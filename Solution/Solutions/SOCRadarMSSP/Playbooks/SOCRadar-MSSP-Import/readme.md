# SOCRadar MSSP Import

Imports alarms from multiple SOCRadar company accounts into Microsoft Sentinel with per-tenant error isolation.

## Features

- Multi-tenant: imports alarms from all configured companies in a single Logic App
- Error isolation: one company failure does not affect others (Scope Try/Catch)
- Sequential company processing with concurrent alarm creation (5 parallel)
- 4-tag system: SOCRadar + MSSP-{CompanyName} + alarm_main_type + alarm_sub_type
- Title format: [MSSP-{CompanyName}] #{alarm_id} - {title}
- Supports all alarm statuses or OPEN-only (ImportAllStatuses parameter)
- Optional audit logging and alarms table with CompanyName/CompanyId columns
- Deduplication via Sentinel API query
- Pagination for both SOCRadar API and Sentinel API

## Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| PlaybookName | No | SOCRadar-MSSP-Import | Logic App name |
| CompanyConfigs | Yes | - | JSON object with companies array (secureObject) |
| WorkspaceName | Yes | - | Sentinel workspace name |
| PollingIntervalMinutes | No | 5 | Polling interval (1-60 min) |
| InitialLookbackMinutes | No | 600 | First run lookback (10 hours) |
| ImportAllStatuses | No | false | Import all statuses or OPEN only |
| EnableAuditLogging | No | false | Enable audit log table |
| EnableAlarmsTable | No | false | Enable alarms custom table |

## CompanyConfigs Format

```json
{
    "companies": [
        { "CompanyId": "330", "CompanyName": "ACME Corp", "ApiKey": "your-api-key-here" },
        { "CompanyId": "331", "CompanyName": "Globex Inc", "ApiKey": "another-api-key" }
    ]
}
```

## Prerequisites

- Deploy the Infrastructure playbook first
- Microsoft Sentinel enabled workspace

## Deployment

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure%2FAzure-Sentinel%2Fmaster%2FSolutions%2FSOCRadarMSSP%2FPlaybooks%2FSOCRadar-MSSP-Import%2Fazuredeploy.json)

## Roles Assigned

- Microsoft Sentinel Contributor (Resource Group scope)
- Log Analytics Reader (Workspace scope)
