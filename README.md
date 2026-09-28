# Enterprise Identity Governance: Automated AD Account Expiration & Renewal Pipeline

## 1. Executive Summary

This enterprise-grade operational pipeline automates account lifecycle management for Active Directory (AD) user accounts nearing expiration. By integrating on-premises Active Directory, SharePoint Online, Power Automate, Microsoft Teams Adaptive Cards, and ServiceNow ITSM, this solution eliminates manual IT service desk overhead, enforces strict compliance auditability, and mitigates security risks from expired contractor or employee accounts.

---

## 2. Architecture & System Data Flow

The solution operates as an asynchronous, multi-stage pipeline designed for fault tolerance and zero race conditions:

1. **Daily Expiration Audit (04:00 AM)**
* Scheduled PowerShell script (`1-FetchAndQueue-ExpiringAccounts.ps1`) runs on the automation server.
* Queries Active Directory for active accounts expiring within the next 14 days.
* Rolls over existing `Pending` items in the Main SharePoint List to `Previous Day Data`.
* Populates new expiring user records into the Main SharePoint List with `Status = 'Pending'`.


2. **Queue Processing & Manager Routing (04:30 AM)**
* Scheduled Power Automate Flow 1 executes parallel evaluation:
* **Branch A (Completed Items)**: Computes the revised expiration date (`Current Expiry` + `Days Extended`) and sends confirmation alerts to managers.
* **Branch B (Pending Items)**: Copies records to the Helper SharePoint List containing `SourceID` references for processing.




3. **Interactive Approval Workflow (Event-Driven)**
* Power Automate Flow 2 triggers on creation of items in the Helper List.
* Dispatches an interactive **Microsoft Teams Adaptive Card** to the line manager offering actions:
* **Extend**: Select 30, 60, or 90 days.
* **Terminate**: Select 0 days.


* Executes a parallel 12-hour timeout branch. If the manager fails to respond within 12 hours, the flow instance terminates gracefully, deferring evaluation to the next daily audit cycle.
* Upon manager input, updates the Main SharePoint List item status to `Approved` or `Rejected` along with the manager's business justification.


4. **Lifecycle Execution & ITSM Auditing (Hourly)**
* Scheduled PowerShell script (`2-ProcessApprovedRejectedRequests.ps1`) processes `Approved` and `Rejected` items:
* **Approved Accounts**:
1. Creates a ServiceNow Service Request via REST API.
2. Generates an audit documentation email attached to the ServiceNow ticket.
3. Calculates and updates the new AD account expiration date (`Set-ADAccountExpiration`).
4. Updates Main SharePoint List item status to `Completed`.


* **Rejected Accounts**:
1. Creates a ServiceNow Termination Task.
2. Updates the AD account expiration date to `Today - 1` (immediate account expiration/disabling).
3. Updates Main SharePoint List item status to `Rejection Successful`.







---

## 3. Data Schema Specifications

### Main List: `SPList-AccountExpirationManager`

| Column Name | Data Type | Description |
| --- | --- | --- |
| `Title` | Single Line of Text | SAMAccountName (Primary Identifier) |
| `DisplayName` | Single Line of Text | User's full display name |
| `Email` | Single Line of Text | User's primary email address |
| `AccountExpirationInDays` | Integer | Days remaining until account expiration |
| `AccountSetToBeExpiredInDays` | Integer | Extension duration requested/granted (0, 30, 60, 90) |
| `ManagerEmail` | Single Line of Text | Email address of responsible line manager |
| `Status` | Choice | `Pending`, `Previous Day Data`, `Approved`, `Rejected`, `Completed`, `Rejection Successful` |
| `BusinessJustification` | Multiple Lines of Text | Rationale supplied by manager via Adaptive Card |

### Helper List: `SPList-HelperQueue`

| Column Name | Data Type | Description |
| --- | --- | --- |
| `Title` | Single Line of Text | SAMAccountName |
| `SourceID` | Integer | Foreign key ID referencing the Main List item |
| `ManagerEmail` | Single Line of Text | Manager email address for Adaptive Card targeting |
| `AccountExpirationInDays` | Integer | Snapshot of remaining days |

---

## 4. Operational Resilience & Security Controls

* **Zero Hardcoded Secrets**: Secure parameter blocks and runtime variables for all tenant endpoints and credentials.
* **Race Condition Prevention**: Status rolling (`Pending` -> `Previous Day Data`) ensures multi-day account evaluation without duplicate processing.
* **Non-Blocking Approval Timeouts**: 12-hour auto-termination prevents flow execution hanging and server resource exhaustion.
* **Audit Compliance**: Every account modification yields a corresponding ServiceNow ticket and audit log record.

---

## 5. Repository Layouttext

.
├── README.md
├── .gitignore
├── 01-Flows/
│   ├── Flow-1-QueueProcessor.json
│   └── Flow-2-AdaptiveCardManager.json
├── 02-Scripts/
│   ├── 1-FetchAndQueue-ExpiringAccounts.ps1
│   └── 2-ProcessApprovedRejectedRequests.ps1
└── 03-Schemas/
├── AdaptiveCard-Approval.json
└── SharePoint-ListSchema.json

---

## 6. Setup & Deployment Quickstart

1. **SharePoint Provisioning**: Create `SPList-AccountExpirationManager` and `SPList-HelperQueue` using the field specifications outlined in the Schema section.
2. **Script Configuration**: Update the mandatory parameter blocks in `/02-Scripts/` with your tenant SharePoint URL and ServiceNow API endpoints.
3. **Task Scheduler Registration**: Register `1-FetchAndQueue-ExpiringAccounts.ps1` to execute daily at 04:00 AM and `2-ProcessApprovedRejectedRequests.ps1` to execute hourly.
4. **Power Automate Import**: Import the flow definitions from `/01-Flows/` into your Power Automate environment and authorize the SharePoint and Microsoft Teams connectors.
