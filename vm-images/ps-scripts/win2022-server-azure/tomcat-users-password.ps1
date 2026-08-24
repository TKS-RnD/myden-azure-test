<#
    modify-tomcat-users.ps1
    - Finds Tomcat via CATALINA_HOME
    - Loads tomcat-users.xml
    - Replaces string "DEPLOYER_PASSWORD" with a locally generated password
    - Restarts Tomcat service
#>

[CmdletBinding()]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '')]
param()

function Write-ErrorAndExit([string]$msg, [int]$code = 1) {
    Write-Error -Message $msg
    exit $code
}

function New-RandomPassword {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [int]$Length = 10
    )

    if ($PSCmdlet.ShouldProcess("Random Password", "Generate")) {
        if ($Length -lt 2) { throw 'Password length must be at least 2.' }

        $lower   = 'abcdefghijklmnopqrstuvwxyz'
        $upper   = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
        $digits  = '0123456789'
        $special = '@#$:,.'

        # Ensure required categories: at least 1 digit and 1 special
        $chars = @()
        $chars += $digits[(Get-Random -Minimum 0 -Maximum $digits.Length)]
        $chars += $special[(Get-Random -Minimum 0 -Maximum $special.Length)]

        $all = ($lower + $upper + $digits + $special)
        for ($i = $chars.Count; $i -lt $Length; $i++) {
            $chars += $all[(Get-Random -Minimum 0 -Maximum $all.Length)]
        }

        # Shuffle
        return -join (@($chars) | Sort-Object { Get-Random })
    }
    return $null
}


# 1. Locate Tomcat via CATALINA_HOME
$CatalinaHome = $env:CATALINA_HOME
if (-not $CatalinaHome) {
    Write-ErrorAndExit -msg "ERROR: CATALINA_HOME environment variable not set."
}

$TomcatUsersPath = Join-Path $CatalinaHome "conf\tomcat-users.xml"
if (-not (Test-Path $TomcatUsersPath)) {
    Write-ErrorAndExit -msg "ERROR: tomcat-users.xml not found at $TomcatUsersPath"
}

# -----------------------------
# 2. Generate password locally (10 chars, min 1 numeric, 1 special)
# -----------------------------
$Password = New-RandomPassword -Length 10

# -----------------------------
# 3. Get Tomcat Service Name
# -----------------------------
$TomcatService = Get-Service |
                 Where-Object { $_.Name -match "tomcat" -or $_.DisplayName -match "tomcat" } |
                 Select-Object -First 1
if ($TomcatService) {
    $TomcatServiceName = $TomcatService.Name
} else {
    Write-ErrorAndExit "ERROR: Tomcat service not found. Set \$TomcatServiceName manually."
}

# -----------------------------
# 4. Extract username and replace password in tomcat-users.xml
# -----------------------------
Write-Verbose "Updating tomcat-users.xml..."
[xml]$xmlContent = Get-Content -Path $TomcatUsersPath

$userNode = $xmlContent.SelectSingleNode("//user")
if ($null -eq $userNode) {
    Write-ErrorAndExit "ERROR: No <user> element found in $TomcatUsersPath"
}

$User = $userNode.username
Write-Verbose "Found user: $User"

$content = Get-Content -Raw -Path $TomcatUsersPath

if ($content -notmatch "DEPLOYER_PASSWORD") {
    Write-Warning "WARNING: Placeholder 'DEPLOYER_PASSWORD' not found."
    exit 0
} else {
    # Hash password using SHA-256 (matches server.xml MessageDigestCredentialHandler)
    $hasher = [System.Security.Cryptography.HashAlgorithm]::Create("SHA-256")
    $hashBytes = $hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Password))
    $hashedPassword = [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()

    $safePassword = [System.Security.SecurityElement]::Escape($hashedPassword)
    $content = $content.Replace("DEPLOYER_PASSWORD", $safePassword)
    $content | Set-Content -Path $TomcatUsersPath -Encoding utf8
    Write-Verbose "Hashed password replaced successfully in tomcat-users.xml."
}

# -----------------------------
# 5. Store the generated password using DPAPI (LocalMachine scope)
# -----------------------------
$secretPath = "${TomcatUsersPath}.dpapi"

# Encrypt password using DPAPI (LocalMachine)
# PSScriptAnalyzer suppression for plaintext conversion as it is required for DPAPI storage.
$securePwd = ConvertTo-SecureString -String $Password -AsPlainText -Force
$encrypted = $securePwd | ConvertFrom-SecureString

# Store encrypted secret
Set-Content -Path $secretPath -Value $encrypted -Encoding ASCII

# Lock down permissions (CRITICAL)
icacls $secretPath /inheritance:r /grant "SYSTEM:F" /grant "Administrators:F" | Out-Null
Write-Verbose "Stored DPAPI-protected credential for '$User' at $secretPath."

# -----------------------------
# 6. Restart Tomcat service only if it is already running.
# -----------------------------
if ($TomcatService.Status -eq 'Running') {
    try {
        Restart-Service -Name $TomcatServiceName -Force -ErrorAction Stop
        Write-Verbose "Tomcat restarted successfully."
    } catch {
        Write-ErrorAndExit "ERROR restarting Tomcat: $($_.Exception.Message)"
    }
} else {
    Write-Verbose "Tomcat service is not running ($($TomcatService.Status)). Skipping restart."
}
