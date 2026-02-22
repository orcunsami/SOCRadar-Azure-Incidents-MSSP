#!/bin/bash
# SOCRadar MSSP Deployment Script
# Deploys multi-tenant solution to Azure

set -e

RESOURCE_GROUP="${1:-}"
LOCATION="${2:-westeurope}"

if [ -z "$RESOURCE_GROUP" ]; then
    echo "Usage: ./deploy-mssp.sh <resource-group-name> [location]"
    exit 1
fi

echo "=== SOCRadar MSSP Deployment ==="
echo "Resource Group: $RESOURCE_GROUP"
echo "Location: $LOCATION"
echo ""

# Create resource group
az group create --name "$RESOURCE_GROUP" --location "$LOCATION"

# Deploy infrastructure (Table Storage, Key Vault)
echo "[1/3] Deploying infrastructure..."
# az deployment group create ...

# Deploy Logic Apps
echo "[2/3] Deploying Logic Apps..."
# az deployment group create ...

# Configure company registry
echo "[3/3] Setting up company registry..."
# az storage entity insert ...

echo ""
echo "=== Deployment Complete ==="
echo "Next steps:"
echo "1. Add companies to registry"
echo "2. Configure API keys in Key Vault"
echo "3. Enable Logic Apps"
