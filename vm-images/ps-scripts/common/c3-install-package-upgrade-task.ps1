[CmdletBinding()]
param (
    [Parameter()]
    [ValidateRange(1,365)]
    [int]$DaysFromNow = 15
)

function Install-UpgradeScheduledTask {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$UpgradeScriptSourcePath,

        [Parameter(Mandatory = $true)]
        [int]$RunAfterDays
    )

    $taskName   = 'Upgrade-Choco-And-PSModules'
    $scriptDir  = Join-Path $env:ProgramData 'Provisioning'
    $scriptPath = Join-Path $scriptDir 'c-upgrade-choco-ps-modules.ps1'
    $runAt      = (Get-Date).AddDays($RunAfterDays)

    if (-not (Test-Path -Path $UpgradeScriptSourcePath -PathType Leaf)) {
        throw "Upgrade script not found: $UpgradeScriptSourcePath"
    }

    #  Copy to a different path.
    if (-not (Test-Path -Path $scriptDir)) {
        New-Item -Path $scriptDir -ItemType Directory -Force | Out-Null
    }
    Copy-Item -Path $UpgradeScriptSourcePath -Destination $scriptPath -Force

    # Create scheduled action
    $action = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    $trigger = New-ScheduledTaskTrigger -Once -At $runAt
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force

    # Done
    Write-Verbose "Scheduled task '$taskName' created to run at $runAt"
}

function Invoke-TaskInstallation {
    [CmdletBinding()]
    param ()

    # If can't find the path. exit.
    $registryPath = "HKLM:\SOFTWARE\Denave\Provision"
    try {
        $provisionPath = Get-ItemPropertyValue -Path $registryPath -Name "ProvisionPath" -ErrorAction Stop
    } catch {
        Write-Warning "ProvisionPath not found in registry. Exiting"
        return
    }

    $upgradeScript = Join-Path $provisionPath 'c-upgrade-choco-ps-modules.ps1'
    Install-UpgradeScheduledTask -UpgradeScriptSourcePath $upgradeScript -RunAfterDays $DaysFromNow
}

# =========================
# Entry Point
# =========================

Invoke-TaskInstallation
