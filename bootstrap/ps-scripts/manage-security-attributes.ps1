<#
.SYNOPSIS
Creates or updates a Microsoft Entra ID custom security attribute definition using Microsoft Graph.
.DESCRIPTION
- Prompts for an attribute name and allowed values.
- Connects to Microsoft Graph via interactive browser login.
- If the attribute does not exist, it is created; otherwise, its allowed values are updated.
- The script does not auto-install modules. It validates required Microsoft Graph submodules and
  prints exact Install-Module commands for any missing ones, then exits.
#>
function ConvertTo-AllowedValueArray {
    param(
        [Parameter(Mandatory=$true)]$values
    )
    # Graph expects lower-camel-case JSON keys for allowedValue objects: id, isActive
    return $values | ForEach-Object {
        @{ id = $_; isActive = $true }
    }
}

function Import-GraphModule {
    # Verify only the specific Microsoft Graph submodules required by this script.
    # Do NOT auto-install; guide the user to install just what is needed.
    $requiredModules = @(
        'Microsoft.Graph.Authentication',              # Connect-MgGraph, Get-MgContext, Set-MgProfile
        'Microsoft.Graph.Identity.DirectoryManagement' # *-MgDirectoryCustomSecurityAttributeDefinition
    )

    $missing = @()
    foreach ($m in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $m)) {
            $missing += $m
        }
    }

    if ($missing -and $missing.Count -gt 0) {
        Write-Error "Missing required Microsoft Graph modules: $($missing -join ', ')"
        Write-Information "`nInstall the missing module(s) with:"
        foreach ($mm in $missing) {
            Write-Information "  Install-Module $mm -Scope CurrentUser"
        }
        throw "Required Microsoft Graph modules are not installed."
    }

    foreach ($m in $requiredModules) {
        Import-Module $m -ErrorAction Stop
    }
}

function Test-GraphConnection {
    param(
        [string[]]$Scopes = @(
            'User.Read',
            'Directory.Read.All',
            'CustomSecAttributeDefinition.ReadWrite.All'
        )
    )
    try {
        $ctx = Get-MgContext -ErrorAction SilentlyContinue
        $connected = $false
        if ($ctx -and $ctx.Account -and $ctx.Scopes) {
            $missing = $Scopes | Where-Object { $_ -notin $ctx.Scopes }
            if (-not $missing -or $missing.Count -eq 0) { $connected = $true }
        }
        if (-not $connected) {
            Write-Information "Connecting to Microsoft Graph... A browser window will open for interactive sign-in."
            Connect-MgGraph -Scopes $Scopes | Out-Null
        }
    } catch {
        throw "Failed to connect to Microsoft Graph via interactive login. $_"
    }
}

function Get-CustomSecurityAttributeDefinition {
    param([Parameter(Mandatory=$true)][string]$name)

    try {
        $items = Get-MgDirectoryCustomSecurityAttributeDefinition -All
        if ($items) {
            $match = $items | Where-Object { $_.Name -eq $name } | Select-Object -First 1
            return $match
        }
        return $null
    } catch {
        $msg = $_.Exception.Message
        if ($msg -match 'Authorization_RequestDenied' -or $msg -match 'Insufficient privileges' -or $msg -match 'Status: 403') {
            Write-Error "Microsoft Graph returned 403 (Authorization_RequestDenied) when listing custom security attribute definitions."
            Write-Information "This usually means your signed-in account doesn't currently have the 'Attribute Definition Administrator' role active (or Global Administrator)."
            Write-Information "Note: 'Attribute Provisioning Administrator' is NOT sufficient for managing custom security attribute definitions."
            Write-Information "If you use PIM, activate the required role and re-run the script."
            Write-Information "Also ensure the Graph consent includes: User.Read, Directory.Read.All, CustomSecAttributeDefinition.ReadWrite.All."
            throw
        }
        throw
    }
}

