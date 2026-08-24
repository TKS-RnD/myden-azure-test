<#
.SYNOPSIS
Take ownership and grant full control to the local Administrators group for specific folders.

.DESCRIPTION
This script iterates through a predefined list of folders. For each existing folder, it:
- Takes ownership recursively using the Windows `takeown` tool (owner becomes Administrators).
- Grants the local Administrators group Full Control recursively using `icacls`.
If a folder is not found, a warning is emitted and processing continues to the next folder.

.NOTES
- Run this script from an elevated PowerShell session (Run as Administrator).
- Uses Write-Information/Write-Warning/Write-Error for output (PSScriptAnalyzer compliant).
#>

[CmdletBinding()]
param()

# List of folders for the Administrators group to take ownership of.
$folders = @(
    'C:\Scripts',
    'C:\Tools'
)

foreach ($folder in $folders) {
    if (-not (Test-Path -LiteralPath $folder)) {
        Write-Warning -Message ("Folder not found: {0}" -f $folder)
        continue
    }

    Write-Information -MessageData ("Taking ownership of: {0}" -f $folder) -InformationAction Continue
    try {
        # Take ownership (recursively). Suppress verbose cmd output to keep logs clean.
        takeown /F "$folder" /R /D Y | Out-Null

        # Grant Administrators Full Control (recursively). /C continues on file errors.
        icacls "$folder" /grant Administrators:F /T /C | Out-Null

        Write-Information -MessageData ("Ownership and permissions updated: {0}" -f $folder) -InformationAction Continue
    }
    catch {
        Write-Error -Message ("Failed to update ownership/permissions for: {0}. Error: {1}" -f $folder, $_.Exception.Message)
    }
}
