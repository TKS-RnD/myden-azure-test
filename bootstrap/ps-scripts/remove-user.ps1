# Requires: Microsoft.Graph SDK
# Install-Module Microsoft.Graph -Scope CurrentUser

#Requires -Modules Microsoft.Graph.Users, Microsoft.Graph.Identity.DirectoryManagement, Microsoft.Graph.Groups
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$User
)

Import-Module Microsoft.Graph.Users
Import-Module Microsoft.Graph.Identity.DirectoryManagement
Import-Module Microsoft.Graph.Groups

# flow -WhatIf/-Confirm into inner calls
$__ConfirmSplat = @{}
if ($PSBoundParameters.ContainsKey('WhatIf')) { $__ConfirmSplat['WhatIf'] = $true }
if ($PSBoundParameters.ContainsKey('Confirm')) { $__ConfirmSplat['Confirm'] = $PSBoundParameters['Confirm'] }

<#
.SYNOPSIS
Safely deprovisions a user: audits groups/roles, removes licenses, disables login, and deletes the user.

.DESCRIPTION
This script connects to Microsoft Graph, validates the target isn't self, performs checks for group and privileged role membership,
removes licenses, disables sign-in, and soft-deletes the target account. All state-changing operations honor -WhatIf / -Confirm via ShouldProcess.

.PARAMETER User
UPN or ObjectId of the user to deprovision.

.EXAMPLE
./remove-user.ps1 -User alice@contoso.com -Verbose -WhatIf
#>

# === FUNCTION: Connect ===
function Connect-GraphTenant {
    [CmdletBinding()]
    param()
    Write-Information "Connecting to Microsoft Graph..." -InformationAction Continue
    try {
        Connect-MgGraph -Scopes "User.Read.All", "User.ReadWrite.All", "Directory.Read.All", "Group.Read.All", "RoleManagement.Read.Directory" -ErrorAction Stop
        $context = Get-MgContext
        Write-Information ("Connected as {0}" -f $context.Account) -InformationAction Continue
        return $context.Account
    }
    catch {
        Write-Error "Failed to connect to Microsoft Graph. $_"
        throw
    }
}

# === FUNCTION: Executing user id ===
function Get-ExecutingUserId {
    [CmdletBinding()]
    param()
    $ctx = Get-MgContext
    if (-not $ctx -or -not $ctx.Account) {
        throw "Not connected to Microsoft Graph. Please run Connect-GraphTenant first."
    }
    try {
        return (Get-MgUser -UserId $ctx.Account -ErrorAction Stop).Id
    }
    catch {
        # Fallback to /me endpoint in case the account UPN is not directly resolvable
        try {
            $me = Invoke-MgGraphRequest -Method GET -Uri "/v1.0/me" -ErrorAction Stop
            if ($null -ne $me -and $me.id) { return $me.id }
            throw "Unable to resolve executing user id from /me."
        }
        catch {
            throw "Failed to resolve executing user id. $_"
        }
    }
}

# === FUNCTION: Get group memberships (security groups) ===
function Get-UserSecurityGroup {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$UserPrincipalName
    )
    try {
        $groups = Get-MgUserMemberOf -UserId $UserPrincipalName -All -ErrorAction Stop | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.group' }
        $count = @($groups).Count
        if ($count -gt 0) {
            Write-Warning "$UserPrincipalName is a member of $count group(s):"
            $groups | ForEach-Object { Write-Information (" - {0}" -f $_.DisplayName) -InformationAction Continue }
        }
        else {
            Write-Information "$UserPrincipalName is not a member of any security groups." -InformationAction Continue
        }
    }
    catch {
        Write-Error "Failed to enumerate groups for $UserPrincipalName. $_"
        throw
    }
}

# === FUNCTION: Get privileged roles ===
function Get-UserPrivilegedRole {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$UserPrincipalName
    )
    try {
        $user = Get-MgUser -UserId $UserPrincipalName -ErrorAction Stop
        $memberOf = Get-MgUserMemberOf -UserId $user.Id -All -ErrorAction Stop
        $roles = $memberOf | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.directoryRole' }

        $count = @($roles).Count
        if ($count -gt 0) {
            Write-Warning "$UserPrincipalName is assigned to $count privileged role(s):"
            $roles | ForEach-Object { Write-Information (" - {0}" -f $_.DisplayName) -InformationAction Continue }
        } else {
            Write-Information "$UserPrincipalName is not assigned to any privileged roles." -InformationAction Continue
        }
    }
    catch {
        Write-Error "Failed to check privileged roles for $UserPrincipalName. $_"
        throw
    }
}

