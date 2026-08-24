<#
.SYNOPSIS
    Activates an eligible PIM assignment (group membership) for the signed-in user.

.DESCRIPTION
    Uses Microsoft Graph PowerShell with interactive login (Connect-MgGraph). Ignores any Azure CLI (az) login state.
    Lists eligible PIM assignments (including group-based), lets you select one or more, and submits activation requests.
#>

function Import-GraphModule {
    [CmdletBinding()]
    param()
    # Verify specific Microsoft Graph submodules required by this script.
    # Do NOT auto-install; guide the user to install only what is needed.
    $requiredModules = @(
        'Microsoft.Graph.Authentication',
        'Microsoft.Graph.Users',
        'Microsoft.Graph.Groups',
        'Microsoft.Graph.Identity.Governance'
    )

    $missingModules = @()
    $installedModules = Get-Module -ListAvailable | Select-Object -ExpandProperty Name
    foreach ($m in $requiredModules) {
        if (-not ($installedModules -contains $m)) {
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
            'PrivilegedAccess.ReadWrite.AzureADGroup',
            'Group.Read.All',
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

function Get-UserEligiblePimGroup {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "Common False Negative")]
    param(
        [Parameter(Mandatory = $true)][string]$UserId
    )
    try {
        $eligibilities = Get-MgIdentityGovernancePrivilegedAccessGroupEligibilitySchedule -All -Filter "principalId eq '$UserId'"
        if (-not $eligibilities) {
            return @()
        }

        $results = @()
        $seen = @{}
        foreach ($e in $eligibilities) {
            if (-not $e.GroupId) {
                continue
            }

            $key = "$($e.GroupId)|$($e.AccessId)"
            if ($seen.ContainsKey($key)) {
                continue
            }

            $seen[$key] = $true

            # Fetch group to get display name
            try {
                $grp = Get-MgGroup -GroupId $e.GroupId -Property Id,DisplayName
                if ($grp -and $grp.DisplayName) {
                    $displayName = $grp.DisplayName
                } else {
                    $displayName = $e.GroupId
                }
            } catch {
                $displayName = $e.GroupId
            }

            $acc = 'member'
            if ($e.AccessId) { $acc = $e.AccessId.ToLower() }
            $results += [pscustomobject]@{
                Id = $e.GroupId
                DisplayName = $displayName
                AccessId = $acc  # normalize to lowercase for ValidateSet
            }
        }

        return $results
    } catch {
        Write-Warning ("Failed to fetch user's PIM eligibilities for groups. Details: {0}" -f ($_ | Out-String))
        return @()
    }
}

# Check if the given PIM Group has active assignment.
function Get-ActivePimGroupAssignment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$UserId,
        [Parameter(Mandatory = $true)][string]$GroupId,
        [Parameter(Mandatory = $true)][ValidateSet('member','owner')][string]$AccessId
    )
    try {
        # Active assignments have Status = 'Provisioned'
        $all = Get-MgIdentityGovernancePrivilegedAccessGroupAssignmentSchedule -All -Filter "principalId eq '$UserId' and groupId eq '$GroupId' and accessId eq '$AccessId'"
        if (-not $all) { return $null }
        $active = $all | Where-Object { $_.Status -eq 'Provisioned' }
        if ($active) {
            return $active | Select-Object -First 1
        }
        return $null
    } catch {
        Write-Warning ("Failed to query active PIM assignment for group $GroupId. Details: {0}" -f ($_ | Out-String))
        return $null
    }
}

# Get List of Pending Requests
function Get-PendingPimGroupRequests {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$UserId,
        [Parameter(Mandatory = $true)][string]$GroupId,
        [Parameter(Mandatory = $true)][ValidateSet('member','owner')][string]$AccessId
    )
    try {
        $reqs = Get-MgIdentityGovernancePrivilegedAccessGroupAssignmentScheduleRequest -All -Filter "principalId eq '$UserId' and groupId eq '$GroupId' and accessId eq '$AccessId'"
        if (-not $reqs) { return @() }
        $pendingStatuses = @('Pending','InProgress','Submitted','Staged')
        return $reqs | Where-Object { $_.Status -in $pendingStatuses }
    } catch {
        Write-Warning ("Failed to query pending PIM requests for group $GroupId. Details: {0}" -f ($_ | Out-String))
        return @()
    }
}

