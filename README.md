# SOCRadar MSSP Alarms for Microsoft Sentinel

Multi-tenant alarm integration between SOCRadar XTI Platform and Microsoft Sentinel for MSSP environments.

## Prerequisites

- Microsoft Sentinel workspace
- SOCRadar API Keys (one per tenant/company)

## Configuration

### Required Parameters

| Parameter | Description |
|-----------|-------------|
| `WorkspaceName` | Your Sentinel workspace name |
| `SocradarApiKey` | Primary SOCRadar API key |
| `CompanyId` | Primary SOCRadar company ID |
| `CompanyConfigs` | JSON array of tenant configurations |

### CompanyConfigs Format

```json
[
  {"CompanyId": "100", "CompanyName": "TenantA", "ApiKey": "key-a"},
  {"CompanyId": "200", "CompanyName": "TenantB", "ApiKey": "key-b"}
]
```

### Optional Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `PollingIntervalMinutes` | 5 | How often to check for alarms (1-60 min) |
| `InitialLookbackMinutes` | 600 | First run lookback (default: 10 hours) |
| `ImportAllStatuses` | false | Import all statuses or only OPEN |
| `EnableAuditLogging` | false | Log operations to Log Analytics |
| `EnableAlarmsTable` | false | Store alarms in custom table |

## What Gets Deployed

- **SOCRadar-MSSP-Import** - Imports alarms from multiple SOCRadar tenants as Sentinel incidents
- **SOCRadar-MSSP-Sync** - Syncs closed incidents back to the correct SOCRadar tenant
- **SOCRadar-MSSP-Infrastructure** - Audit logging and custom table infrastructure (optional)

## Key Features

- Multi-tenant support with per-company isolation
- Cross-tenant duplicate prevention
- Per-tenant error handling (one tenant failure doesn't affect others)
- Automatic tenant routing for bidirectional sync
- Classification mapping for closed incidents

## Post-Deployment

Logic Apps start 3 minutes after deployment to allow Azure role propagation.

## About SOCRadar

SOCRadar is an Extended Threat Intelligence (XTI) platform.

Learn more at [socradar.io](https://socradar.io)

## Support

- **Documentation:** [docs.socradar.io](https://docs.socradar.io)
- **Support:** support@socradar.io
