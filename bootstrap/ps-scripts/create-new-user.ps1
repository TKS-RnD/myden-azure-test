<#
.SYNOPSIS
Creates a new Microsoft Entra ID (Azure AD) user and emails a one-time password.

.DESCRIPTION
- Prompts for or accepts inputs: Work Email (UPN), First Name, Last Name, Usage Location (e.g., US, IN), Manager Email, Phone (for MFA), Personal Email (for password delivery).
- Connects to Microsoft Graph with required scopes.
- Creates the user with a strong temporary password and forces change on next sign-in.
- Emails the temporary password to both Personal Email and Manager using Graph sendMail (from the signed-in admin).
- Sets usage location, manager relationship (after user creation), and phone properties.

.REQUIREMENTS
- Microsoft Graph PowerShell SDK submodules:
  - Microsoft.Graph.Authentication
  - Microsoft.Graph.Users
  - Microsoft.Graph.Identity.DirectoryManagement
  - Microsoft.Graph.DirectoryObjects
  - Microsoft.Graph.Mail

.NOTES
- You must be a user administrator (or Global Admin) and have consent to the requested Graph scopes.
- Sending mail uses the signed-in admin identity.
#>


# region Helper: Module import and Graph connection
function Import-RequiredModule {
    [CmdletBinding()]
    param()
    $required = @(
        'Microsoft.Graph.Authentication',
        'Microsoft.Graph.Users',
        'Microsoft.Graph.Identity.DirectoryManagement',
        'Microsoft.Graph.DirectoryObjects',
        'Microsoft.Graph.Mail'
    )
    $optional = @()

    $missing = @()
    foreach ($m in $required) { if (-not (Get-Module -ListAvailable -Name $m)) { $missing += $m } }
    if ($missing.Count -gt 0) {
        Write-Error ("Missing required modules: {0}" -f ($missing -join ', '))
        Write-Output "Install them with:" -ForegroundColor Yellow
        foreach ($mm in $missing) {
            Write-Output "  Install-Module $mm -Scope CurrentUser"
        }
        throw "Required modules not installed."
    }
    foreach ($m in $required) { Import-Module $m -ErrorAction Stop }
    foreach ($m in $optional) { if (Get-Module -ListAvailable -Name $m) { Import-Module $m -ErrorAction SilentlyContinue } }
}

function Connect-Graph {
    [CmdletBinding()]
    [OutputType([Boolean])]
    param()
    $scopes = @(
        'User.ReadWrite.All',
        'Directory.ReadWrite.All',
        'Mail.Send',
        'Directory.AccessAsUser.All',
        'Organization.Read.All'
    )
    try {
        $ctx = Get-MgContext -ErrorAction SilentlyContinue
        $need = $true
        if ($ctx -and $ctx.Account -and $ctx.Scopes) {
            $missing = $scopes | Where-Object { $_ -notin $ctx.Scopes }
            if (-not $missing -or $missing.Count -eq 0) { $need = $false }
        }
        if ($need) {
            Write-Output "Connecting to Microsoft Graph..."
            Connect-MgGraph -Scopes $scopes | Out-Null
        }
        return $true
    } catch {
        throw "Failed to connect to Microsoft Graph. $_"
    }
}
# endregion

# region Input prompts
function Get-ValueIfMissing {
    param([string]$value,[string]$prompt,[ValidateSet('Text','Country')]$type='Text')
    if ($value) { return $value }
    while ($true) {
        $ans = Read-Host $prompt
        if ($type -eq 'Country') {
            if ($ans -match '^[A-Za-z]{2}$') { return $ans.ToUpper() }
            Write-Warning 'Please enter a two-letter country code (e.g., US, IN, GB).'
        } else {
            if ([string]::IsNullOrWhiteSpace($ans)) { Write-Warning 'Value cannot be empty.' } else { return $ans }
        }
    }
}
# endregion

# region User + password helpers
function Convert-SecureStringToPlainText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][securestring]$SecureString
    )
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }
}

function New-StrongTemporaryPassword {
    [CmdletBinding()]
    [OutputType([SecureString])]
    param([int]$Length = 20)

    $upper = -join ((65..90) | Get-Random -Count 4 | ForEach-Object { [char]$_ })
    $lower = -join ((97..122) | Get-Random -Count 6 | ForEach-Object { [char]$_ })
    $digits = -join ((0..9) | Get-Random -Count 4)
    $symbols = '!@#$%^&*()-_=+' | ForEach-Object { $_ }
    $sym = -join ($symbols | Get-Random -Count 2)
    $restCount = [Math]::Max(0, $Length - ($upper.Length + $lower.Length + $digits.Length + $sym.Length))
    $rest = ''
    if ($restCount -gt 0) {
        $rest = -join ((33..126 | Where-Object { $_ -notin 34,39 } | Get-Random -Count $restCount) | ForEach-Object { [char]$_ })
    }

    # Plain password
    $plain = -join ((($upper + $lower + $digits + $sym + $rest).ToCharArray() | Sort-Object { Get-Random } -Unique))

    # Convert the password to a SecureString
    $securePassword = New-Object -TypeName System.Security.SecureString

    # Append each character of the password to the SecureString object
    $plain.ToCharArray() | ForEach-Object { $securePassword.AppendChar($_) }
    return $securePassword
}