# Extend PIM Group Extension.
function Submit-PimGroupExtend {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)][string]$AssignmentScheduleId,
        [Parameter(Mandatory = $true)][string]$GroupId,
        [Parameter(Mandatory = $true)][string]$PrincipalId,
        [Parameter(Mandatory = $true)][ValidateSet('member','owner')][string]$AccessId,
        [Parameter()][string]$Justification = 'Extend active assignment',
        [Parameter()][string]$Duration = 'PT8H'
    )

    $scheduleInfo = @{
        startDateTime = [DateTime]::UtcNow.ToString('o')
        expiration    = @{ type = 'AfterDuration'; duration = $Duration }
    }

    # NOTE:
    # Some Microsoft Graph PowerShell SDK versions (especially v2+) do not expose
    # a top-level cmdlet parameter named 'AssignmentScheduleId'. When we splat a
    # hashtable into the cmdlet, PowerShell tries to bind keys to cmdlet
    # parameters, causing: "A parameter cannot be found that matches parameter name 'AssignmentScheduleId'".
    #
    # To keep compatibility across SDK versions, build the request body and pass
    # it with -BodyParameter. The property names map to the API payload fields.
    $body = @{
        action               = 'SelfExtend'
        assignmentScheduleId = $AssignmentScheduleId
        groupId              = $GroupId
        principalId          = $PrincipalId
        accessId             = $AccessId
        justification        = $Justification
        scheduleInfo         = $scheduleInfo
    }

    try {
        if ($PSCmdlet.ShouldProcess("$GroupId", "Extend PIM group assignment")) {
            # Use -BodyParameter to avoid strict parameter binding issues
            $resp = New-MgIdentityGovernancePrivilegedAccessGroupAssignmentScheduleRequest -BodyParameter $body
            return $resp
        }
    } catch {
        throw $_
    }
}


function Show-PimAssignmentMenu {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "", Justification = "Interactive menu uses Write-Host for clear console prompts and selections")]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Assignments
    )

    if (-not $Assignments -or $Assignments.Count -eq 0) {
        throw "Assignments list cannot be empty."
    }

    Write-Host "`nRole-assignable Groups:`n"

    for ($i = 0; $i -lt $Assignments.Count; $i++) {
        $g = $Assignments[$i]

        $access = 'member'
        if ($g.PSObject.Properties.Name -contains 'AccessId') {
            $access = $g.AccessId
        }

        $display = "[$($i+1)] $($g.DisplayName) - access: $access  ($($g.Id))"
        Write-Host $display
    }

    Write-Host "`nYou can select multiple groups by entering comma-separated numbers"
    Write-Host "(e.g., 1,3,5)."

    # Read User input (Comma separated list of values)
    $userInput = Read-Host "Enter the number(s) of the group(s) you want to activate"

    # Coerce them into an array of integers.
    $parts = $userInput -split ','        |
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
        if ($p -lt 1 -or $p -gt $Assignments.Count) {
            $valid = $false
            break
        }
    }

    # if not valid, cancel the entire thing. Not worth the trouble
    if (-not $valid) {
        return $()
    }

    # Pick the values that are selected and return them.
    Write-Host $parts
    return $parts
}

