# SOCRadar MSSP Infrastructure

Creates the data collection infrastructure for SOCRadar MSSP multi-tenant alarm and audit logging.

## Resources Created

- Data Collection Endpoint (SOCRadar-MSSP-DCE)
- Custom Table: SOCRadar_Alarms_CL (with CompanyName column)
- Data Collection Rule: SOCRadar-MSSP-Alarms-DCR
- Custom Table: SOCRadarAuditLog_CL (with CompanyName column)
- Data Collection Rule: SOCRadar-MSSP-Audit-DCR

## Prerequisites

- Existing Log Analytics workspace with Microsoft Sentinel enabled

## Deployment

Deploy this playbook before the Import and Sync playbooks.
