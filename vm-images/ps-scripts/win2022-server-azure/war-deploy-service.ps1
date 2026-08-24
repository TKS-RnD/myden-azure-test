<#
    war-deploy-service.ps1
    - Gets Tomcat manager password from Windows Credential Manager (CredentialManager module).
    - Monitors the Drive where WARs are mapped via FileSystemWatcher.
    - Deploys WARs to Tomcat Manager (manager-text API) when uploaded/changed.

    Notes for service hosting (NSSM):
    - This script starts a transcript log under C:\ProgramData\WarDeploy\Logs.
    - NSSM can also redirect stdout/stderr; both are compatible.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [bool]$LatestWarDeploy = $false
)

# -----------------------------
# Script-level variables
# -----------------------------
$script:Transcribing = $false

# -----------------------------
# Functions (kept at top for PSScriptAnalyzer friendliness)
# -----------------------------

function Write-ErrorAndExit([string]$msg, [int]$code = 1) {
    Write-Error -Message $msg
    exit $code
}

function Write-LogInfo {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Message)
    Write-Information -MessageData $Message -InformationAction Continue
}


function Start-TranscriptLogging {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$LogDirectory = 'C:\\ProgramData\\WarDeploy\\Logs'
    )
    if ($PSCmdlet.ShouldProcess($LogDirectory, "Initialize transcript logging")) {
        try {
            if (-not (Test-Path -Path $LogDirectory)) {
                New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
            }
            $datePart = (Get-Date -Format 'yyyyMMdd')
            $logPath = Join-Path $LogDirectory ("war-deploy-" + $datePart + ".log")
            if ($script:Transcribing -ne $true) {
                Start-Transcript -Path $logPath -Append | Out-Null
                $script:Transcribing = $true
            }
            Write-LogInfo -Message ("Logging initialized -> {0}" -f $logPath)
        } catch {
            Write-Warning ("Failed to initialize transcript logging: {0}" -f $_.Exception.Message)
        }
    }
}

function Get-InstanceTag {
    [CmdletBinding()] param()
    $imdsUri = 'http://169.254.169.254/metadata/instance?api-version=2021-02-01'
    try {
        Write-LogInfo -Message 'Querying Azure Instance Metadata Service for VM tags (tagsList)...'
        $metadata = Invoke-RestMethod -Headers @{ Metadata = 'true' } -Uri $imdsUri -Method GET -TimeoutSec 5 -ErrorAction Stop
        return $metadata.compute.tagsList
    } catch {
        throw ('Failed to query Azure IMDS. Ensure this runs on an Azure VM and IMDS is accessible. Error: {0}' -f $_.Exception.Message)
    }
}

function Get-BasicAuthHeader {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$User,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$PassPlain
    )
    $bytes = [System.Text.Encoding]::ASCII.GetBytes("$User`:$PassPlain")
    $b64 = [System.Convert]::ToBase64String($bytes)
    return @{ Authorization = "Basic $b64" }
}

function Get-TomcatUsersXmlPath {
    [CmdletBinding()] param()
    # Locate Tomcat via CATALINA_HOME
    $CatalinaHome = $env:CATALINA_HOME
    if (-not $CatalinaHome) {
        Write-ErrorAndExit -msg "ERROR: CATALINA_HOME environment variable not set."
    }

    # Find the users' XML
    $TomcatUsersPath = Join-Path $CatalinaHome "conf\tomcat-users.xml"
    if (-not (Test-Path $TomcatUsersPath)) {
        Write-ErrorAndExit -msg "ERROR: tomcat-users.xml not found at $TomcatUsersPath"
    }
    return $TomcatUsersPath
}

function Get-TomcatUserName {
    [CmdletBinding()] param()
    $TomcatUsersPath = Get-TomcatUsersXmlPath
    [xml]$xmlContent = Get-Content -Path $TomcatUsersPath
    $userNode = $xmlContent.SelectSingleNode("//user")
    if ($null -eq $userNode) {
        Write-ErrorAndExit "ERROR: No <user> element found in $TomcatUsersPath"
    }
    return $userNode.username
}