# === FUNCTION: Remove all licenses ===
function Remove-UserLicense {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory)] [string]$UserPrincipalName
    )
    try {
        # Collect assigned license SKU IDs reliably
        $skuIds = @()
        try {
            $licenseDetails = Get-MgUserLicenseDetail -UserId $UserPrincipalName -All -ErrorAction Stop
            if ($licenseDetails) {
                $skuIds = @($licenseDetails | Select-Object -ExpandProperty SkuId)
            }
        }
        catch {
            # Fallback to reading AssignedLicenses via User with explicit property selection
            $user = Get-MgUser -UserId $UserPrincipalName -Property "AssignedLicenses" -ErrorAction Stop
            if ($user -and $user.AssignedLicenses) {
                $skuIds = @($user.AssignedLicenses | Select-Object -ExpandProperty SkuId)
            }
        }

        if ($skuIds.Count -gt 0) {
            # Ensure GUID array type for the SDK call
            $guidSkuIds = @($skuIds | ForEach-Object { [Guid]$_ })
            if ($PSCmdlet.ShouldProcess($UserPrincipalName, "Remove all licenses")) {
                Set-MgUserLicense -UserId $UserPrincipalName -AddLicenses @() -RemoveLicenses $guidSkuIds -ErrorAction Stop
                Write-Information "Licenses removed from $UserPrincipalName." -InformationAction Continue
            }
        }
        else {
            Write-Information "No licenses to remove from $UserPrincipalName." -InformationAction Continue
        }
    }
    catch {
        Write-Error "Failed to remove licenses for $UserPrincipalName. $_"
        throw
    }
}

# === FUNCTION: Disable user login ===
function Disable-UserLogin {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory)] [string]$UserPrincipalName
    )
    try {
        if ($PSCmdlet.ShouldProcess($UserPrincipalName, "Disable sign-in")) {
            Update-MgUser -UserId $UserPrincipalName -AccountEnabled:$false -ErrorAction Stop
            Write-Information "Login disabled for $UserPrincipalName." -InformationAction Continue
        }
    }
    catch {
        Write-Error "Failed to disable login for $UserPrincipalName. $_"
        throw
    }
}


# === FUNCTION: Remove user (soft-delete) ===
function Remove-User {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory)] [string]$UserPrincipalName
    )
    try {
        if ($PSCmdlet.ShouldProcess($UserPrincipalName, "Soft delete user")) {
            Remove-MgUser -UserId $UserPrincipalName -Confirm:$false -ErrorAction Stop
            Write-Information "$UserPrincipalName has been soft-deleted." -InformationAction Continue
        }
    }
    catch {
        Write-Error "Failed to delete user $UserPrincipalName. $_"
        throw
    }
}

# === FUNCTION: Main ===
function Invoke-RemoveUserWorkflow {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory)] [string]$User
    )

    $null = Connect-GraphTenant

    # Resolve executing and target identities by ObjectId for a robust self-check
    $executingId = Get-ExecutingUserId
    $targetUserObj = Get-MgUser -UserId $User -ErrorAction Stop
    if ($executingId -eq $targetUserObj.Id) {
        throw "You cannot run this operation on yourself."
    }


    Write-Information "[1/4] Checking group membership..." -InformationAction Continue
    Get-UserSecurityGroup -UserPrincipalName $targetUserObj.Id

    Write-Information "[2/4] Checking privileged roles..." -InformationAction Continue
    Get-UserPrivilegedRole -UserPrincipalName $targetUserObj.Id

    # ensure WhatIf/Confirm propagate to inner calls only
    $confirmSplat = @{}
    if ($PSBoundParameters.ContainsKey('WhatIf')) { $confirmSplat['WhatIf'] = $true }
    if ($PSBoundParameters.ContainsKey('Confirm')) { $confirmSplat['Confirm'] = $PSBoundParameters['Confirm'] }

    Write-Information "[3/4] Removing licenses..." -InformationAction Continue
    Remove-UserLicense -UserPrincipalName $User @confirmSplat

    Write-Information "[4/4] Disabling login..." -InformationAction Continue
    Disable-UserLogin -UserPrincipalName $User @confirmSplat

    Write-Information "[Final Step] Deleting user..." -InformationAction Continue
    Remove-User -UserPrincipalName $User @confirmSplat

    Write-Information "Done." -InformationAction Continue
}

# Entry point: execute workflow
Invoke-RemoveUserWorkflow -User $User @__ConfirmSplat