function New-CustomSecurityAttributeDefinition {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param(
        [Parameter(Mandatory=$true)][string]$name,
        [Parameter(Mandatory=$true)]$allowedValues,
        [Parameter(Mandatory=$true)][string]$attributeSetName
    )

    $body = @{
        attributeSet = $attributeSetName
        name = $name
        description = "Managed via PowerShell script"
        type = "String"
        isCollection = $true
        isSearchable = $true
        status = "Available"
        usePreDefinedValuesOnly = $true
        allowedValues = $allowedValues
    }

    Write-Information "Creating custom security attribute '$name' in attribute set '$attributeSetName'..."
    try {
        if ($PSCmdlet.ShouldProcess("Custom security attribute '$name' in set '$attributeSetName'","Create")) {
            New-MgDirectoryCustomSecurityAttributeDefinition -BodyParameter $body | Out-Null
            Write-Information "Creation complete."
        }
    } catch {
        $msg = $_.Exception.Message
        if ($msg -match 'Authorization_RequestDenied' -or $msg -match 'Insufficient privileges' -or $msg -match 'Status: 403') {
            Write-Error "Microsoft Graph returned 403 (Authorization_RequestDenied) while creating the attribute."
            Write-Information "Ensure you have the 'Attribute Definition Administrator' role active (or Global Administrator)."
            Write-Information "If using PIM, activate the role and re-run."
            Write-Information "Ensure consented Graph scopes include: User.Read, Directory.Read.All, CustomSecAttributeDefinition.ReadWrite.All."
            throw
        } elseif ($msg -match 'Request_BadRequest' -or $msg -match 'Status: 400') {
            Write-Error "Microsoft Graph returned 400 (BadRequest) while creating the attribute. Common causes:"
            Write-Information " - The attribute set name '$attributeSetName' does not exist. It will be created by this script if you confirm, or specify an existing set."
            Write-Information " - The allowed values payload must use keys 'value' and 'isActive'. This script already does that; double-check your input for blanks."
            Write-Information " - Ensure type is 'String' for predefined values."
            throw
        }
        throw
    }
}

function Update-CustomSecurityAttributeDefinition {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param(
        [Parameter(Mandatory=$true)][string]$id,
        [Parameter(Mandatory=$true)]$allowedValues
    )

    $body = @{
        allowedValues = $allowedValues
    }

    Write-Information "Updating allowed values of existing custom security attribute..."
    try {
        if ($PSCmdlet.ShouldProcess("Custom security attribute id $id","Update allowed values")) {
            Update-MgDirectoryCustomSecurityAttributeDefinition -CustomSecurityAttributeDefinitionId $id -BodyParameter $body | Out-Null
            Write-Information "Update complete."
        }
    } catch {
        $msg = $_.Exception.Message
        if ($msg -match 'Authorization_RequestDenied' -or $msg -match 'Insufficient privileges' -or $msg -match 'Status: 403') {
            Write-Error "Microsoft Graph returned 403 (Authorization_RequestDenied) while updating the attribute."
            Write-Information "Ensure you have the 'Attribute Definition Administrator' role active (or Global Administrator)."
            Write-Information "If using PIM, activate the role and re-run."
            Write-Information "Ensure consented Graph scopes include: User.Read, Directory.Read.All, CustomSecAttributeDefinition.ReadWrite.All."
            throw
        }
        throw
    }
}

function Read-AllowedValueFromUser {
    $raw = Read-Host "Enter allowed values (comma- or newline-separated)"
    $values = $raw -split "[\,\r\n]" | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object -Unique
    return $values
}

