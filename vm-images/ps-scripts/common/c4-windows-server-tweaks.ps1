# ================================
# Windows Server Quiet Mode Script
# ================================

[CmdletBinding()]
param()

# Fail fast on errors; keep output concise for CI
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Helper: Create-or-update a registry value with logging
function Set-RegValue {
    [CmdletBinding(SupportsShouldProcess)]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification='Host-stream logging is intentional; avoids polluting pipeline output')]
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][object]$Value,
        [Parameter(Mandatory=$true)]
        [ValidateSet('String','ExpandString','Binary','DWord','QWord','MultiString')]
        [string]$Type
    )

    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    if ($PSCmdlet.ShouldProcess($Path, "Set registry value '$Name' to '$Value'")) {
        try {
            Write-Host ("[$ts] REG: Ensuring key '{0}'" -f $Path)
            New-Item -Path $Path -Force | Out-Null
            Write-Host ("[$ts] REG: Setting {0} -> Name='{1}' Type={2} Value='{3}'" -f $Path, $Name, $Type, $Value)
            New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        }
        catch {
            Write-Warning ("[$ts] REG: Failed to set '{0}'\'{1}' ({2}): {3}" -f $Path, $Name, $Type, $_.Exception.Message)
            throw
        }
    }
}

# 1. Stop Server Manager auto-launch
# Use the Group Policy path to avoid ACL restrictions on the default key during provisioning
Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Server\ServerManager" -Name "DoNotOpenAtLogon" -Value 1 -Type DWord

# 2. File Explorer default to "This PC" instead of Quick Access
Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "LaunchTo" -Value 1 -Type DWord

# 3. Disable Shutdown Event Tracker
Set-RegValue -Path "HKLM:\Software\Policies\Microsoft\Windows NT\Reliability" -Name "ShutdownReasonOn" -Value 0 -Type DWord

# 4. Disable Windows Defender enhanced notifications
Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications" -Name "DisableEnhancedNotifications" -Value 1 -Type DWord

# 5. Disable AutoPlay dialogs
Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoDriveTypeAutoRun" -Value 255 -Type DWord

# 6. Force active, real NIC profiles to Private to stop "Network Discovery" popups (be robust during image baking)
try {
    $profiles = Get-NetConnectionProfile | Where-Object {
        $_.NetworkCategory -ne 'Private' -and
        $_.InterfaceAlias -notmatch 'Loopback|vEthernet|Default Switch' -and
        $_.IPv4Connectivity -ne 'Disconnected'
    }
    foreach ($p in $profiles) {
        try {
            Set-NetConnectionProfile -InterfaceIndex $p.InterfaceIndex -NetworkCategory Private -ErrorAction Stop
        }
        catch {
            # Ignore benign failures (e.g., transient/unsupported profiles during baking)
            Write-Verbose ("Could not set profile '{0}' (Alias: {1}) to Private: {2}" -f $p.Name, $p.InterfaceAlias, $_.Exception.Message)
        }
    }
}
catch {
    Write-Verbose ("Get-NetConnectionProfile failed or returned no applicable profiles: {0}" -f $_.Exception.Message)
}

# 7. Disable Windows Admin Center (WAC) pop-up in Server Manager
Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Server\ServerManager" -Name "DoNotPopWACAlert" -Value 1 -Type DWord

# 8. Suppress new Microsoft Edge first-run experience
Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "HideFirstRunExperience" -Value 1 -Type DWord

# 9. Stop “Windows welcomes you” tips
Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableSoftLanding" -Value 1 -Type DWord

# 10. Enable Scheduled Task Log History
wevtutil.exe sl Microsoft-Windows-TaskScheduler/Operational /e:true
