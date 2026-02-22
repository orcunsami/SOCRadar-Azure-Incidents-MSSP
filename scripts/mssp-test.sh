#!/bin/bash
# SOCRadar MSSP Test Script
# Enables Logic Apps, waits for runs, verifies, DISABLES
# Usage: ./mssp-test.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load config
if [ -f "$SCRIPT_DIR/test.config" ]; then
    source "$SCRIPT_DIR/test.config" 2>/dev/null
fi

# Validate
if [ -z "$SUBSCRIPTION_ID" ] || [ -z "$RESOURCE_GROUP" ] || [ -z "$WORKSPACE_NAME" ]; then
    echo "ERROR: Missing config."
    exit 1
fi

# CRITICAL: Disable Logic Apps on ANY exit (crash, error, Ctrl+C)
# 5587 TL lesson: NEVER leave Logic Apps enabled!
cleanup() {
    echo ""
    echo "  Disabling Logic Apps (cleanup)..."
    az logic workflow update --name "SOCRadar-MSSP-Import" -g "$RESOURCE_GROUP" --state Disabled -o none 2>/dev/null || true
    az logic workflow update --name "SOCRadar-MSSP-Sync" -g "$RESOURCE_GROUP" --state Disabled -o none 2>/dev/null || true
}
trap cleanup EXIT

POLLING="${POLLING_INTERVAL_MINUTES:-5}"
BASE_URL="https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"
SENTINEL_URL="$BASE_URL/providers/Microsoft.OperationalInsights/workspaces/$WORKSPACE_NAME/providers/Microsoft.SecurityInsights"
PASSED=0
FAILED=0
TOTAL=0

pass() {
    PASSED=$((PASSED + 1))
    TOTAL=$((TOTAL + 1))
    echo "  PASS: $1"
}

fail() {
    FAILED=$((FAILED + 1))
    TOTAL=$((TOTAL + 1))
    echo "  FAIL: $1"
}

echo "=== MSSP TEST ==="
echo "  Workspace: $WORKSPACE_NAME"
echo "  Polling: ${POLLING}m"
echo ""

# 1. Check Logic Apps exist
echo "[1/8] Checking Logic Apps..."
IMPORT_STATE=$(az logic workflow show --name "SOCRadar-MSSP-Import" -g "$RESOURCE_GROUP" --query "state" -o tsv 2>/dev/null || echo "MISSING")
SYNC_STATE=$(az logic workflow show --name "SOCRadar-MSSP-Sync" -g "$RESOURCE_GROUP" --query "state" -o tsv 2>/dev/null || echo "MISSING")

if [ "$IMPORT_STATE" != "MISSING" ]; then pass "Import Logic App exists ($IMPORT_STATE)"; else fail "Import Logic App MISSING"; fi
if [ "$SYNC_STATE" != "MISSING" ]; then pass "Sync Logic App exists ($SYNC_STATE)"; else fail "Sync Logic App MISSING"; fi

# 2. Check infrastructure
echo ""
echo "[2/8] Checking Infrastructure..."
DCE_EXISTS=$(az monitor data-collection endpoint show --name "SOCRadar-MSSP-DCE" -g "$RESOURCE_GROUP" --query "name" -o tsv 2>/dev/null || echo "MISSING")
ALARMS_DCR=$(az monitor data-collection rule show --name "SOCRadar-MSSP-Alarms-DCR" -g "$RESOURCE_GROUP" --query "name" -o tsv 2>/dev/null || echo "MISSING")
AUDIT_DCR=$(az monitor data-collection rule show --name "SOCRadar-MSSP-Audit-DCR" -g "$RESOURCE_GROUP" --query "name" -o tsv 2>/dev/null || echo "MISSING")

if [ "$DCE_EXISTS" != "MISSING" ]; then pass "DCE exists"; else fail "DCE MISSING"; fi
if [ "$ALARMS_DCR" != "MISSING" ]; then pass "Alarms DCR exists"; else fail "Alarms DCR MISSING"; fi
if [ "$AUDIT_DCR" != "MISSING" ]; then pass "Audit DCR exists"; else fail "Audit DCR MISSING"; fi

