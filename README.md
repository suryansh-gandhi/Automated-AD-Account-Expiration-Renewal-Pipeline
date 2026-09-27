# Enterprise Identity Governance: Automated AD Account Expiration & Renewal Pipeline

## 1. Executive Summary

This end-to-end operational pipeline automates the tracking, escalation, manager approval, and lifecycle execution for Active Directory (AD) user accounts nearing expiration. By integrating on-premises Active Directory, SharePoint Online, Power Automate, Microsoft Teams Adaptive Cards, and ServiceNow ITSM, this solution eliminates manual IT service desk overhead, enforces strict auditability, and reduces unauthorized account access risks.

---

## 2. Architecture & Data Flow Diagram

1. [4:00 AM Scheduled Server Script 1]
└─ Queries Active Directory for accounts expiring in <= 14 days.
└─ Updates existing 'Pending' items in Main SharePoint List to 'Previous Day Data'.
└─ Inserts new expiring accounts into Main SharePoint List with Status = 'Pending'.
2. [4:30 AM Scheduled Power Automate Flow 1]
├─ Branch A (Completed Items): Calculates future expiry date (Current Expiry + Extended Days) and notifies Manager via Adaptive Card/Email.
└─ Branch B (Pending Items): Copies records to Helper SharePoint List with 'SourceID' references.
3. [Event-Triggered Power Automate Flow 2 - Helper List Item Created]
├─ Delivers Interactive Teams Adaptive Card to Manager (Options: Extend [30/60/90 days] or Terminate [0 days]).
├─ Parallel 12-Hour Timer: If no response in 12 hours, flow terminates (allowing next day's 4 AM run to re-evaluate).
└─ Manager Responds:
├─ "Extend" -> Updates Main SharePoint List item to Status = 'Approved', populates BusinessJustification and DaysToBeExtended.
└─ "Terminate" -> Updates Main SharePoint List item to Status = 'Rejected', BusinessJustification, DaysToBeExtended = 0.
4. [Hourly Scheduled Server Script 2]
└─ Queries Main SharePoint List for Status = 'Approved' or 'Rejected'.
└─ For 'Approved':
1. Generates ServiceNow (SNOW) Service Request ticket via REST API.
2. Sends automated documentation email to Service Account -> Saved to SP Library -> Attached to SNOW Task.
3. Calculates new expiration date (Today + DaysToBeExtended) and updates Active Directory account.
4. Closes SNOW Task and updates Main SharePoint List Status = 'Completed'.
└─ For 'Rejected':
5. Generates SNOW Termination Task via REST API.
6. Attaches documentation email to SNOW Task.
7. Sets AD account expiration date to (Today - 1) for immediate account termination.
8. Closes SNOW Task and updates Main SharePoint List Status = 'Rejection Successful'.



---

## 3. Data Schema Specifications

### Main SharePoint List: `SPList-AccountExpirationManager`

* `Title` (Single Line of Text): SamAccountName
* `DisplayName` (Single Line of Text): Full Name
* `Email` (Single Line of Text): User Email Address
* `AccountExpirationInDays` (Integer): Days remaining until account expires
* `AccountSetToBeExpiredInDays` (Integer): Days added during previous extension
* `ManagerEmail` (Single Line of Text): Manager Email Address
* `Status` (Choice): Pending | Previous Day Data | Approved | Rejected | Completed | Rejection Successful
* `BusinessJustification` (Multiple Lines of Text): Manager's rationale
* `DaysToBeExtended` (Integer): Requested extension days (0, 30, 60, 90)

### Helper SharePoint List: `SPList-HelperQueue`

* `Title` (Single Line of Text): SamAccountName
* `SourceID` (Integer): ID reference linking back to the Main SharePoint List
* `ManagerEmail` (Single Line of Text): Manager Email Address
* `AccountExpirationInDays` (Integer): Days remaining until expiration

---

## 4. Resilience, Auditability, and Security

* **Data Deduplication**: Daily status rolling (`Pending` -> `Previous Day Data`) prevents race conditions between runs.
* **Non-Blocking Approvals**: 12-hour timeout handles unresponsive managers gracefully without hanging server threads.
* **Audit Trails**: Every lifecycle change (extension or termination) generates an immutable ServiceNow incident ticket linked with the approval justification log.
