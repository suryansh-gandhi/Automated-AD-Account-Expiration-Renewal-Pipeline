<#
.SYNOPSIS
    Queries Active Directory for accounts expiring within 14 days and synchronizes records to SharePoint.
.DESCRIPTION
    Runs as a scheduled task at 04:00 AM. Finds expiring AD accounts, updates older pending records 
    in SharePoint to 'Previous Day Data', and pushes new pending account records.
.PARAMETER SharePointSiteUrl
    The URL of the target SharePoint site.
.PARAMETER ExpirationWindowDays
    The threshold in days to check for account expiration (Default: 14).
.EXAMPLE
    .\1-FetchAndQueue-ExpiringAccounts.ps1 -SharePointSiteUrl "https://contoso.sharepoint.com/sites/ITOps"
#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory = $true)]
    [string]$SharePointSiteUrl,

    [Parameter(Mandatory = $false)]
    [int]$ExpirationWindowDays = 14,

    [Parameter(Mandatory = $false)]
    [string]$MainListName = "SPList-AccountExpirationManager"
)

# Setup Environment and Error Handling
$ErrorActionPreference = "Stop"
$LogPath = "$PSScriptRoot\Logs\FetchAndQueue_$(Get-Date -Format 'yyyyMMdd').log"

function Write-Log {
    Param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Level] $Message"
    Write-Output $LogEntry
    if (!(Test-Path "$PSScriptRoot\Logs")) { New-Item -ItemType Directory -Path "$PSScriptRoot\Logs" | Out-Null }
    Add-Content -Path $LogPath -Value $LogEntry
}

try {
    Write-Log "Starting AD Account Expiration Scan (Window: $ExpirationWindowDays days)..."

    # Step 1: Connect to SharePoint
    Write-Log "Connecting to SharePoint Site: $SharePointSiteUrl"
    Connect-PnPOnline -Url $SharePointSiteUrl -Interactive

    # Step 2: Mark previous 'Pending' items as 'Previous Day Data'
    Write-Log "Rolling over previous 'Pending' entries in list '$MainListName'..."
    $PendingItems = Get-PnPListItem -List $MainListName -Query "<View><Query><Where><Eq><FieldRef Name='Status'/><Value Type='Choice'>Pending</Value></Eq></Where></Query></View>"
    
    foreach ($Item in $PendingItems) {
        Set-PnPListItem -List $MainListName -Identity $Item.Id -Values @{ "Status" = "Previous Day Data" } | Out-Null
        Write-Log "Updated Item ID $($Item.Id) ($($Item['Title'])) to Status = 'Previous Day Data'"
    }

    # Step 3: Fetch AD Users Expiring within the next N days
    $Today = Get-Date
    $TargetThresholdDate = $Today.AddDays($ExpirationWindowDays)

    Write-Log "Searching Active Directory for accounts expiring between $($Today.ToShortDateString()) and $($TargetThresholdDate.ToShortDateString())..."
    
    $ExpiringUsers = Get-ADUser -Filter { Enabled -eq $true -and AccountExpirationDate -ne $null } -Properties SamAccountName, DisplayName, EmailAddress, Manager, AccountExpirationDate | 
        Where-Object { $_.AccountExpirationDate -ge $Today -and $_.AccountExpirationDate -le $TargetThresholdDate }

    Write-Log "Found $($ExpiringUsers.Count) accounts matching expiration criteria."

    # Step 4: Add fresh records to SharePoint List with Status = 'Pending'
    foreach ($User in $ExpiringUsers) {
        $DaysRemaining = [math]::Max(0, ($User.AccountExpirationDate - $Today).Days)
        
        # Resolve Manager Email
        $ManagerEmail = ""
        if ($User.Manager) {
            $ManagerUser = Get-ADUser -Identity $User.Manager -Properties EmailAddress
            $ManagerEmail = $ManagerUser.EmailAddress
        }

        if ([string]::IsNullOrEmpty($ManagerEmail)) {
            Write-Log "Warning: No manager email found for user $($User.SamAccountName). Setting default fallback." -Level "WARN"
            $ManagerEmail = "it-service-desk@company.com"
        }

        $ItemValues = @{
            "Title"                   = $User.SamAccountName
            "DisplayName"             = $User.DisplayName
            "Email"                   = $User.EmailAddress
            "AccountExpirationInDays" = $DaysRemaining
            "ManagerEmail"            = $ManagerEmail
            "Status"                  = "Pending"
        }

        Add-PnPListItem -List $MainListName -Values $ItemValues | Out-Null
        Write-Log "Queued $($User.SamAccountName) into SharePoint (Expires in $DaysRemaining days, Manager: $ManagerEmail)."
    }

    Write-Log "Scan and queue execution completed successfully."
}
catch {
    Write-Log "Critical Failure during execution: $_" -Level "ERROR"
    throw $_
}