function Get-TCDeployerSecurePassword {
    [CmdletBinding()] param()

    $TomcatUsersPath = Get-TomcatUsersXmlPath

    # And the password
    $secretPath = "${TomcatUsersPath}.dpapi"
    if (-not (Test-Path $secretPath)) {
       Write-ErrorAndExit -msg "ERROR: tomcat-users.xml.dpapi not found at $secretPath"
    }

    # Read the value and return.
    return (Get-Content $secretPath | ConvertTo-SecureString)
}

function Test-FileStable {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Path,
        [int]$StableSeconds = 5,
        [int]$MaxWaitSeconds = 120
    )
    $elapsed = 0
    $lastSize = -1
    while ($elapsed -lt $MaxWaitSeconds) {
        try {
            if (-not (Test-Path -Path $Path)) {
                Write-Verbose -Message "File is not yet stable"
                Start-Sleep -Seconds 1; $elapsed += 1
                continue
            }
            $fi = Get-Item -LiteralPath $Path -ErrorAction Stop
            $size = $fi.Length
            if ($size -gt 0 -and $size -eq $lastSize) {
                return $true
            }
            $lastSize = $size
        } catch {
            # Swallow intermittent I/O access errors while waiting for stability, but record for verbose diagnostics
            Write-Verbose -Message ("Test-FileStable transient error for '{0}': {1}" -f $Path, $_.Exception.Message)
        }
        Start-Sleep -Seconds $StableSeconds
        $elapsed += $StableSeconds
    }
    return $false
}

function Get-ContextPathFromWar {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Path)
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    if ([string]::IsNullOrWhiteSpace($name)) {
        return $null
    }
    if ($name -ieq 'ROOT') {
        return '/'
    }
    return '/' + $name
}

function Invoke-DeployWar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$WarPath,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$TCUser,
        [Parameter(Mandatory)][ValidateNotNull()][System.Security.SecureString]$SecurePassword,
        [ValidateNotNullOrEmpty()][string]$ManagerBase = 'http://localhost:8080/manager/text'
    )
    if (-not (Test-Path -Path $WarPath)) { throw "WAR file not found: $WarPath" }
    $ctx = Get-ContextPathFromWar -Path $WarPath
    if (-not $ctx) { throw "Could not derive context path from WAR: $WarPath" }

    # Convert secure string to plaintext for curl command (Tomcat Manager requires Basic auth)
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
    try {
        $passPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($bstr)
        $deployUri = "{0}/deploy?path={1}&update=true" -f $ManagerBase, [uri]::EscapeDataString($ctx)
        Write-LogInfo -Message ("Deploying '{0}' to context '{1}' via Tomcat manager (curl.exe)..." -f $WarPath, $ctx)

        # Use curl.exe for deployment.
        # --upload-file (or -T) uploads the WAR file (PUT request).
        # --fail (or -f) ensures curl exits with non-zero on HTTP errors.
        # --silent (or -s) suppresses progress meter.
        # --user (or -u) for Basic Auth.

        $userAuth = "{0}:{1}" -f $TCUser, $passPlain
        $curlArgs = @(
            "--upload-file", $WarPath,
            "--user", $userAuth,
            "--silent",
            "--show-error",
            "--fail",
            $deployUri
        )

        $response = & curl.exe @curlArgs 2>&1
        $exitCode = $LASTEXITCODE

        $responseText = if ($null -ne $response) { $response -join "`n" } else { "" }

        if ($exitCode -eq 0 -and $responseText -match '^OK') {
            Write-LogInfo -Message ("Tomcat manager response: {0}" -f $responseText.Trim())
        } else {
            throw ("Deployment failed (exit code $exitCode). Tomcat manager response: {0}" -f $responseText.Trim())
        }
    } catch {
        throw ("Deployment failed: {0}" -f $_.Exception.Message)
    } finally {
        if ($bstr -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        $passPlain = $null
    }
}

