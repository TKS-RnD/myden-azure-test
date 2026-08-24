[CmdletBinding()]
param(
    [string]$ServiceName = "WarDeployService"
)

# -------------------------------
# 1. Static variables
# -------------------------------
$taskName    = "MountWarStorageAfterBoot"
$regPath     = "HKLM:\SOFTWARE\Denave\Provision"
$regPathName = "ProvisionPath"
$scriptName  = "mount-war-drive.ps1"

# Now we need to find the script. It should be findable in the above Registry Path and Name.
$scriptDir   = (Get-ItemProperty -Path $regPath -Name $regPathName -ErrorAction SilentlyContinue).ProvisionPath
if (-not $scriptDir) {
    throw "Can't Find Registry entry ${regPath}. Quitting."
}
$scriptPath = Join-Path $scriptDir $scriptName

# Create a logging folder and log file path
$logDir  = Join-Path $scriptDir "logs"
if (-not (Test-Path -Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logPath = Join-Path $logDir "mount-azure-drive.log"

# -------------------------------
# 2. Define the Scheduled Task
# -------------------------------
# Locate pwsh.exe and run it with a fully-qualified path
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

# Build arguments and include logging redirection
# Use -Command so we can perform redirection/tee outside the script context
$escapedScript = $scriptPath -replace "'", "''"
$escapedLog    = $logPath   -replace "'", "''"
$commandText   = "& '$escapedScript' -ServiceName '$ServiceName' *>&1 | Tee-Object -FilePath '$escapedLog' -Append"
$pwshArgs      = "-NoLogo -NoProfile -ExecutionPolicy Bypass -Command $commandText"
$action        = New-ScheduledTaskAction -Execute $pwshPath -Argument $pwshArgs -WorkingDirectory $scriptDir

# Trigger: At Startup with 5-minute delay
# NOTE: Use -RandomDelay so the module emits a proper ISO8601 duration (PT2M)
# and avoid manual Delay formatting issues on some environments.
$trigger = New-ScheduledTaskTrigger -AtStartup -RandomDelay (New-TimeSpan -Minutes 5)

# Settings: keep task after completion; require network to be available
$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 20) `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable

# Principal: SYSTEM account with highest privileges
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

# -------------------------------
# 5. Register the Scheduled Task
# -------------------------------
Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Force

Write-Output "Scheduled task '$taskName' created successfully. Script will run ~5 minutes after boot, once networking is available. Logs: $logPath"

# -------------------------------
# 6. Misc settings
# -------------------------------

# Enable event logging
wevtutil sl Microsoft-Windows-TaskScheduler/Operational /e:true

# Always start Ip SVC Helper, so that it does not get stuck.
Set-Service -Name iphlpsvc -StartupType Automatic