function Confirm-AttributeSetExist {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [string]$Description = "Managed via PowerShell script"
    )

    # Check for Attribute presence.
    $sets = Get-MgDirectoryAttributeSet -All -ErrorAction Stop
    if ($sets) {
        $exists = $sets | Where-Object { $_.id -eq $Name } | Select-Object -First 1
        if ($exists) { return $Name }
    }

    $response = Read-Host "Attribute set '$Name' was not found. Create it now? (Y/N)"
    if ($response -notin @('Y','y','Yes','yes')) { throw "Attribute set '$Name' does not exist." }
    $body = @{ id = $Name; description = $Description }
    Write-Information "Creating attribute set '$Name'..."
    try {
        if ($PSCmdlet.ShouldProcess($Name, "Create attribute set")) {
            New-MgDirectoryAttributeSet -BodyParameter $body | Out-Null
            Write-Information "Attribute set '$Name' created."
        }
    } catch {
        $msg = $_.Exception.Message
        if ($msg -match 'Authorization_RequestDenied' -or $msg -match 'Insufficient privileges' -or $msg -match 'Status: 403') {
            Write-Error "Microsoft Graph returned 403 (Authorization_RequestDenied) while creating the attribute set."
            Write-Information "Ensure you have the 'Attribute Definition Administrator' role active (or Global Administrator)."
            throw
        }
        throw
    }
    return $Name
}

function Read-AttributeSetFromUser {
    param(
        [string]$Prompt = "Enter the attribute set name (will be created if absent, e.g., 'Custom')"
    )
    $attributeSetName = Read-Host $Prompt
    if ([string]::IsNullOrWhiteSpace($attributeSetName)) {
        Write-Error "Attribute set name is required."
        throw
    }
    # Ensure it exists; create if missing (with confirmation)
    $null = Confirm-AttributeSetExist -Name $attributeSetName
    return $attributeSetName
}

function Get-CurrentUserId {
    try {
        $ctx = Get-MgContext -ErrorAction Stop
        if (-not $ctx -or -not $ctx.Account) { throw "No current Graph context/account." }
        $u = Get-MgUser -UserId $ctx.Account -ErrorAction Stop
        return $u.Id
    } catch {
        throw "Unable to determine current user ID. $_"
    }
}

function Test-HasRequiredEntraRole {
    param(
        [string[]]$AcceptedRoles = @('Attribute Definition Administrator','Global Administrator')
    )

    $meId = Get-CurrentUserId
    $roles = Get-MgDirectoryRole -All -ErrorAction Stop
    $hasRole = $false
    foreach ($rName in $AcceptedRoles) {
        $role = $roles | Where-Object { $_.DisplayName -eq $rName } | Select-Object -First 1
        if ($role) {
            $members = Get-MgDirectoryRoleMember -DirectoryRoleId $role.Id -All -ErrorAction Stop
            if ($members | Where-Object { $_.Id -eq $meId }) { $hasRole = $true; break }
        }
    }
    if (-not $hasRole) {
        Write-Error "Your account is not currently active in a required role to manage custom security attribute definitions."
        Write-Information "Required role: Attribute Definition Administrator (or Global Administrator)."
        Write-Information "If you use Privileged Identity Management (PIM), activate the required role and re-run this script."
        Write-Information "Note: 'Attribute Provisioning Administrator' is not sufficient for creating/updating custom security attribute definitions."
        throw
    }

}
function Main {
    $ErrorActionPreference = 'Stop'

    Import-GraphModule
    # Connect with required scopes (User.Read, Directory.Read.All, CustomSecAttributeDefinition.ReadWrite.All)
    Test-GraphConnection

    # Optional preflight: ensure the signed-in user has required directory role active
    Test-HasRequiredEntraRole

    $attributeSetName = Read-AttributeSetFromUser

    $attributeName = Read-Host "Enter the custom security attribute name"
    if ([string]::IsNullOrWhiteSpace($attributeName)) {
        Write-Error "Attribute name is required."
        throw
    }

    $allowedValuesInput = Read-AllowedValueFromUser
    if ($null -eq $allowedValuesInput -or $allowedValuesInput.Count -eq 0) {
        Write-Error "At least one allowed value is required."
        throw
    }

    $allowedValuesArray = ConvertTo-AllowedValueArray -values $allowedValuesInput

    $existingAttribute = Get-CustomSecurityAttributeDefinition -name $attributeName

    if ($null -eq $existingAttribute) {
        New-CustomSecurityAttributeDefinition -name $attributeName -allowedValues $allowedValuesArray -attributeSetName $attributeSetName
    } else {
        Update-CustomSecurityAttributeDefinition -id $existingAttribute.id -allowedValues $allowedValuesArray
    }
}

Main
