#!/bin/bash
# SOCRadar MSSP Azure FAST RESET
# Deletes EVERYTHING without confirmation - for dev/test only!
# Usage: ./mssp-reset.sh [workspace_name]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load config from test.config if exists
if [ -f "$SCRIPT_DIR/test.config" ]; then
    source "$SCRIPT_DIR/test.config" 2>/dev/null
fi

# Override workspace from CLI arg if provided
if [ -n "$1" ]; then
    WORKSPACE_NAME="$1"
fi

# Validate required vars
if [ -z "$SUBSCRIPTION_ID" ] || [ -z "$RESOURCE_GROUP" ] || [ -z "$WORKSPACE_NAME" ]; then
    echo "ERROR: Missing config. Copy test.config.example to test.config and fill values."
    exit 1
fi

echo "=== MSSP FAST RESET ==="
echo "  Workspace: $WORKSPACE_NAME"
echo "  Resource Group: $RESOURCE_GROUP"
echo ""

# 1. Disable Logic Apps (stop burning money)
echo "[1/11] Disabling Logic Apps..."
az logic workflow update --name "SOCRadar-MSSP-Import" -g "$RESOURCE_GROUP" --state Disabled -o none 2>/dev/null || true
az logic workflow update --name "SOCRadar-MSSP-Sync" -g "$RESOURCE_GROUP" --state Disabled -o none 2>/dev/null || true
echo "  Done"

# 2. Delete Role Assignments (FIRST - prevents RoleAssignmentUpdateNotPermitted on redeploy)
echo "[2/11] Deleting Role Assignments..."
for id in $(az role assignment list --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" --query "[?principalType=='ServicePrincipal'].id" -o tsv 2>/dev/null); do
    az role assignment delete --ids "$id" 2>/dev/null || true
done
for id in $(az role assignment list --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.OperationalInsights/workspaces/$WORKSPACE_NAME" --query "[?principalType=='ServicePrincipal'].id" -o tsv 2>/dev/null); do
    az role assignment delete --ids "$id" 2>/dev/null || true
done
echo "  Done"

# 3. Delete Logic Apps
echo "[3/11] Deleting Logic Apps..."
az logic workflow delete --name "SOCRadar-MSSP-Import" -g "$RESOURCE_GROUP" --yes 2>/dev/null &
az logic workflow delete --name "SOCRadar-MSSP-Sync" -g "$RESOURCE_GROUP" --yes 2>/dev/null &
wait
echo "  Done"

# 4. Delete API Connections
echo "[4/11] Deleting API Connections..."
az resource delete --ids "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/connections/azuresentinel-socradar-mssp-shared" 2>/dev/null || true
echo "  Done"

# 5. Delete DCRs FIRST (depend on DCE)
echo "[5/11] Deleting DCRs..."
az monitor data-collection rule delete --name "SOCRadar-MSSP-Alarms-DCR" -g "$RESOURCE_GROUP" --yes 2>/dev/null &
az monitor data-collection rule delete --name "SOCRadar-MSSP-Audit-DCR" -g "$RESOURCE_GROUP" --yes 2>/dev/null &
wait
echo "  Done"

# 6. Delete DCE (after DCRs)
echo "[6/11] Deleting DCE..."
az monitor data-collection endpoint delete --name "SOCRadar-MSSP-DCE" -g "$RESOURCE_GROUP" --yes 2>/dev/null || true
echo "  Done"

# 7. Delete Custom Tables
echo "[7/11] Deleting Custom Tables..."
az monitor log-analytics workspace table delete --workspace-name "$WORKSPACE_NAME" -g "$RESOURCE_GROUP" --name "SOCRadar_Alarms_CL" --yes 2>/dev/null &
az monitor log-analytics workspace table delete --workspace-name "$WORKSPACE_NAME" -g "$RESOURCE_GROUP" --name "SOCRadarAuditLog_CL" --yes 2>/dev/null &
wait
echo "  Done"

# 8. Delete Workbooks
echo "[8/11] Deleting Workbooks..."
for id in $(az resource list -g "$RESOURCE_GROUP" --resource-type "Microsoft.Insights/workbooks" --query "[].id" -o tsv 2>/dev/null); do
    az resource delete --ids "$id" 2>/dev/null || true
done
echo "  Done"

# 9. Delete MSSP Incidents (only [MSSP- prefixed)
echo "[9/11] Deleting MSSP Incidents..."
BASE_URL="https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.OperationalInsights/workspaces/$WORKSPACE_NAME/providers/Microsoft.SecurityInsights/incidents"
INC_IDS_FILE=$(mktemp)
az rest --method GET --url "$BASE_URL?api-version=2023-11-01&\$top=1000&\$filter=startswith(properties/title, '[MSSP-')" --query "value[].name" -o tsv 2>/dev/null > "$INC_IDS_FILE" || true
count=$(wc -l < "$INC_IDS_FILE" | tr -d ' ')

if [ "$count" = "0" ] || [ ! -s "$INC_IDS_FILE" ]; then
    echo "  No MSSP incidents"
else
    echo "  Deleting $count MSSP incidents..."
    deleted=0
    while IFS= read -r id; do
        [ -z "$id" ] && continue
        az rest --method DELETE --url "$BASE_URL/$id?api-version=2023-11-01" >/dev/null 2>&1 &
        deleted=$((deleted + 1))
        if [ $((deleted % 25)) -eq 0 ]; then
            wait
            echo "  Deleted: $deleted / $count"
        fi
    done < "$INC_IDS_FILE"
    wait
    echo "  $deleted incidents deleted"
fi
rm -f "$INC_IDS_FILE"

# 10. Delete Sentinel (onboarding + solutions)
echo "[10/11] Deleting Sentinel..."
az rest --method DELETE --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.OperationalInsights/workspaces/$WORKSPACE_NAME/providers/Microsoft.SecurityInsights/onboardingStates/default?api-version=2024-03-01" 2>/dev/null || true
az resource delete --ids "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.OperationsManagement/solutions/SecurityInsights($WORKSPACE_NAME)" 2>/dev/null || true
echo "  Done"

# 11. Delete Workspace
echo "[11/11] Deleting Workspace..."
az monitor log-analytics workspace delete --workspace-name "$WORKSPACE_NAME" -g "$RESOURCE_GROUP" --force --yes 2>/dev/null || true
echo "  Done"

echo ""
echo "=== MSSP RESET COMPLETE ==="
echo ""
ALL_RESOURCES=$(az resource list -g "$RESOURCE_GROUP" --query "length(@)" -o tsv 2>/dev/null || echo "0")
ROLE_COUNT=$(az role assignment list --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" --query "[?principalType=='ServicePrincipal'] | length(@)" -o tsv 2>/dev/null || echo "0")
echo "  Resources in RG: $ALL_RESOURCES"
echo "  Role Assignments: $ROLE_COUNT"

if [ "$ALL_RESOURCES" = "0" ] && [ "$ROLE_COUNT" = "0" ]; then
    echo ""
    echo "  RG is CLEAN - ready for fresh deploy!"
else
    echo ""
    echo "  WARNING: Remaining resources:"
    az resource list -g "$RESOURCE_GROUP" --query "[].{name:name, type:type}" -o table 2>/dev/null
fi
echo ""
echo "NOTE: Use a NEW workspace name (soft-delete recovers old data for 14 days)"
