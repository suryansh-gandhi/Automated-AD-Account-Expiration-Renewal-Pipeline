## Data Schema Specifications

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