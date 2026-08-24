<#!
.SYNOPSIS
    Enables or disables Microsoft Entra ID Security Defaults using Microsoft Graph PowerShell.
.DESCRIPTION
    - Validates only the specific Microsoft Graph modules required by this script; does not auto-install.
    - Connects to Microsoft Graph interactively (browser login) with Policy.Read.All and Policy.ReadWrite.ConditionalAccess scopes.
    - Accepts a boolean parameter to set Security Defaults to Enabled or Disabled.
    - Prints the current status and the new status; performs no-op if already in target state.
    - Structured into functions and formatted to satisfy PSScriptAnalyzer guidelines.
#>

[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
param(
    [Parameter(Mandatory = $true, HelpMessage = 'Enter true to enable, false to disable Security Defaults.')]
    [ValidateSet('true','false')]
    [string]$EnableSecurityDefaults
)

function Import-GraphModule {
    [CmdletBinding()]
    param()

    # Require only Authentication; use REST (Invoke-MgGraphRequest) for Directory Settings.
    $requiredAuth = 'Microsoft.Graph.Authentication'

    if (-not (Get-Module -ListAvailable -Name $requiredAuth)) {
        Write-Error 'Missing required Microsoft Graph module(s).'
        Write-Error "`nInstall the missing module with:"
        Write-Error "  Install-Module Microsoft.Graph.Authentication -Scope CurrentUser"
        throw 'Required Microsoft Graph modules are not installed. Exiting.'
    }

    # Import or fail.
    Import-Module $requiredAuth -ErrorAction Stop
}

function Test-GraphConnection {
    [CmdletBinding()]
    param()

    # Request scopes needed to read/update Security Defaults policy
    $Scopes = @('Policy.Read.All', 'Policy.ReadWrite.ConditionalAccess', 'User.Read')
    try {
        $ctx = Get-MgContext -ErrorAction SilentlyContinue
        $connected = $false
        if ($ctx -and $ctx.Account -and $ctx.Scopes) {
            $missing = $Scopes | Where-Object { $_ -notin $ctx.Scopes }
            if (-not $missing -or $missing.Count -eq 0) {
                $connected = $true
            }
        }
        if (-not $connected) {
            Write-Information "Connecting to Microsoft Graph... A browser window will open for interactive sign-in."
            Connect-MgGraph -Scopes $Scopes | Out-Null
        }
    } catch {
        throw "Failed to connect to Microsoft Graph via interactive login. $_"
    }
}

function Get-SecurityDefaultSetting {
    [CmdletBinding()]
    param()

    # Use the modern Graph policy endpoint for Security Defaults
    $uri = 'https://graph.microsoft.com/v1.0/policies/identitySecurityDefaultsEnforcementPolicy'
    $policyObj = Invoke-MgGraphRequest -Method GET -Uri $uri

    # Normalize across PowerShell versions:
    # - On Windows PowerShell 5.1, some Microsoft.Graph.Authentication versions may return a raw JSON string
    # - On PowerShell 7+, we typically get a PSCustomObject
    if ($null -eq $policyObj) {
        throw 'Failed to retrieve identitySecurityDefaultsEnforcementPolicy.'
    }

    if ($policyObj -is [string]) {
        try {
            $policyObj = $policyObj | ConvertFrom-Json -ErrorAction Stop
        } catch {
            throw "Received string from Graph but failed to parse JSON for identitySecurityDefaultsEnforcementPolicy. $_"
        }
    }

    return $policyObj
}

function Get-EnableSecurityDefaultValue {
    [OutputType([bool])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $DirectorySetting
    )

    # For identitySecurityDefaultsEnforcementPolicy, the flag is 'isEnabled'
    if ($null -ne $DirectorySetting -and $DirectorySetting.PSObject.Properties.Name -contains 'isEnabled') {
        return [bool]$DirectorySetting.isEnabled
    }

    # Default to true if not present (conservative)
    return $true
}

function Set-SecurityDefault {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Enable
    )

    process {
        $desiredText = if ($Enable) { 'Enabled' } else { 'Disabled' }
        $target = 'Microsoft Entra ID Security Defaults policy'
        $action = "Set Security Defaults to $desiredText"

        if ($PSCmdlet.ShouldProcess($target, $action)) {
            $updateBody = @{ isEnabled = $Enable } | ConvertTo-Json
            $uri = 'https://graph.microsoft.com/v1.0/policies/identitySecurityDefaultsEnforcementPolicy'
            Invoke-MgGraphRequest -Method PATCH -Uri $uri -Body $updateBody -ContentType 'application/json' | Out-Null

            Write-Output ("Security Defaults have been set to: {0}" -f $desiredText)
        } else {
            Write-Verbose "WhatIf: $action on $target"
        }
    }
}

function Main {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Enable
    )

    # Exit on Error.
    $ErrorActionPreference = 'Stop'

    # Check for Imports.
    Import-GraphModule

    # Check Graph Connections.
    Test-GraphConnection

    # Check if we need to do anything first.
    $settings = Get-SecurityDefaultSetting

    $current = Get-EnableSecurityDefaultValue -DirectorySetting $settings
    $desired = [bool]$Enable

    $currentText = if ($current) { 'Enabled' } else { 'Disabled' }
    $desiredText = if ($desired) { 'Enabled' } else { 'Disabled' }

    Write-Output (
        "Current Security Defaults status : {0}" -f $currentText
    )
    Write-Output (
        "Requested new Security Defaults : {0}" -f $desiredText
    )

    if ($current -eq $desired) {
        Write-Information "No change required. Security Defaults already $currentText."
        return
    }

    # Ok We have to do something.
    Set-SecurityDefault -Enable $Enable
}

# Convert validated string input to a real boolean before invoking main logic
$enableBool = [System.Convert]::ToBoolean($EnableSecurityDefaults)
Main -Enable $enableBool