function Invoke-WarEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$FileEventArgs,
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][hashtable]$LastHandled
    )
    $mutex = New-Object System.Threading.Mutex($false, "Global\WarDeployMutex")
    try {
        $hasLock = $mutex.WaitOne(300000) # Wait up to 5 minutes
        if (-not $hasLock) {
            Write-Error "Could not acquire WarDeployMutex within timeout."
            return
        }

        $fullPath = $FileEventArgs.FullPath
        if (-not $fullPath -or ([System.IO.Path]::GetExtension($fullPath) -notmatch '^\.war$')) { return }

        $now = Get-Date
        if ($LastHandled.ContainsKey($fullPath)) {
            $last = $LastHandled[$fullPath]
            if (($now - $last).TotalSeconds -lt 20) { return }
        }

        if (-not (Test-FileStable -Path $fullPath -StableSeconds 3 -MaxWaitSeconds 300)) {
            Write-Warning ("WAR didn't become stable in time, skipping: {0}" -f $fullPath)
            return
        }

        Invoke-DeployWar -WarPath $fullPath -TCUser $Context.TCUser -SecurePassword $Context.SecurePassword -ManagerBase $Context.ManagerBase
        $LastHandled[$fullPath] = Get-Date
    } catch {
        Write-Error ("WAR event handling error: {0}" -f $_.Exception.Message)
    } finally {
        if ($null -ne $mutex) {
            if ($hasLock) { $mutex.ReleaseMutex() }
            $mutex.Dispose()
        }
    }
}

function Start-WarWatcher {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$DriveRoot,
        [Parameter(Mandatory)][hashtable]$Context
    )
    if ($PSCmdlet.ShouldProcess($DriveRoot, "Start WAR watcher")) {
        $fsw = New-Object System.IO.FileSystemWatcher
        $fsw.Path = $DriveRoot
        $fsw.Filter = '*.war'
        $fsw.IncludeSubdirectories = $true
        $fsw.NotifyFilter = [IO.NotifyFilters]'FileName, LastWrite, Size'

        $LastHandled = @{}
        $action = {
            param($psSender, $psArgs)
            # Suppress unused parameter warning
            $null = $psSender
            $ctx = $Event.MessageData.Context
            $lh = $Event.MessageData.LastHandled
            Invoke-WarEvent -FileEventArgs $psArgs -Context $ctx -LastHandled $lh
        }

        $msgData = @{ Context = $Context; LastHandled = $LastHandled }
        $subs = @()
        $subs += Register-ObjectEvent -InputObject $fsw -EventName Created -Action $action -MessageData $msgData
        $subs += Register-ObjectEvent -InputObject $fsw -EventName Changed -Action $action -MessageData $msgData
        $subs += Register-ObjectEvent -InputObject $fsw -EventName Renamed -Action $action -MessageData $msgData
        $fsw.EnableRaisingEvents = $true

        Write-LogInfo -Message ("Watching for WAR files under {0} (including sub-folders)..." -f $DriveRoot)
        return [pscustomobject]@{ Watcher = $fsw; Subscriptions = $subs; LastHandled = $LastHandled }
    }
    return $null
}

function Stop-WarWatcher {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$false)]
        [object]$WatchObject
    )
    if ($PSCmdlet.ShouldProcess($WatchObject, "Stop WAR watcher")) {
        try {
            if ($null -ne $WatchObject) {
                try {
                    if ($WatchObject.Subscriptions) {
                        foreach ($s in $WatchObject.Subscriptions) {
                            if ($null -ne $s) {
                                Unregister-Event -SubscriptionId $s.Id -ErrorAction SilentlyContinue
                            }
                        }
                    }
                } catch {
                    Write-Verbose -Message ("Failed to unregister events: {0}" -f $_.Exception.Message)
                }
                try {
                    if ($WatchObject.Watcher) {
                        $WatchObject.Watcher.EnableRaisingEvents = $false
                        $WatchObject.Watcher.Dispose()
                    }
                } catch {
                    Write-Verbose -Message ("Failed to dispose watcher: {0}" -f $_.Exception.Message)
                }
            }
            if ($script:Transcribing -eq $true) {
                Stop-Transcript | Out-Null
                $script:Transcribing = $false
            }
        } catch {
            Write-Verbose -Message ("Error during Stop-WarWatcher: {0}" -f $_.Exception.Message)
        }
    }
}

