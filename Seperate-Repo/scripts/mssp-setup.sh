#!/bin/bash
# SOCRadar MSSP Azure Setup
# Deploys Import + Sync Logic Apps (Enabled with 3-min delay) + verifies roles
# Usage: ./mssp-setup.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMPORT_TEMPLATE="$SCRIPT_DIR/../playbooks/SOCRadar-MSSP-Import/azuredeploy.json"
SYNC_TEMPLATE="$SCRIPT_DIR/../playbooks/SOCRadar-MSSP-Sync/azuredeploy.json"
INFRA_TEMPLATE="$SCRIPT_DIR/../playbooks/SOCRadar-MSSP-Infrastructure/azuredeploy.json"

# Load config
if [ -f "$SCRIPT_DIR/test.config" ]; then
    source "$SCRIPT_DIR/test.config" 2>/dev/null
fi

# Load secrets (.env should have COMPANY_CONFIGS as JSON string)
if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env" 2>/dev/null
fi

# Validate
if [ -z "$SUBSCRIPTION_ID" ] || [ -z "$RESOURCE_GROUP" ] || [ -z "$WORKSPACE_NAME" ]; then
    echo "ERROR: Missing config. Copy test.config.example to test.config and fill values."
    echo "  Required: SUBSCRIPTION_ID, RESOURCE_GROUP, WORKSPACE_NAME"
    exit 1
fi

if [ -z "$COMPANY_CONFIGS" ]; then
    echo "ERROR: COMPANY_CONFIGS not set."
    echo "  Create .env with:"
    echo '  COMPANY_CONFIGS='"'"'{"companies":[{"CompanyId":"330","CompanyName":"TestCo","ApiKey":"xxx"}]}'"'"''
    exit 1
fi

LOCATION="${LOCATION:-northeurope}"
POLLING="${POLLING_INTERVAL_MINUTES:-5}"
IMPORT_NAME="${IMPORT_PLAYBOOK_NAME:-SOCRadar-MSSP-Import}"
SYNC_NAME="${SYNC_PLAYBOOK_NAME:-SOCRadar-MSSP-Sync}"
AUDIT="${ENABLE_AUDIT_LOGGING:-false}"
ALARMS="${ENABLE_ALARMS_TABLE:-false}"

echo "=== MSSP DEPLOY ==="
echo "  Workspace: $WORKSPACE_NAME"
echo "  Location: $LOCATION"
echo "  Import: $IMPORT_NAME"
echo "  Sync: $SYNC_NAME"
echo "  Polling: ${POLLING}m"
echo ""

# 1. Deploy Infrastructure (if audit or alarms table enabled)
if [ "$AUDIT" = "true" ] || [ "$ALARMS" = "true" ]; then
    echo "[1/5] Deploying Infrastructure template..."
    az deployment group create \
        --resource-group "$RESOURCE_GROUP" \
        --template-file "$INFRA_TEMPLATE" \
        --parameters \
            WorkspaceName="$WORKSPACE_NAME" \
        -o table
    echo ""
else
    echo "[1/5] Skipping Infrastructure (audit/alarms disabled)"
    echo ""
fi

# 2. Deploy Import Logic App
echo "[2/5] Deploying Import Logic App..."
az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$IMPORT_TEMPLATE" \
    --parameters \
        PlaybookName="$IMPORT_NAME" \
        CompanyConfigs="$COMPANY_CONFIGS" \
        WorkspaceName="$WORKSPACE_NAME" \
        PollingIntervalMinutes="$POLLING" \
        InitialLookbackMinutes="${INITIAL_LOOKBACK_MINUTES:-600}" \
        ImportAllStatuses="${IMPORT_ALL_STATUSES:-false}" \
        EnableAuditLogging="$AUDIT" \
        EnableAlarmsTable="$ALARMS" \
    -o table
echo ""

# 3. Deploy Sync Logic App
echo "[3/5] Deploying Sync Logic App..."
az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$SYNC_TEMPLATE" \
    --parameters \
        PlaybookName="$SYNC_NAME" \
        CompanyConfigs="$COMPANY_CONFIGS" \
        WorkspaceName="$WORKSPACE_NAME" \
        PollingIntervalMinutes="$POLLING" \
    -o table
echo ""

# 4. Verify role assignments
echo "[4/5] Verifying role assignments..."
for name in "$IMPORT_NAME" "$SYNC_NAME"; do
    PRINCIPAL=$(az logic workflow show --name "$name" -g "$RESOURCE_GROUP" --query "identity.principalId" -o tsv 2>/dev/null || echo "MISSING")
    echo "  $name principal: $PRINCIPAL"
done

ROLE_COUNT=$(az role assignment list --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" --query "[?principalType=='ServicePrincipal'] | length(@)" -o tsv 2>/dev/null || echo "0")
echo "  Total role assignments: $ROLE_COUNT"
echo ""

# 5. Wait for role propagation
echo "[5/5] Waiting 90s for role propagation..."
sleep 90

echo ""
echo "=== DEPLOY COMPLETE ==="
echo ""
echo "Logic Apps have 3-minute delayed start. Use mssp-test.sh to test."
echo ""
echo "Resources deployed:"
az resource list -g "$RESOURCE_GROUP" --query "[].{name:name, type:type}" -o table 2>/dev/null
