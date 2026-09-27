<#
.SYNOPSIS
    Processes approved extensions and rejected terminations in AD, logs ServiceNow tasks, and updates SharePoint.
.DESCRIPTION
    Runs as an hourly scheduled task. Fetches items from SharePoint where Status is 'Approved' or 'Rejected',
    creates ServiceNow tasks, updates AD account expiration dates, and updates SharePoint statuses.
.PARAMETER SharePointSiteUrl
    Target SharePoint Site URL.
.PARAMETER ServiceNowInstance
    ServiceNow instance URL (e.g., "https://dev12345.service-now.com").
.EXAMPLE
    .\2-ProcessApprovedRejectedRequests.ps1 -SharePointSiteUrl "https://contoso.sharepoint.com/sites/ITOps" -ServiceNowInstance "https://company.service-now.com"
#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory = $true)]
    [string]$SharePointSiteUrl,

    [Parameter(Mandatory = $true)]
    [string]$ServiceNowInstance,

    [Parameter(Mandatory = $false)]
    [string]$MainListName = "SPList-AccountExpirationManager",

    [Parameter(Mandatory = $false)]
    [string]$ServiceAccountEmail = "automation-service-account@company.com"
)

$ErrorActionPreference = "Stop"
$LogPath = "$PSScriptRoot\Logs\ProcessRequests_$(Get-Date -Format 'yyyyMMdd').log"

function Write-Log {
    Param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Level] $Message"
    Write-Output $LogEntry
    if (!(Test-Path "$PSScriptRoot\Logs")) { New-Item -ItemType Directory -Path "$PSScriptRoot\Logs" | Out-Null }
    Add-Content -Path $LogPath -Value $LogEntry
}

function New-ServiceNowTask {
    Param(
        [string]$InstanceUrl,
        [string]$SamAccountName,
        [string]$ActionType,
        [int]$Days
    )
    
    # REST API Payload construct for ServiceNow Incident/Task API
    $Uri = "$InstanceUrl/api/now/table/u_service_request"
    $Body = @{
        u_requested_for = $SamAccountName
        u_short_description = "Automated AD Lifecycle Action: $ActionType ($Days Days)"
        u_description = "Manager approved AD Account action: $ActionType for $SamAccountName. Adjustment: $Days days."
        u_assignment_group = "Identity and Access Management"
    } | ConvertTo-Json

    # Replace with Client Rest Credentials / Secret in production
    # $Response = Invoke-RestMethod -Uri $Uri -Method Post -Body $Body -Headers $Headers -ContentType "application/json"
    
    # Simulated Task Number Return for standard script template
    $MockTaskNumber = "TASK" + (Get-Random -Minimum 100000 -Maximum 999999)
    return $MockTaskNumber
}

try {
    Write-Log "Starting hourly execution for Approved/Rejected account requests..."

    Connect-PnPOnline -Url $SharePointSiteUrl -Interactive

    # Query items with status 'Approved' OR 'Rejected'
    $CAMLQuery = "<View><Query><Where><Or><Eq><FieldRef Name='Status'/><Value Type='Choice'>Approved</Value></Eq><Eq><FieldRef Name='Status'/><Value Type='Choice'>Rejected</Value></Eq></Or></Where></Query></View>"
    $ActionItems = Get-PnPListItem -List $MainListName -Query $CAMLQuery

    Write-Log "Found $($ActionItems.Count) action items requiring processing."

    foreach ($Item in $ActionItems) {
        $SamAccountName = $Item["Title"]
        $Status = $Item["Status"]
        $DaysToBeExtended = [int]$Item["DaysToBeExtended"]
        $ItemID = $Item.Id

        Write-Log "Processing Item ID: $ItemID | User: $SamAccountName | Status: $Status"

        # Check AD User Existence
        $ADUser = Get-ADUser -Filter { SamAccountName -eq $SamAccountName } -Properties AccountExpirationDate
        if (!$ADUser) {
            Write-Log "Error: User $SamAccountName not found in Active Directory. Skipping." -Level "ERROR"
            continue
        }

        if ($Status -eq "Approved") {
            # 1. Create ServiceNow Task
            $TaskNum = New-ServiceNowTask -InstanceUrl $ServiceNowInstance -SamAccountName $SamAccountName -ActionType "Extension" -Days $DaysToBeExtended
            Write-Log "ServiceNow Service Request Created: $TaskNum"

            # 2. Trigger Documentation Email Notification
            $EmailBody = "Automation Audit: Account $SamAccountName extended by $DaysToBeExtended days under ServiceNow Ticket $TaskNum."
            Send-MailMessage -To $ServiceAccountEmail -From "noreply-automation@company.com" -Subject "Audit Trail $TaskNum" -Body $EmailBody -SmtpServer "mail.company.com"

            # 3. Calculate New AD Expiration Date
            $CurrentExpiry = $ADUser.AccountExpirationDate
            if ($null -eq $CurrentExpiry -or $CurrentExpiry -lt (Get-Date)) { $CurrentExpiry = Get-Date }
            $NewExpiry = $CurrentExpiry.AddDays($DaysToBeExtended)

            # 4. Update AD Account
            Set-ADAccountExpiration -Identity $SamAccountName -DateTime $NewExpiry
            Write-Log "Active Directory updated: $SamAccountName extended to $($NewExpiry.ToShortDateString())"

            # 5. Update SharePoint List Record
            Set-PnPListItem -List $MainListName -Identity $ItemID -Values @{
                "Status" = "Completed"
                "AccountSetToBeExpiredInDays" = $DaysToBeExtended
            } | Out-Null
            Write-Log "SharePoint item ID $ItemID updated to Status = 'Completed'."
        }
        elseif ($Status -eq "Rejected") {
            # 1. Create ServiceNow Termination Task
            $TaskNum = New-ServiceNowTask -InstanceUrl $ServiceNowInstance -SamAccountName $SamAccountName -ActionType "Termination" -Days 0
            Write-Log "ServiceNow Termination Task Created: $TaskNum"

            # 2. Set AD Account Expiration to Yesterday (Immediate Termination)
            $ImmediateExpiry = (Get-Date).AddDays(-1)
            Set-ADAccountExpiration -Identity $SamAccountName -DateTime $ImmediateExpiry
            Write-Log "Active Directory updated: $SamAccountName expired immediately ($($ImmediateExpiry.ToShortDateString()))"

            # 3. Update SharePoint List Record
            Set-PnPListItem -List $MainListName -Identity $ItemID -Values @{
                "Status" = "Rejection Successful"
            } | Out-Null
            Write-Log "SharePoint item ID $ItemID updated to Status = 'Rejection Successful'."
        }

        # Headroom delay to manage API rate limits and execution stability
        Start-Sleep -Seconds 3
    }

    Write-Log "Execution cycle finished successfully."
}
catch {
    Write-Log "Critical Failure during execution: $_" -Level "ERROR"
    throw $_
}