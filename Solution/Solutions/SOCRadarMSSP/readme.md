# SOCRadar MSSP Solution for Microsoft Sentinel

The SOCRadar MSSP solution provides multi-tenant alarm management for Managed Security Service Providers. Import alarms from multiple SOCRadar company accounts into a single Microsoft Sentinel workspace, with per-tenant tagging, sync, and visibility.

## Components

### Playbooks

- **SOCRadar-MSSP-Import** - Imports alarms from multiple SOCRadar company accounts with parallel processing and error isolation per tenant.
- **SOCRadar-MSSP-Sync** - Syncs closed Sentinel incidents back to the correct SOCRadar tenant with classification mapping.
- **SOCRadar-MSSP-Infrastructure** - Creates custom log tables and data collection rules for multi-tenant alarm and audit data.

### Workbook

- **SOCRadar MSSP Dashboard** - Unified view of alarms across all managed tenants with company selector, cross-tenant correlation, and tenant health monitoring.

### Hunting Queries

- **Alarm Overview** - Summary of alarms grouped by company and severity.
- **Cross-Tenant Correlation** - Identifies threats affecting multiple tenants simultaneously.
- **Tenant Health** - Monitors alarm import health per managed tenant.

## Prerequisites

- Microsoft Sentinel enabled workspace
- SOCRadar XTI Platform account(s) with API access
- Company ID and API Key for each managed tenant

## Post-Deployment

1. Deploy the Infrastructure playbook first to create custom log tables.
2. Deploy the Import playbook with your company configurations.
3. Deploy the Sync playbook with the same company configurations.
4. Both Logic Apps start automatically after a 3-minute delay for role propagation.