# 3. Check role assignments
echo ""
echo "[3/8] Checking Role Assignments..."
ROLE_COUNT=$(az role assignment list --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" --query "[?principalType=='ServicePrincipal'] | length(@)" -o tsv 2>/dev/null || echo "0")
if [ "$ROLE_COUNT" -ge 3 ]; then pass "Role assignments: $ROLE_COUNT (>=3)"; else fail "Role assignments: $ROLE_COUNT (<3)"; fi

# 4. Enable and wait for Import
echo ""
echo "[4/8] Enabling Import Logic App..."
az logic workflow update --name "SOCRadar-MSSP-Import" -g "$RESOURCE_GROUP" --state Enabled -o none

WAIT_SECONDS=$(( (POLLING * 60) + 120 ))
echo "  Waiting ${WAIT_SECONDS}s for first run (polling=${POLLING}m + 2min buffer)..."
sleep "$WAIT_SECONDS"

# 5. Check Import results
echo ""
echo "[5/8] Checking Import results..."
INCIDENT_COUNT=$(az rest --method GET --url "$SENTINEL_URL/incidents?api-version=2023-11-01&\$top=1000&\$filter=startswith(properties/title, '[MSSP-')" --query "value | length(@)" -o tsv 2>/dev/null || echo "0")
echo "  MSSP incidents found: $INCIDENT_COUNT"

if [ "$INCIDENT_COUNT" -gt 0 ]; then
    pass "Incidents created: $INCIDENT_COUNT"

    # Check title format
    FIRST_TITLE=$(az rest --method GET --url "$SENTINEL_URL/incidents?api-version=2023-11-01&\$top=1&\$filter=startswith(properties/title, '[MSSP-')" --query "value[0].properties.title" -o tsv 2>/dev/null || echo "")
    echo "  Sample title: $FIRST_TITLE"

    if echo "$FIRST_TITLE" | grep -q '\[MSSP-.*\] #[0-9]'; then
        pass "Title format correct: [MSSP-CompanyName] #ID - ..."
    else
        fail "Title format unexpected"
    fi

    # Check tags (4-tag system)
    TAGS=$(az rest --method GET --url "$SENTINEL_URL/incidents?api-version=2023-11-01&\$top=1&\$filter=startswith(properties/title, '[MSSP-')" --query "value[0].properties.labels[].labelName" -o tsv 2>/dev/null || echo "")
    echo "  Tags: $TAGS"

    if echo "$TAGS" | grep -q "SOCRadar"; then
        pass "SOCRadar tag present"
    else
        fail "SOCRadar tag MISSING"
    fi

    if echo "$TAGS" | grep -q "MSSP-"; then
        pass "MSSP-CompanyName tag present"
    else
        fail "MSSP-CompanyName tag MISSING"
    fi
else
    fail "No incidents created"
fi

# 6. Duplicate test - wait for second run
echo ""
echo "[6/8] Duplicate test - waiting for second run..."
sleep $(( POLLING * 60 + 60 ))

NEW_COUNT=$(az rest --method GET --url "$SENTINEL_URL/incidents?api-version=2023-11-01&\$top=1000&\$filter=startswith(properties/title, '[MSSP-')" --query "value | length(@)" -o tsv 2>/dev/null || echo "0")
echo "  Incidents after 2nd run: $NEW_COUNT (was: $INCIDENT_COUNT)"

if [ "$NEW_COUNT" = "$INCIDENT_COUNT" ]; then
    pass "Duplicate prevention working (count unchanged)"
else
    DIFF=$((NEW_COUNT - INCIDENT_COUNT))
    if [ "$DIFF" -le 0 ]; then
        pass "No duplicates (count: $NEW_COUNT)"
    else
        fail "Possible duplicates: $DIFF new incidents"
    fi
fi

# 7. IMMEDIATELY DISABLE Import (stop burning money!)
echo ""
echo "[7/8] DISABLING Logic Apps..."
az logic workflow update --name "SOCRadar-MSSP-Import" -g "$RESOURCE_GROUP" --state Disabled -o none
az logic workflow update --name "SOCRadar-MSSP-Sync" -g "$RESOURCE_GROUP" --state Disabled -o none
echo "  Both Logic Apps DISABLED"

# 8. Verify disabled
echo ""
echo "[8/8] Verifying disabled..."
IMPORT_STATE=$(az logic workflow show --name "SOCRadar-MSSP-Import" -g "$RESOURCE_GROUP" --query "state" -o tsv 2>/dev/null || echo "UNKNOWN")
SYNC_STATE=$(az logic workflow show --name "SOCRadar-MSSP-Sync" -g "$RESOURCE_GROUP" --query "state" -o tsv 2>/dev/null || echo "UNKNOWN")

if [ "$IMPORT_STATE" = "Disabled" ]; then pass "Import DISABLED"; else fail "Import NOT disabled: $IMPORT_STATE"; fi
if [ "$SYNC_STATE" = "Disabled" ]; then pass "Sync DISABLED"; else fail "Sync NOT disabled: $SYNC_STATE"; fi

# Summary
echo ""
echo "======================================="
echo "  MSSP TEST RESULTS"
echo "  Passed: $PASSED / $TOTAL"
echo "  Failed: $FAILED / $TOTAL"
echo "======================================="
echo ""

if [ "$FAILED" -gt 0 ]; then
    echo "  SOME TESTS FAILED!"
    exit 1
else
    echo "  ALL TESTS PASSED!"
fi
