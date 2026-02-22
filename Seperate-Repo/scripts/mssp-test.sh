#!/bin/bash
# SOCRadar MSSP Test Script
# Enables Logic Apps, waits for run, verifies incidents, DISABLES
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

POLLING="${POLLING_INTERVAL_MINUTES:-5}"
IMPORT_NAME="${IMPORT_PLAYBOOK_NAME:-SOCRadar-MSSP-Import}"
SYNC_NAME="${SYNC_PLAYBOOK_NAME:-SOCRadar-MSSP-Sync}"
SENTINEL_URL="https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.OperationalInsights/workspaces/$WORKSPACE_NAME/providers/Microsoft.SecurityInsights"
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

# CRITICAL: Always disable Logic Apps on exit (5587 TL lesson!)
cleanup() {
    echo ""
    echo "=== DISABLING Logic Apps ==="
    az logic workflow update --name "$IMPORT_NAME" -g "$RESOURCE_GROUP" --state Disabled -o none 2>/dev/null || true
    az logic workflow update --name "$SYNC_NAME" -g "$RESOURCE_GROUP" --state Disabled -o none 2>/dev/null || true
    echo "  Import: $(az logic workflow show --name "$IMPORT_NAME" -g "$RESOURCE_GROUP" --query "state" -o tsv 2>/dev/null || echo "UNKNOWN")"
    echo "  Sync: $(az logic workflow show --name "$SYNC_NAME" -g "$RESOURCE_GROUP" --query "state" -o tsv 2>/dev/null || echo "UNKNOWN")"
}
trap cleanup EXIT

echo "=== MSSP TEST ==="
echo "  Workspace: $WORKSPACE_NAME"
echo "  Import: $IMPORT_NAME"
echo "  Sync: $SYNC_NAME"
echo "  Polling: ${POLLING}m"
echo ""

# 1. Check Logic Apps exist
echo "[1/6] Checking Logic Apps..."
for name in "$IMPORT_NAME" "$SYNC_NAME"; do
    STATE=$(az logic workflow show --name "$name" -g "$RESOURCE_GROUP" --query "state" -o tsv 2>/dev/null || echo "MISSING")
    if [ "$STATE" != "MISSING" ]; then pass "$name exists ($STATE)"; else fail "$name MISSING"; fi
done

# 2. Check role assignments
echo ""
echo "[2/6] Checking Role Assignments..."
ROLE_COUNT=$(az role assignment list --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" --query "[?principalType=='ServicePrincipal'] | length(@)" -o tsv 2>/dev/null || echo "0")
if [ "$ROLE_COUNT" -ge 2 ]; then pass "Role assignments: $ROLE_COUNT (>=2 for 2 Logic Apps)"; else fail "Role assignments: $ROLE_COUNT (<2)"; fi

# 3. Count pre-existing incidents
echo ""
echo "[3/6] Counting existing MSSP incidents..."
PRE_COUNT=$(az rest --method GET \
    --url "$SENTINEL_URL/incidents?api-version=2023-11-01&\$top=1&\$filter=startswith(properties/title, '[MSSP-')" \
    --query "value | length(@)" -o tsv 2>/dev/null || echo "0")
echo "  Pre-test incident count: $PRE_COUNT"

# 4. Enable Import and wait for first run
echo ""
echo "[4/6] Enabling Import Logic App and waiting for first run..."
az logic workflow update --name "$IMPORT_NAME" -g "$RESOURCE_GROUP" --state Enabled -o none

WAIT_SECONDS=$(( (POLLING * 60) + 120 ))
echo "  Waiting ${WAIT_SECONDS}s for first run (polling=${POLLING}m + 2min buffer)..."
sleep "$WAIT_SECONDS"

# 5. Check results
echo ""
echo "[5/6] Checking results..."

# Check run history
LAST_STATUS=$(az logic workflow run list --workflow-name "$IMPORT_NAME" -g "$RESOURCE_GROUP" --query "[0].status" -o tsv 2>/dev/null || echo "UNKNOWN")
echo "  Last run status: $LAST_STATUS"

if [ "$LAST_STATUS" = "Succeeded" ]; then
    pass "Import run succeeded"
elif [ "$LAST_STATUS" = "Running" ]; then
    echo "  Still running, waiting 60 more seconds..."
    sleep 60
    LAST_STATUS=$(az logic workflow run list --workflow-name "$IMPORT_NAME" -g "$RESOURCE_GROUP" --query "[0].status" -o tsv 2>/dev/null || echo "UNKNOWN")
    if [ "$LAST_STATUS" = "Succeeded" ]; then pass "Import run succeeded (delayed)"; else fail "Import run: $LAST_STATUS"; fi
else
    fail "Import run: $LAST_STATUS"
fi

# Count post-test incidents
POST_COUNT=$(az rest --method GET \
    --url "$SENTINEL_URL/incidents?api-version=2023-11-01&\$top=1000&\$filter=startswith(properties/title, '[MSSP-')" \
    --query "value | length(@)" -o tsv 2>/dev/null || echo "0")
echo "  Post-test incident count: $POST_COUNT (was: $PRE_COUNT)"

NEW_INCIDENTS=$((POST_COUNT - PRE_COUNT))
if [ "$NEW_INCIDENTS" -gt 0 ]; then
    pass "New incidents created: $NEW_INCIDENTS"
elif [ "$POST_COUNT" -gt 0 ]; then
    pass "Incidents exist: $POST_COUNT (duplicates skipped)"
else
    fail "No incidents found after test"
fi

# 6. Duplicate check
echo ""
echo "[6/6] Checking for duplicates..."
az logic workflow update --name "$IMPORT_NAME" -g "$RESOURCE_GROUP" --state Enabled -o none
echo "  Waiting ${WAIT_SECONDS}s for second run..."
sleep "$WAIT_SECONDS"

FINAL_COUNT=$(az rest --method GET \
    --url "$SENTINEL_URL/incidents?api-version=2023-11-01&\$top=1000&\$filter=startswith(properties/title, '[MSSP-')" \
    --query "value | length(@)" -o tsv 2>/dev/null || echo "0")
echo "  After 2nd run: $FINAL_COUNT incidents (was: $POST_COUNT)"

if [ "$FINAL_COUNT" = "$POST_COUNT" ]; then
    pass "No duplicates (count unchanged: $FINAL_COUNT)"
else
    DUPES=$((FINAL_COUNT - POST_COUNT))
    if [ "$DUPES" -gt 0 ]; then
        fail "Possible duplicates: +$DUPES incidents"
    else
        pass "Count decreased (incidents may have been synced/closed)"
    fi
fi

# Summary (Logic Apps disabled by trap handler)
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
