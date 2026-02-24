# SOCRadar MSSP Alarms for Microsoft Sentinel

Multi-tenant alarm integration between SOCRadar XTI Platform and Microsoft Sentinel for MSSP environments.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Forcunsami%2FSOCRadar-Azure-Incidents-MSSP%2Fmaster%2Fazuredeploy.json)

## Prerequisites

- Microsoft Sentinel workspace
- SOCRadar Platform API key

## Configuration

### Required Parameters

| Parameter | Description |
|-----------|-------------|
| `WorkspaceName` | Your Sentinel workspace name |
| `SocradarApiKey` | SOCRadar Platform API Key |
| `CompanyIds` | Comma-separated SOCRadar company IDs (e.g., `330,331,332`) |
| `CompanyNames` | Comma-separated company names matching IDs (e.g., `ACME,Contoso,Fabrikam`) |

### Optional Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `PollingIntervalMinutes` | 5 | How often to check for alarms (1-60 min) |
| `InitialLookbackMinutes` | 600 | First run lookback (default: 10 hours) |
| `ImportAllStatuses` | false | Import all statuses or only OPEN |
| `EnableAuditLogging` | true | Log operations to Log Analytics |
| `EnableAlarmsTable` | true | Store alarms in custom table |
| `EnableWorkbook` | true | Deploy SOCRadar MSSP Analytics Dashboard |

## What Gets Deployed

- **SOCRadar-MSSP-Import** - Imports alarms from multiple SOCRadar tenants as Sentinel incidents
- **SOCRadar-MSSP-Sync** - Syncs closed incidents back to the correct SOCRadar tenant
- **SOCRadar-MSSP-Infrastructure** - Audit logging and custom table infrastructure (optional)
- **SOCRadar MSSP Dashboard** - Workbook with company filter, severity/status charts, timeline, and audit monitoring (if EnableWorkbook=true)

## Key Features

- Multi-tenant support with per-company isolation
- Cross-tenant duplicate prevention
- Per-tenant error handling (one tenant failure doesn't affect others)
- Automatic tenant routing for bidirectional sync
- Classification mapping for closed incidents

## Post-Deployment

Logic Apps are configured to start **3 minutes after deployment** to allow Azure role propagation.

No manual action required - they will start automatically.

## About SOCRadar

SOCRadar is an Extended Threat Intelligence (XTI) platform.

Learn more at [socradar.io](https://socradar.io)

## Support

- **Documentation:** [docs.socradar.io](https://docs.socradar.io)
- **Support:** support@socradar.io
