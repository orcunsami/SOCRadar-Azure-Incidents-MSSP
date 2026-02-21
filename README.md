# SOCRadar MSSP Alarms for Microsoft Sentinel

Multi-tenant bidirectional integration between SOCRadar XTI Platform and Microsoft Sentinel for MSSP environments.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Forcunsami%2FSOCRadar-Azure-Incidents-MSSP%2Fmaster%2Fazuredeploy.json)

## Prerequisites

- Microsoft Sentinel workspace
- SOCRadar API Keys for each managed company

## Configuration

### Required Parameters

| Parameter | Description |
|-----------|-------------|
| `WorkspaceName` | Your Sentinel workspace name (e.g., `my-sentinel-workspace`, NOT the Workspace ID/GUID) |
| `WorkspaceLocation` | Region of your workspace (e.g., `centralus`, `northeurope`) |
| `CompanyConfigs` | JSON object with company array (see format below) |

### CompanyConfigs Format

```json
{
  "companies": [
    {
      "CompanyId": "330",
      "CompanyName": "ACME-Corp",
      "ApiKey": "your-api-key-here"
    },
    {
      "CompanyId": "331",
      "CompanyName": "Beta-Inc",
      "ApiKey": "another-api-key"
    }
  ]
}
```

> **Note:** CompanyName is used in incident titles (`[MSSP-ACME-Corp] #12345 - ...`) and as a Sentinel tag. Keep it short and without special characters.

### Optional Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `PollingIntervalMinutes` | 5 | How often to check for alarms (1-60 min) |
| `InitialLookbackMinutes` | 600 | First run lookback (default: 10 hours) |
| `ImportAllStatuses` | false | Import all statuses or only OPEN |
| `EnableAuditLogging` | true | Log operations to Log Analytics |
| `EnableAlarmsTable` | true | Store alarms in SOCRadar_Alarms_CL table |
| `EnableWorkbook` | true | Deploy MSSP Analytics Dashboard |
| `TableRetentionDays` | 365 | Data retention (30-730 days) |

## What Gets Deployed

- **SOCRadar-MSSP-Import** - Imports alarms from all configured companies as Sentinel incidents
- **SOCRadar-MSSP-Sync** - Syncs closed incidents back to the correct SOCRadar tenant
- **SOCRadar_Alarms_CL** - Custom table with CompanyId/CompanyName columns
- **SOCRadar MSSP Dashboard** - Workbook with company selector and cross-tenant analysis
- **SOCRadarAuditLog_CL** - Audit log table with per-company tracking
- **Data Collection Endpoint & Rules** - For data ingestion

## Key Features

**Multi-Tenant Import**
- Sequential company processing (concurrency=1) to avoid variable conflicts
- Per-company error isolation (Scope Try-Catch)
- 4-tag system: SOCRadar + MSSP-CompanyName + alarm_main_type + alarm_sub_type
- Title format: `[MSSP-CompanyName] #AlarmID - Title`
- Duplicate prevention across all companies

**Bidirectional Sync**
- Extracts company name from incident title
- Routes to correct SOCRadar tenant API key
- Classification mapping: TruePositive, FalsePositive, BenignPositive

**MSSP Dashboard**
- Company selector dropdown
- Per-company severity breakdown
- Cross-tenant threat correlation
- Tenant health monitoring

## Post-Deployment

Logic Apps start 3 minutes after deployment to allow Azure role propagation. No manual action required.

## Redeployment

Role assignments are generated with deployment-scoped unique identifiers. This means you can safely delete all resources and redeploy without running into `RoleAssignmentUpdateNotPermitted` errors. Previous role assignments from old deployments are automatically orphaned and do not affect the new deployment.

## About SOCRadar

SOCRadar is an Extended Threat Intelligence (XTI) platform that provides actionable threat intelligence, digital risk protection, and external attack surface management.

Learn more at [socradar.io](https://socradar.io)

## Support

- **Documentation:** [docs.socradar.io](https://docs.socradar.io)
- **Support:** support@socradar.io