function Start-PimAssignmentActivation {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Assignments,
        [Parameter(Mandatory = $true)]
        [string]$UserId
    )

    if (-not $Assignments -or $Assignments.Count -eq 0) {
        throw "No assignments provided for activation."
    }

    if ([string]::IsNullOrWhiteSpace($UserId)) {
        throw "UserId is required for activation."
    }

    # Create a Schedule Info partial payload. It can be adjusted later to fill the details.
    $scheduleInfo = @{
        startDateTime = [DateTime]::UtcNow.ToString('o')
        # default 8 hours
        expiration    = @{ type = 'AfterDuration'; duration = 'PT8H' }
    }

    # Iterate through object validations.
    foreach ($g in $Assignments) {

        $groupId = $g.Id
        $accessId = $g.AccessId
        if (-not $accessId) { $accessId = 'member' } else { $accessId = $accessId.ToLower() }
        $display = if ($g.DisplayName) { $g.DisplayName } else { $groupId }

        # 1) Skip if there is a pending request for the same target
        $pending = Get-PendingPimGroupRequests -UserId $UserId -GroupId $groupId -AccessId $accessId
        if ($pending -and $pending.Count -gt 0) {
            $pStatus = ($pending | Select-Object -ExpandProperty Status | Sort-Object -Unique) -join ', '
            Write-Warning "⏳ Skipping '$display' ($groupId) — a request is already pending: $pStatus"
            continue
        }

        # 2) If there is an active assignment, submit an extend instead of activate
        $active = Get-ActivePimGroupAssignment -UserId $UserId -GroupId $groupId -AccessId $accessId
        if ($active) {
            try {
                if ($PSCmdlet.ShouldProcess("$display ($groupId)", "Extend active PIM assignment as $accessId")) {
                    $extendResp = Submit-PimGroupExtend -AssignmentScheduleId $active.Id -GroupId $groupId -PrincipalId $UserId -AccessId $accessId -Justification 'Extend active session' -Duration 'PT8H'
                    Write-Output "`n✅ Extend request submitted for group: $display ($groupId)"
                    if ($extendResp) {
                        Write-Output ("Status     : {0}" -f $extendResp.Status)
                        if ($extendResp.ScheduleInfo -and $extendResp.ScheduleInfo.Expiration) {
                            Write-Output ("New Expires At : {0}" -f $extendResp.ScheduleInfo.Expiration.EndDateTime)
                        }
                    }
                }
            } catch {
                $em = $_.Exception.Message
                Write-Error "Extend failed for group '$display' ($groupId): $em"
            }
            continue
        }

        # 3) Otherwise, proceed with activation
        $params = @{
            Action        = 'SelfActivate'
            GroupId       = $groupId
            PrincipalId   = $UserId
            # honor eligibility access type
            AccessId      = $accessId
            Justification = 'Daily Work'
            ScheduleInfo  = $scheduleInfo
        }

        try {
            if ($PSCmdlet.ShouldProcess("$display ($groupId)", "Activate PIM group assignment as $accessId")) {
                $response = New-MgIdentityGovernancePrivilegedAccessGroupAssignmentScheduleRequest @params

                Write-Output "`n✅ Activation request submitted for group: $display ($groupId)"
                if ($response) {
                    Write-Output ("Status     : {0}" -f $response.Status)
                    if ($response.ScheduleInfo -and $response.ScheduleInfo.Expiration) {
                        Write-Output (
                            "Expires At : {0}" -f $response.ScheduleInfo.Expiration.EndDateTime
                        )
                    }
                }
            }
        } catch {
            $details = $null
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                $details = $_.ErrorDetails.Message
                Write-Error "Graph details: $details"
            }
        }
    }

    Write-Output ''
}

function Start-PimGroupActivation {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "", Justification = "Interactive flow uses Write-Host for user prompts and summaries")]
    param()
    try {
        # Step 1: Connect to Microsoft Graph interactively with required scopes
        Import-GraphModule
        Test-GraphConnection
        $ctx = Get-MgContext
        if (-not $ctx -or -not $ctx.Account) {
            throw "Not connected to Microsoft Graph or missing account in context. Please sign in and try again."
        }
        $UserPrincipalName = $ctx.Account

        # Get user id for activation principal
        $user = Get-GraphUserByUpn -UserPrincipalName $UserPrincipalName
        $userId = $user.Id

        # Step 2: Get PIM-eligible groups for the signed-in user (with access type)
        $groups = Get-UserEligiblePimGroup -UserId $userId

        if (-not $groups -or $groups.Count -eq 0) {
            Write-Warning "No PIM-eligible groups found for the signed-in user."
            return
        }

        # Step 3: Show menu and pick one or more groups
        $selected = Show-PimAssignmentMenu -Assignments $groups
        Write-Host $selected
        $selectedGroups = $selected | ForEach-Object { $groups[$_-1] }

        # Preview selection and confirm
        if (-not $selectedGroups -or $selectedGroups.Count -eq 0) {
            Write-Warning "No groups were selected."
            return
        }

        Write-Host "`nYou are about to submit activation for the following selection:`n"
        $preview = $selectedGroups | ForEach-Object {
            $acc = 'member'
            if ($_.PSObject.Properties.Name -contains 'AccessId' -and $_.AccessId) {
                $acc = $_.AccessId
            }
            [pscustomobject]@{
                DisplayName = $_.DisplayName
                GroupId     = $_.Id
                Access      = $acc
            }
        }
        $preview | Sort-Object DisplayName, Access | Format-Table -AutoSize | Out-String | Write-Host

        $confirm = Read-Host "Proceed to submit activation requests? (y/N)"
        if ($confirm -notin @('y','Y','yes','YES')) {
            Write-Host "Operation cancelled by user."
            return
        }

        # Step 4: Activate selection(s) for groups only (honors member/owner access per eligibility)
        Start-PimAssignmentActivation -Assignments $selectedGroups -UserId $userId

    } catch {
        Write-Error "❌ Error occurred: $_"
        throw
    }
}

# ----------------------------
# 🔧 Main Execution Starts Here
# ----------------------------
Start-PimGroupActivation
