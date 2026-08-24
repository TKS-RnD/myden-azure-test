# -----------------------------------------------------------------------------
# Function: Set-RegValueForAll (Targets live users and future logins)
# -----------------------------------------------------------------------------
function Set-RegValueForAll {
    param(
        [Parameter(Mandatory=$true)][string]$SubKey,
        [Parameter(Mandatory=$true)][string]$ValueName,
        [Parameter(Mandatory=$true)][object]$Value,
        [Parameter(Mandatory=$true)][ValidateSet('DWord','String','QWord')][string]$Type
    )

    # 1. Update Currently Loaded User Hives (HKU)
    $LoadedSIDs = Get-ChildItem Registry::HKEY_USERS | Where-Object { $_.PSChildName -match "S-1-5-21-[\d\-]+$" }
    foreach ($SID in $LoadedSIDs) {
        $Path = "Registry::HKEY_USERS\$($SID.PSChildName)\$SubKey"
        if (!(Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        Set-ItemProperty -Path $Path -Name $ValueName -Value $Value -Type $Type -Force -ErrorAction SilentlyContinue
    }

    # 2. Setup Active Setup for Future Users
    $Guid = [guid]::NewGuid().ToString("B").ToUpper()
    $ActiveSetupPath = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\$Guid"
    $RegType = if ($Type -eq "DWord") { "REG_DWORD" } elseif ($Type -eq "QWord") { "REG_QWORD" } else { "REG_SZ" }

    New-Item -Path $ActiveSetupPath -Force | Out-Null
    Set-ItemProperty -Path $ActiveSetupPath -Name "ComponentID" -Value "DBA_Tweak_$ValueName"
    Set-ItemProperty -Path $ActiveSetupPath -Name "StubPath" -Value "reg add `"HKCU\$SubKey`" /v $ValueName /t $RegType /d $Value /f"
}

Write-Host "--- Initiating DBA Master Workstation Build ---" -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# 1. UI & PRODUCTIVITY (HKCU via Active Setup)
# -----------------------------------------------------------------------------
Set-RegValueForAll "Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "HideFileExt" 0 "DWord"
Set-RegValueForAll "Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Hidden" 1 "DWord"
Set-RegValueForAll "Software\Microsoft\Windows\CurrentVersion\Search" "BingSearchEnabled" 0 "DWord"
Set-RegValueForAll "Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarAl" 0 "DWord"
Set-RegValueForAll "Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarEndTask" 1 "DWord"
Set-RegValueForAll "Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" "AppsUseLightTheme" 0 "DWord"
Set-RegValueForAll "Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" "SystemUsesLightTheme" 0 "DWord"

# Restore Classic Right-Click Menu
Set-RegValueForAll "Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" "" "" "String"

# -----------------------------------------------------------------------------
# 2. SYSTEM POLICIES & PERFORMANCE (HKLM)
# -----------------------------------------------------------------------------
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1 -Type DWord
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "verbosestatus" -Value 1 -Type DWord
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsSpotlightFeatures" -Value 1 -Type DWord

# Set Power Plan to High Performance
$HighPerfGuid = (powercfg /list | Select-String "High performance").ToString().Split()[3]
if ($HighPerfGuid) { powercfg /setactive $HighPerfGuid }

# -----------------------------------------------------------------------------
# 3. GLOBAL POWERSHELL PROFILE
# -----------------------------------------------------------------------------
$ProfilePath = "$PSHOME\Microsoft.PowerShell_profile.ps1"

# SSMS 20 path (Current version) or fall back to SSMS 19
$SsmsPath = if (Test-Path "C:\Program Files (x86)\Microsoft SQL Server Management Studio 20\Common7\IDE\Ssms.exe") {
    "C:\Program Files (x86)\Microsoft SQL Server Management Studio 20\Common7\IDE\Ssms.exe"
} else {
    "C:\Program Files (x86)\Microsoft SQL Server Management Studio 19\Common7\IDE\Ssms.exe"
}

$ProfileContent = @"
# DBA Workspace Customizations
Import-Module dbatools -ErrorAction SilentlyContinue

function Start-SSMS { & "$SsmsPath" }
Set-Alias ssms Start-SSMS
Set-Alias ads azuredatastudio
Set-Alias grep Select-String
Set-Alias ll { Get-ChildItem -Force }

`$Host.UI.RawUI.WindowTitle = "DBA Terminal - `$(whoami)"
Write-Host "DBA Terminal Ready (dbatools loaded). Type 'ssms' or 'ads' to launch." -ForegroundColor Green
"@
$ProfileContent | Set-Content -Path $ProfilePath -Force

# -----------------------------------------------------------------------------
# 4. PIN WINDOWS TERMINAL TO TASKBAR
# -----------------------------------------------------------------------------
Write-Host "Configuring Taskbar Pinning for Windows Terminal..." -ForegroundColor Yellow

# We use the AUMID for the Windows Terminal (standard for MSIX/Choco install)
$TerminalAUMID = "Microsoft.WindowsTerminal_8wekyb3d8bbwe!App"

# For Windows Server 2022 / Windows 10+, the most reliable way to pin is via
# TaskbarLayoutModification.xml for NEW profiles, or a specialized script for existing ones.
# We'll use a hybrid approach via Active Setup to ensure it's pinned for all DBAs.

$PinScript = {
    param($AUMID)
    $MaxRetries = 5
    $RetryCount = 0
    $Pinned = $false

    while (-not $Pinned -and $RetryCount -lt $MaxRetries) {
        $app = (New-Object -ComObject Shell.Application).NameSpace('shell:AppsFolder').ParseName($AUMID)
        if ($app) {
            $app.InvokeVerb('taskbarpin')
            $Pinned = $true
        } else {
            Start-Sleep -Seconds 2
            $RetryCount++
        }
    }
}

$EncodedScript = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes("powershell.exe -NoProfile -WindowStyle Hidden -Command & { $($PinScript.ToString()) } -AUMID '$TerminalAUMID'"))

$Guid = "{6A1A7B4F-3F5E-4B9D-9C8E-2E7A3D9A4B8F}" # Fixed GUID for Terminal Pinning
$ActiveSetupPath = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\$Guid"

New-Item -Path $ActiveSetupPath -Force | Out-Null
Set-ItemProperty -Path $ActiveSetupPath -Name "ComponentID" -Value "DBA_Pin_Terminal"
Set-ItemProperty -Path $ActiveSetupPath -Name "Version" -Value "1"
Set-ItemProperty -Path $ActiveSetupPath -Name "StubPath" -Value "powershell.exe -NoProfile -WindowStyle Hidden -EncodedCommand $EncodedScript"

# -----------------------------------------------------------------------------
# 5. REFRESH EXPLORER
# -----------------------------------------------------------------------------
Stop-Process -Name Explorer -Force -ErrorAction SilentlyContinue

Write-Host "BUILD COMPLETE. DBAs are ready for launch." -ForegroundColor Green
