<#
.SYNOPSIS
    Installs the WarDeployService using NSSM and configures it to start after the storage is mounted.

.DESCRIPTION
    1. Installs war-deploy-service.ps1 as a Windows Service via NSSM.
    2. Sets the service to Manual startup (it will be triggered by the mount script).

.NOTES
    Compatible with PSScriptAnalyzer.
#>

[CmdletBinding()]
param (
    [Parameter()]
    [string]$ServiceName = "WarDeployService"
)

# -------------------------------
# Static variables
# -------------------------------
$RegPath     = "HKLM:\SOFTWARE\Denave\Provision"
$regPathName = "ProvisionPath"
$ProvisionDir = (Get-ItemProperty -Path $RegPath -Name $regPathName -ErrorAction SilentlyContinue).ProvisionPath
if (-not $ProvisionDir) {
    throw "Can't Find Registry entry ${regPath}. Quitting."
}

# Now get the Scripts.
$ScriptPath = Join-Path $ProvisionDir "war-deploy-service.ps1"

# 1. Locate NSSM
$NssmCommand = Get-Command -Name "nssm.exe" -ErrorAction SilentlyContinue
if ($null -eq $NssmCommand) {
    Write-Error -Message "NSSM not found. Ensure it is installed (e.g., via 'choco install nssm')."
    return
}
$NssmPath = $NssmCommand.Source

# 2. Define PowerShell Path
$pwshPathCandidates = @()
$cmd = Get-Command "pwsh.exe" -ErrorAction SilentlyContinue
if ($cmd) { $pwshPathCandidates += $cmd.Source }
$pwshPathCandidates += @(
    [IO.Path]::Combine($env:ProgramFiles,'PowerShell','7','pwsh.exe'),
    [IO.Path]::Combine($env:ProgramFiles,'PowerShell','7-preview','pwsh.exe'),
    [IO.Path]::Combine($env:ProgramFiles,'PowerShell','6','pwsh.exe')
)
$pwshPath = $pwshPathCandidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $pwshPath) {
    throw "Unable to locate 'pwsh.exe'. Ensure PowerShell 7 is installed and available in PATH."
}

# 3. Define Arguments
$ServiceArgs = "-ExecutionPolicy Bypass -NoProfile -File `"$ScriptPath`""

# 4. Install the Service
Write-Information -MessageData "Installing service '$ServiceName' via NSSM..." -InformationAction Continue
try {
    # Install
    & $NssmPath install $ServiceName $pwshPath $ServiceArgs

    # Set Startup Type to Manual (it will be started by the mount script)
    & $NssmPath set $ServiceName Start SERVICE_DEMAND_START

    # Set Description
    & $NssmPath set $ServiceName Description "Monitors a drive and deploys WAR files to Tomcat Manager."

    # Set I/O redirection (Optional but recommended for NSSM)
    $LogDir = "C:\ProgramData\WarDeploy\Logs"
    if (-not (Test-Path -Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    & $NssmPath set $ServiceName AppStdout "$LogDir\service-stdout.log"
    & $NssmPath set $ServiceName AppStderr "$LogDir\service-stderr.log"
    & $NssmPath set $ServiceName AppRotateFiles 1

    Write-Information -MessageData "Service '$ServiceName' installed successfully with Manual startup." -InformationAction Continue
}
catch {
    Write-Error -Message "Failed to install service '$ServiceName': $($_.Exception.Message)"
    return
}
