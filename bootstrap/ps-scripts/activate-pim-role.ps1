<#
.SYNOPSIS
    Activates an eligible Azure AD (Entra ID) PIM directory role for the signed-in user.

.DESCRIPTION
    Uses Microsoft Graph PowerShell with interactive login (Connect-MgGraph). Ignores any Azure CLI (az) login state.
    Lists eligible PIM directory roles for the current user, allows selection, and submits activation requests
    using roleManagement/directory assignment schedule requests.

.NOTES
    Requires the following Microsoft Graph PowerShell modules (no auto-install):
      - Microsoft.Graph.Authentication
      - Microsoft.Graph.Users
      - Microsoft.Graph.Identity.Governance

    Required Graph scopes requested during login:
      - RoleManagement.ReadWrite.Directory
      - Directory.Read.All
      - User.Read
#>

function Import-GraphModule {
    [CmdletBinding()]
    param()
    # Verify specific Microsoft Graph submodules required by this script.
    # Do NOT auto-install; guide the user to install only what is needed.
    $requiredModules = @(
        'Microsoft.Graph.Authentication',
        'Microsoft.Graph.Users',
        'Microsoft.Graph.Identity.Governance'
    )

    $missingModules = @()
    foreach ($m in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $m)) {
            $missingModules += $m
        }
    }

    if ($missingModules -and $missingModules.Count -gt 0) {
        Write-Error -Message "One or more required Microsoft Graph modules are missing: $($missingModules -join ', ')"
        Write-Output "\nInstall the missing modules with the following command(s):"
        foreach ($mm in $missingModules) {
            Write-Output "  Install-Module $mm -Scope CurrentUser"
        }
        throw "Missing required Microsoft Graph modules."
    }

    foreach ($m in $requiredModules) {
        Import-Module -Name $m -ErrorAction Stop
    }

}

function Test-GraphConnection {
    [CmdletBinding()]
    param()
    try {
        # Request all scopes required by this script in a single interactive login
        $Scopes = @(
            'RoleManagement.ReadWrite.Directory',
            'Directory.Read.All',
            'User.Read'
        )
        $ctx = Get-MgContext -ErrorAction SilentlyContinue
        $connected = $false
        if ($ctx -and $ctx.Account -and $ctx.Scopes) {
            # If current context already contains all required scopes, keep it
            $missing = $Scopes | Where-Object { $_ -notin $ctx.Scopes }
            if (-not $missing -or $missing.Count -eq 0) {
                $connected = $true
            }
        }
        if (-not $connected) {
            Write-Output "Connecting to Microsoft Graph... A browser window will open for interactive sign-in."
            Connect-MgGraph -Scopes $Scopes | Out-Null
        }
    } catch {
        throw "Failed to connect to Microsoft Graph via interactive login. $_"
    }
}

function Get-GraphUserByUpn {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserPrincipalName
    )

    try {
        $user = Get-MgUser -UserId $UserPrincipalName -Property Id,DisplayName,UserPrincipalName
        return $user
    } catch {
        throw "Failed to retrieve user '$UserPrincipalName' from Microsoft Graph. $_"
    }
}

function Get-UserEligiblePimDirectoryRole {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "Common False Negative")]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$UserId
    )

    # Returns objects with: RoleDefinitionId, RoleDisplayName, DirectoryScopeId
    try {
        $eligibilities = Get-MgRoleManagementDirectoryRoleEligibilitySchedule -All -Filter "principalId eq '$UserId'"
        if (-not $eligibilities) {
            return @()
        }

        $results = @()
        $seen = @{}
        foreach ($e in $eligibilities) {
            if (-not $e.RoleDefinitionId) { continue }

            $key = "$($e.RoleDefinitionId)|$($e.DirectoryScopeId)"
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true

            # Fetch role definition display name
            $roleName = $e.RoleDefinitionId
            $rd = Get-MgRoleManagementDirectoryRoleDefinition -UnifiedRoleDefinitionId $e.RoleDefinitionId -Property Id,DisplayName
            if ($rd -and $rd.DisplayName) { $roleName = $rd.DisplayName }

            # Normalize scope; for directory-wide scope, DirectoryScopeId is typically '/'
            $scope = if ($e.DirectoryScopeId) { $e.DirectoryScopeId } else { '/' }

            $results += [pscustomobject]@{
                RoleDefinitionId = $e.RoleDefinitionId
                RoleDisplayName  = $roleName
                DirectoryScopeId = $scope
            }
        }

        return $results
    } catch {
        Write-Warning ("Failed to fetch user's PIM eligibilities for directory roles. Details: {0}" -f ($_ | Out-String))
        return @()
    }
}