function New-UserObject {
    [CmdletBinding()] param(
        [string]$UserPrincipalName,
        [string]$FirstName,
        [string]$LastName,
        [securestring]$Password
    )
    $display = ($FirstName + ' ' + $LastName).Trim()
    $mailNick = ($UserPrincipalName.Split('@')[0])
    # Convert password only for API payload and minimize plaintext lifetime
    $pwPlain = Convert-SecureStringToPlainText -SecureString $Password
    try {
        $obj = @{
            accountEnabled   = $true
            displayName      = $display
            userPrincipalName= $UserPrincipalName
            mailNickname     = $mailNick
            givenName        = $FirstName
            surname          = $LastName
            passwordProfile  = @{ forceChangePasswordNextSignIn = $true; password = $pwPlain }
        }
        return $obj
    }
    finally {
        $pwPlain = $null
    }
}
# endregion

# region Manager, usage location, phone
function Set-UserManager {
    [CmdletBinding()] param([string]$UserId,[string]$ManagerUpn)
    if ([string]::IsNullOrWhiteSpace($ManagerUpn)) { return }
    try {
        $mgr = Get-MgUser -UserId $ManagerUpn -ErrorAction Stop
        Set-MgUserManagerByRef -UserId $UserId -BodyParameter @{ '@odata.id' = "https://graph.microsoft.com/v1.0/users/$($mgr.Id)" }
    } catch {
        Write-Warning "Failed to set manager. $_"
    }
}

function Set-UsageLocation {
    [CmdletBinding()] param([string]$UserId,[string]$UsageLocation)
    if ([string]::IsNullOrWhiteSpace($UsageLocation)) { return }
    try { Update-MgUser -UserId $UserId -UsageLocation $UsageLocation } catch { Write-Warning "Failed to set usage location. $_" }
}

function Set-PhoneAttribute {
    [CmdletBinding()] param([string]$UserId,[string]$MobilePhone)
    if ([string]::IsNullOrWhiteSpace($MobilePhone)) { return }
    try { Update-MgUser -UserId $UserId -MobilePhone $MobilePhone } catch { Write-Warning "Failed to set user mobile phone property. $_" }
    # Skipping creation of authentication phone method to avoid 403 accessDenied in tenants without required permissions/scopes.
}
# endregion

# region Email password
function Send-PasswordEmail {
    [CmdletBinding()] param(
        [string]$FromUserId,
        [string[]]$Recipients,
        [string]$UserPrincipalName,
        [securestring]$TempPassword
    )
    # Normalize sender: if not provided or empty, fall back to 'me' which uses the signed-in identity.
    if ([string]::IsNullOrWhiteSpace($FromUserId)) { $FromUserId = 'me' }
    if (-not $Recipients -or $Recipients.Count -eq 0) { return }
    $toRecipients = $Recipients | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { @{ emailAddress = @{ address = $_ } } }
    if ($toRecipients.Count -eq 0) { return }
    $subject = "New account created: $UserPrincipalName"
    $plainPw = Convert-SecureStringToPlainText -SecureString $TempPassword
    try {
        $bodyText = @"
A new Microsoft 365 account has been created.

User: $UserPrincipalName
Temporary password: $plainPw

Important:
- The user will be forced to change this password at first sign-in.
- Please register Microsoft Authenticator and complete MFA setup at https://aka.ms/mfasetup

This message was sent automatically by the admin provisioning script.
"@
        $message = @{ subject = $subject; body = @{ contentType = 'Text'; content = $bodyText }; toRecipients = $toRecipients }
        # Send as the signed-in admin
        Send-MgUserMail -UserId $FromUserId -Message $message -SaveToSentItems:$true
        Write-Output "Password email sent to: $($Recipients -join ', ')"
    } catch {
        Write-Warning "Failed to send password email. $_"
    } finally {
        $plainPw = $null
    }
}
# endregion

# region Preflight prerequisites
function Get-CurrentUserActiveDirectoryRoleName {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "Common False Negative")]
    param()
    try {
        $memberOf = Invoke-MgGraphRequest -Method GET -Uri '/v1.0/me/memberOf?$select=displayName' -ErrorAction Stop
        $roles = @()
        if ($memberOf.value) {
            $roles = $memberOf.value | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.directoryRole' } | ForEach-Object { $_.displayName }
        }
        return $roles
    } catch {
        Write-Verbose 'Failed to query current user directory roles; continuing without role list.'
        return @()
    }
}

function Test-Scope {
    [CmdletBinding()]
    [OutputType([Hashtable])]
    param([string[]]$Required)
    $ctx = Get-MgContext -ErrorAction SilentlyContinue
    if (-not $ctx -or -not $ctx.Scopes) { return @{ OK = $false; Missing = $Required } }
    $missing = $Required | Where-Object { $_ -notin $ctx.Scopes }
    return @{ OK = ($missing.Count -eq 0); Missing = $missing }
}

