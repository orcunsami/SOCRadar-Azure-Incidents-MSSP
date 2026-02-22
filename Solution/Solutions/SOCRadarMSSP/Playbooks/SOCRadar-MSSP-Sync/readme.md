# SOCRadar MSSP Sync

Syncs closed Sentinel incidents back to the correct SOCRadar tenant with classification mapping and automatic company routing.

## Features

- Automatic company routing: extracts company name from incident title
- Company config lookup: matches company name to find correct API key
- Classification mapping: FalsePositive, BenignPositive, TruePositive
- Synced tag prevents duplicate syncs
- PUT-based incident update (Sentinel API requirement)
- Pagination for 1000+ incidents

## How It Works

1. Queries closed incidents with SOCRadar label and MSSP title prefix
2. For each incident, extracts the company name from `[MSSP-{CompanyName}]` in the title
3. Looks up the matching company config to find the API key
4. Updates SOCRadar alarm status and severity using the tenant-specific API key
5. Adds "Synced" tag to prevent re-processing

## Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| PlaybookName | No | SOCRadar-MSSP-Sync | Logic App name |
| CompanyConfigs | Yes | - | Same JSON as Import (secureObject) |
| WorkspaceName | Yes | - | Sentinel workspace name |
| PollingIntervalMinutes | No | 5 | Polling interval (1-1440 min) |

## Prerequisites

- SOCRadar-MSSP-Import must be deployed and running
- Same CompanyConfigs used for both Import and Sync

## Deployment

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure%2FAzure-Sentinel%2Fmaster%2FSolutions%2FSOCRadarMSSP%2FPlaybooks%2FSOCRadar-MSSP-Sync%2Fazuredeploy.json)

## Roles Assigned

- Microsoft Sentinel Contributor (Resource Group scope)
