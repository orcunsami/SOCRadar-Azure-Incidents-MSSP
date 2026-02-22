#!/bin/bash
# SOCRadar MSSP Azure FAST RESET
# Deletes EVERYTHING without confirmation - for dev/test only!
# Usage: ./mssp-reset.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load config
if [ -f "$SCRIPT_DIR/test.config" ]; then
    source "$SCRIPT_DIR/test.config" 2>/dev/null
fi

# Validate
if [ -z "$SUBSCRIPTION_ID" ] || [ -z "$RESOURCE_GROUP" ]; then
    echo "ERROR: Missing config. Copy test.config.example to test.config and fill values."
    exit 1
fi

IMPORT_NAME="${IMPORT_PLAYBOOK_NAME:-SOCRadar-MSSP-Import}"
SYNC_NAME="${SYNC_PLAYBOOK_NAME:-SOCRadar-MSSP-Sync}"
WORKSPACE_NAME="${WORKSPACE_NAME:-}"

echo "=== MSSP FAST RESET ==="
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Import: $IMPORT_NAME"
echo "  Sync: $SYNC_NAME"
echo ""

# 1. Disable Logic Apps (stop burning money)
echo "[1/7] Disabling Logic Apps..."
az logic workflow update --name "$IMPORT_NAME" -g "$RESOURCE_GROUP" --state Disabled -o none 2>/dev/null || true
az logic workflow update --name "$SYNC_NAME" -g "$RESOURCE_GROUP" --state Disabled -o none 2>/dev/null || true
echo "  Done"

# 2. Delete Role Assignments
echo "[2/7] Deleting Role Assignments..."
for id in $(az role assignment list --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" --query "[?principalType=='ServicePrincipal'].id" -o tsv 2>/dev/null); do
    az role assignment delete --ids "$id" 2>/dev/null || true
done
# Workspace-scoped role assignments
if [ -n "$WORKSPACE_NAME" ]; then
    WS_SCOPE="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.OperationalInsights/workspaces/$WORKSPACE_NAME"
    for id in $(az role assignment list --scope "$WS_SCOPE" --query "[?principalType=='ServicePrincipal'].id" -o tsv 2>/dev/null); do
        az role assignment delete --ids "$id" 2>/dev/null || true
    done
fi
echo "  Done"

# 3. Delete Logic Apps
echo "[3/7] Deleting Logic Apps..."
az logic workflow delete --name "$IMPORT_NAME" -g "$RESOURCE_GROUP" --yes 2>/dev/null || true
az logic workflow delete --name "$SYNC_NAME" -g "$RESOURCE_GROUP" --yes 2>/dev/null || true
echo "  Done"

# 4. Delete API Connections
echo "[4/7] Deleting API Connections..."
for conn in $(az resource list -g "$RESOURCE_GROUP" --resource-type "Microsoft.Web/connections" --query "[?starts_with(name, 'azuresentinel-')].name" -o tsv 2>/dev/null); do
    az resource delete --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.Web/connections" --name "$conn" 2>/dev/null || true
done
echo "  Done"

# 5. Delete DCRs and DCE (audit infrastructure)
echo "[5/7] Deleting Audit Infrastructure..."
az monitor data-collection rule delete --name "SOCRadar-MSSP-Alarms-DCR" -g "$RESOURCE_GROUP" --yes 2>/dev/null || true
az monitor data-collection rule delete --name "SOCRadar-MSSP-Audit-DCR" -g "$RESOURCE_GROUP" --yes 2>/dev/null || true
az monitor data-collection endpoint delete --name "SOCRadar-MSSP-DCE" -g "$RESOURCE_GROUP" --yes 2>/dev/null || true
echo "  Done"

# 6. Delete Custom Tables
echo "[6/7] Deleting Custom Tables..."
if [ -n "$WORKSPACE_NAME" ]; then
    az monitor log-analytics workspace table delete --workspace-name "$WORKSPACE_NAME" -g "$RESOURCE_GROUP" --name "SOCRadar_Alarms_CL" --yes 2>/dev/null || true
    az monitor log-analytics workspace table delete --workspace-name "$WORKSPACE_NAME" -g "$RESOURCE_GROUP" --name "SOCRadarAuditLog_CL" --yes 2>/dev/null || true
fi
echo "  Done"

# 7. Delete Sentinel Incidents
echo "[7/7] Deleting MSSP Incidents..."
if [ -n "$WORKSPACE_NAME" ]; then
    SENTINEL_URL="https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.OperationalInsights/workspaces/$WORKSPACE_NAME/providers/Microsoft.SecurityInsights"

    INCIDENTS=$(az rest --method GET \
        --url "$SENTINEL_URL/incidents?api-version=2023-11-01&\$top=1000&\$filter=startswith(properties/title, '[MSSP-')" \
        --query "value[].name" -o tsv 2>/dev/null || echo "")

    count=0
    for name in $INCIDENTS; do
        [ -z "$name" ] && continue
        az rest --method DELETE \
            --url "$SENTINEL_URL/incidents/$name?api-version=2023-11-01" \
            2>/dev/null || true
        count=$((count + 1))
    done
    echo "  Deleted $count incidents"
else
    echo "  Skipped (no WORKSPACE_NAME)"
fi

echo ""
echo "=== MSSP RESET COMPLETE ==="
echo ""
ALL_RESOURCES=$(az resource list -g "$RESOURCE_GROUP" --query "length(@)" -o tsv 2>/dev/null || echo "0")
echo "  Resources in RG: $ALL_RESOURCES"

if [ "$ALL_RESOURCES" = "0" ]; then
    echo ""
    echo "  RG is CLEAN - ready for fresh deploy!"
else
    echo ""
    echo "  Remaining resources:"
    az resource list -g "$RESOURCE_GROUP" --query "[].{name:name, type:type}" -o table 2>/dev/null
fi