function Invoke-RecentWarCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$DriveRoot,
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][hashtable]$LastHandled
    )
    $mutex = New-Object System.Threading.Mutex($false, "Global\WarDeployMutex")
    try {
        $hasLock = $mutex.WaitOne(300000)
        if (-not $hasLock) {
            Write-Error "Could not acquire WarDeployMutex for RecentWarCheck."
            return
        }

        $recent = Get-ChildItem -Path $DriveRoot -Recurse -Filter *.war -ErrorAction SilentlyContinue |
                  Sort-Object LastWriteTime -Descending |
                  Select-Object -First 1
        if ($recent) {
            Write-LogInfo -Message ("Found a recent WAR on startup: {0}; attempting deploy..." -f $recent.FullName)
            if (Test-FileStable -Path $recent.FullName -StableSeconds 3 -MaxWaitSeconds 300) {
                Invoke-DeployWar -WarPath $recent.FullName -TCUser $Context.TCUser -SecurePassword $Context.SecurePassword -ManagerBase $Context.ManagerBase
                $LastHandled[$recent.FullName] = Get-Date
            }
        }
    } catch {
        Write-Verbose -Message ("Invoke-RecentWarCheck encountered an error: {0}" -f $_.Exception.Message)
    } finally {
        if ($null -ne $mutex) {
            if ($hasLock) { $mutex.ReleaseMutex() }
            $mutex.Dispose()
        }
    }
}

function Invoke-Main {
    [CmdletBinding()]
    param(
        [bool]$LatestWarDeploy = $false
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'

    Start-TranscriptLogging

    try {

        # Read all Tags
        $tagsList = Get-InstanceTag

        # Get Drive to watch
        $DriveLetter = ($tagsList | Where-Object { $_.name -ieq 'WarStorageDrive' }).value
        if ([string]::IsNullOrWhiteSpace($DriveLetter)) {
            Write-ErrorAndExit "Missing required VM tag 'WarStorageDrive'."
        }
        $DriveLetter = ($DriveLetter -replace ':', '').Trim()
        if ($DriveLetter.Length -ne 1 -or ($DriveLetter -notmatch '^[A-Za-z]$')) {
            Write-ErrorAndExit "Invalid DriveLetter '{$DriveLetter}'. Provide a single letter (e.g., 'Z')."
        }
        $DriveRoot = ("{0}:\" -f $DriveLetter)
        if (-not (Test-Path -Path $DriveRoot)) {
            throw "Drive {$DriveLetter}: not found or not accessible. Ensure the Azure Files share is mounted."
        }

        # Get Tomcat Deployer context.
        $TCUser = Get-TomcatUserName
        $SecurePassword = Get-TCDeployerSecurePassword
        $ctx = @{
            TCUser = $TCUser
            SecurePassword = $SecurePassword
            ManagerBase = 'http://localhost:8080/manager/text'
        }

        # Start WAR watcher.
        $watch = Start-WarWatcher -DriveRoot $DriveRoot -Context $ctx
        $script:watch = $watch
        Write-LogInfo -Message 'WAR deploy watcher is running.'

        # Check if there is a new one and if so, deploy it.
        if ($LatestWarDeploy) {
            Invoke-RecentWarCheck -DriveRoot $DriveRoot -Context $ctx -LastHandled $watch.LastHandled
        }

        # Register graceful shutdown hook for service stop / engine exit
        Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
            Stop-WarWatcher -WatchObject $script:watch
        } | Out-Null

        # Keep script alive for FileSystemWatcher events
        Write-LogInfo -Message 'Entering event loop. Press Ctrl+C to stop (if running interactively).'
        while ($true) {
            Wait-Event -Timeout 1
        }
    }
    catch {
        Write-Error $_
        throw
    }
    finally {
        Stop-WarWatcher -WatchObject $watch
    }
}

# -----------------------------
# Script entry point
# -----------------------------
Invoke-Main -LatestWarDeploy $LatestWarDeploy