function Show-PimRoleMenu {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "", Justification = "Interactive menu uses Write-Host for clear console prompts and selections")]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Roles
    )

    if (-not $Roles -or $Roles.Count -eq 0) {
        throw "Role list cannot be empty."
    }

    Write-Host "`nEligible Directory Roles:`n"

    for ($i = 0; $i -lt $Roles.Count; $i++) {
        $r = $Roles[$i]
        $display = "[$($i+1)] $($r.RoleDisplayName)  RoleDefId: $($r.RoleDefinitionId)  Scope: $($r.DirectoryScopeId)"
        Write-Host $display
    }

    Write-Host "\nYou can select multiple roles by entering comma-separated numbers"
    Write-Host "(e.g., 1,3,5)."

    # Read User input (Comma separated list of values)
    $userInput = Read-Host "Enter the number(s) of the role(s) you want to activate"

    # Coerce them into an array of integers.
    $parts = $userInput -split ',' |
             ForEach-Object { $_.Trim() } |
             Where-Object { $_ -match '^\d+$' } |
             ForEach-Object { [int]$_ }

    # If nothing selected, bail.
    if ($parts.Count -eq 0) {
        return $()
    }

    # Check if they are within the range of given array
    $valid = $true
    foreach ($p in $parts) {
        # Validate against the roles count (1-based indices)
        if ($p -lt 1 -or $p -gt $Roles.Count) {
            $valid = $false
            break
        }
    }

    # if not valid, cancel the entire thing. Not worth the trouble
    if (-not $valid) {
        return $()
    }

    # Map selected indices (1-based) to actual role objects and return them.
    $selectedRoleObjects = @()
    foreach ($idx in $parts) {
        $selectedRoleObjects += $Roles[$idx - 1]
    }
    return $selectedRoleObjects
}

function Start-PimRoleActivationRequest {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)] [array] $SelectedRoles,
        [Parameter(Mandatory = $true)] [string] $UserId
    )

    if (-not $SelectedRoles -or $SelectedRoles.Count -eq 0) {
        throw "No roles provided for activation."
    }
    if ([string]::IsNullOrWhiteSpace($UserId)) {
        throw "UserId is required for activation."
    }

    $scheduleInfo = @{
        startDateTime = [DateTime]::UtcNow.ToString('o')
        # default 8 hours
        expiration    = @{ type = 'AfterDuration'; duration = 'PT8H' }
    }

    foreach ($r in $SelectedRoles) {
        $params = @{
            Action             = 'SelfActivate'
            PrincipalId        = $UserId
            RoleDefinitionId   = $r.RoleDefinitionId
            DirectoryScopeId   = $r.DirectoryScopeId
            Justification      = 'Daily Work'
            ScheduleInfo       = $scheduleInfo
        }

        try {
            if ($PSCmdlet.ShouldProcess("$($r.RoleDisplayName) (RoleDefId: $($r.RoleDefinitionId))", "Activate PIM directory role assignment")) {
                $resp = New-MgRoleManagementDirectoryRoleAssignmentScheduleRequest @params

                Write-Output "`n✅ Activation request submitted for role: $($r.RoleDisplayName) (RoleDefId: $($r.RoleDefinitionId))"
                if ($resp) {
                    Write-Output ("Status     : {0}" -f $resp.Status)
                    if ($resp.ScheduleInfo -and $resp.ScheduleInfo.Expiration) {
                        Write-Output ("Expires At : {0}" -f $resp.ScheduleInfo.Expiration.EndDateTime)
                    }
                }
            }
        } catch {
            $msg = $_.Exception.Message
            if ($msg -match 'RoleAssignmentDoesNotExist' -or $msg -match '404') {
                $e1 = "Activation failed for role '$($r.RoleDisplayName)'."
                $e2 = 'Likely causes: 1) You are not eligible for this role in PIM,'
                $e3 = '2) The role is not managed by PIM in your tenant, or'
                $e4 = '3) Scope mismatch for the eligibility.'
                Write-Error ("{0} {1} {2} {3}" -f $e1, $e2, $e3, $e4)
            } else {
                Write-Error -Message "Activation failed for role '$($r.RoleDisplayName)': $msg"
            }
        }
    }

    Write-Output ''
}

function Main {
    [CmdletBinding()]
    param()
    try {
        # Step 1: Connect to Microsoft Graph interactively with required scopes
        Import-GraphModule
        Test-GraphConnection
        $ctx = Get-MgContext
        $UserPrincipalName = $ctx.Account

        # Get user id for activation principal
        $user = Get-GraphUserByUpn -UserPrincipalName $UserPrincipalName
        $userId = $user.Id

        # Step 2: Get PIM-eligible directory roles for the signed-in user
        $roles = Get-UserEligiblePimDirectoryRole -UserId $userId

        if (-not $roles -or $roles.Count -eq 0) {
            Write-Warning "No PIM-eligible directory roles found for the signed-in user."
            return
        }

        # Step 3: Show menu and pick one or more roles
        $selectedRoles = Show-PimRoleMenu -Roles $roles
        if (-not $selectedRoles -or $selectedRoles.Count -eq 0) {
            Write-Warning "No roles selected. Exiting without submitting activation requests."
            return
        }

        # Step 4: Submit activation requests for selected roles
        Start-PimRoleActivationRequest -SelectedRoles $selectedRoles -UserId $userId

    } catch {
        Write-Error -Message "❌ Error occurred: $_"
        throw
    }
}

# ----------------------------
# 🔧 Main Execution Starts Here
# ----------------------------
Main