function Test-CurrentUserCanSendMail {
    [CmdletBinding()]
    [OutputType([Boolean])]
    param()
    try {
        # Check if the signed-in account has an Exchange service plan enabled
        $me = Invoke-MgGraphRequest -Method GET -Uri "/v1.0/me?`$select=assignedPlans" -ErrorAction Stop
        $plans = @()
        if ($me.assignedPlans) { $plans = $me.assignedPlans }
        if (-not $plans -or $plans.Count -eq 0) { return $false }
        $hasExchange = $plans | Where-Object {
            $_.capabilityStatus -eq 'Enabled' -and ($_.service -match 'Exchange')
        }
        return ($hasExchange -and $hasExchange.Count -gt 0)
    } catch {
        Write-Verbose "Failed to evaluate mail capability for current user. $_"
        return $false
    }
}

# endregion

# region Main
function Invoke-Main {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param()
    try {
        Import-RequiredModule
        Connect-Graph | Out-Null

        # Preflight: verify scopes and active directory admin role (supports PIM scenarios)
        if (-not (Test-ProvisioningPrerequisite)) {
            Write-Error 'Stopping before provisioning due to missing prerequisites.'
            return
        }

        $UserPrincipalName = Get-ValueIfMissing $null 'Enter Work Email (UPN):'
        $FirstName = Get-ValueIfMissing $null 'Enter First Name:'
        $LastName = Get-ValueIfMissing $null 'Enter Last Name:'
        $UsageLocation = Get-ValueIfMissing $null 'Enter Usage Location (2-letter country code, e.g., US, IN):' -type Country
        $ManagerUpn = Get-ValueIfMissing $null 'Enter Manager Email (UPN), or leave blank:'
        $MobilePhone = Get-ValueIfMissing $null 'Enter Mobile Phone for MFA (e.g., +1 4255551234), or leave blank:'
        $PersonalEmail = Get-ValueIfMissing $null 'Enter Personal Email for password delivery:'

        # Generate password
        $tempPassword = New-StrongTemporaryPassword

        # Create user
        $userBody = New-UserObject -UserPrincipalName $UserPrincipalName -FirstName $FirstName -LastName $LastName -Password $tempPassword

        if ($PSCmdlet.ShouldProcess($UserPrincipalName, 'Create user in Entra ID')) {
            try {
                $newUser = New-MgUser -BodyParameter $userBody -ErrorAction Stop
                Write-Output ("Created user {0} ({1})" -f $newUser.DisplayName, $newUser.Id)
            } catch {
                $msg = $_.Exception.Message
                if ($msg -match 'Authorization_RequestDenied' -or $msg -match 'Status:\s*403' -or $msg -match 'Insufficient privileges') {
                    Write-Error 'Microsoft Graph denied the create user operation (403 Authorization_RequestDenied).'
                    Write-Output 'Common causes and fixes:'
                    Write-Output ' - Your signed-in account lacks an active directory role with user write permissions.'
                    Write-Output '   Required: User Administrator or Global Administrator (Privileged Role Administrator can help manage roles).'
                    Write-Output ' - If your tenant uses PIM, activate the role before running this script.'
                    Write-Output '   You can use bootstrap/ps-scripts/activate-pim-role.ps1 to activate an eligible role.'
                    Write-Output ' - Ensure the Graph consent includes scopes: User.ReadWrite.All, Directory.ReadWrite.All, Mail.Send.'
                    Write-Output 'Docs: https://learn.microsoft.com/graph/errors#authorization_requestdenied'
                    return
                }
                throw
            }
        } else {
            Write-Output 'WhatIf: Skipping user creation.'
            return
        }

        # Post-create updates
        Set-UsageLocation -UserId $newUser.Id -UsageLocation $UsageLocation
        if (-not [string]::IsNullOrWhiteSpace($ManagerUpn)) { Set-UserManager -UserId $newUser.Id -ManagerUpn $ManagerUpn }
        Set-PhoneAttribute -UserId $newUser.Id -MobilePhone $MobilePhone

        # Email OTP to personal and manager
        $recipients = @()
        if ($PersonalEmail) { $recipients += $PersonalEmail }
        if ($ManagerUpn) { $recipients += $ManagerUpn }
        if ($recipients.Count -gt 0) {
            if (Test-CurrentUserCanSendMail) {
                Send-PasswordEmail -Recipients $recipients -UserPrincipalName $UserPrincipalName -TempPassword $tempPassword
            } else {
                Write-Warning 'Skipping password email: the signed-in account does not have an Exchange Online (mail) license.'
            }
        } else {
            Write-Verbose 'No recipients specified for password email; skipping send.'
        }

        Write-Output ''
        Write-Output 'User provisioning completed.'
    }
    catch {
        Write-Error $_
        throw
    }
}

Invoke-Main
# endregion
