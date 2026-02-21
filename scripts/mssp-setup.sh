#!/bin/bash
# SOCRadar MSSP Azure Setup
# Deploys combined template (disabled) + verifies roles + enables
# Usage: ./mssp-setup.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_PATH="$SCRIPT_DIR/../azuredeploy.json"

# Load config
if [ -f "$SCRIPT_DIR/test.config" ]; then
    source "$SCRIPT_DIR/test.config" 2>/dev/null
fi

# Validate
if [ -z "$SUBSCRIPTION_ID" ] || [ -z "$RESOURCE_GROUP" ] || [ -z "$WORKSPACE_NAME" ] || [ -z "$COMPANY_CONFIGS" ]; then
    echo "ERROR: Missing config. Copy test.config.example to test.config and fill values."
    echo "  Required: SUBSCRIPTION_ID, RESOURCE_GROUP, WORKSPACE_NAME, COMPANY_CONFIGS"
    exit 1
fi

if [ ! -f "$TEMPLATE_PATH" ]; then
    echo "ERROR: Template not found: $TEMPLATE_PATH"
    exit 1
fi

LOCATION="${LOCATION:-northeurope}"
POLLING="${POLLING_INTERVAL_MINUTES:-5}"
LOOKBACK="${INITIAL_LOOKBACK_MINUTES:-600}"
IMPORT_ALL="${IMPORT_ALL_STATUSES:-false}"

echo "=== MSSP DEPLOY ==="
echo "  Template: $TEMPLATE_PATH"
echo "  Workspace: $WORKSPACE_NAME"
echo "  Location: $LOCATION"
echo "  Polling: ${POLLING}m"
echo "  Lookback: ${LOOKBACK}m"
echo "  Import All: $IMPORT_ALL"
echo ""

# Deploy
echo "[1/4] Deploying template..."
az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$TEMPLATE_PATH" \
    --parameters \
        WorkspaceName="$WORKSPACE_NAME" \
        WorkspaceLocation="$LOCATION" \
        CompanyConfigs="$COMPANY_CONFIGS" \
        PollingIntervalMinutes="$POLLING" \
        InitialLookbackMinutes="$LOOKBACK" \
        ImportAllStatuses="$IMPORT_ALL" \
        EnableAuditLogging=true \
        EnableAlarmsTable=true \
        EnableWorkbook=true \
        TableRetentionDays=90 \
    -o table

echo ""
echo "[2/4] Verifying role assignments..."
IMPORT_PRINCIPAL=$(az logic workflow show --name "SOCRadar-MSSP-Import" -g "$RESOURCE_GROUP" --query "identity.principalId" -o tsv 2>/dev/null || echo "")
SYNC_PRINCIPAL=$(az logic workflow show --name "SOCRadar-MSSP-Sync" -g "$RESOURCE_GROUP" --query "identity.principalId" -o tsv 2>/dev/null || echo "")

echo "  Import principal: $IMPORT_PRINCIPAL"
echo "  Sync principal: $SYNC_PRINCIPAL"

ROLE_COUNT=$(az role assignment list --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" --query "[?principalType=='ServicePrincipal'] | length(@)" -o tsv 2>/dev/null || echo "0")
echo "  Role assignments: $ROLE_COUNT"

echo ""
echo "[3/4] Waiting 90s for role propagation..."
sleep 90

echo ""
echo "[4/4] Disabling Logic Apps (deploy creates them Enabled)..."
az logic workflow update --name "SOCRadar-MSSP-Import" -g "$RESOURCE_GROUP" --state Disabled -o none
az logic workflow update --name "SOCRadar-MSSP-Sync" -g "$RESOURCE_GROUP" --state Disabled -o none
echo "  Both Logic Apps DISABLED"

echo ""
echo "=== DEPLOY COMPLETE ==="
echo ""
echo "Logic Apps are DISABLED. Use mssp-test.sh to enable, test, and disable."
echo ""
echo "Resources deployed:"
az resource list -g "$RESOURCE_GROUP" --query "[].{name:name, type:type}" -o table 2>/dev/null
