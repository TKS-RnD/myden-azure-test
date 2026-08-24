[CmdletBinding()]
param ()

function Get-ProvisionPackagePaths {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$RegistryPath
    )

    try {
        return @{
            ChocoPackages = Get-ItemPropertyValue -Path $RegistryPath -Name 'choco-packages.txt' -ErrorAction Stop
            PsModules = Get-ItemPropertyValue -Path $RegistryPath -Name 'ps-modules.txt' -ErrorAction Stop
        }
    }
    catch {
        throw "Failed to read package list paths from registry: $RegistryPath"
    }
}

function Update-ChocolateyPackages {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$PackageListPath
    )

    if (-not (Test-Path -Path $PackageListPath -PathType Leaf)) {
        Write-Warning "Chocolatey package list not found: $PackageListPath"
        return
    }

    Get-Content -Path $PackageListPath |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object {
            Write-Verbose "Upgrading Chocolatey package: $_"
            choco upgrade $_ -y --no-progress
        }
}

function Update-PowerShellModules {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ModuleListPath
    )

    if (-not (Test-Path -Path $ModuleListPath -PathType Leaf)) {
        Write-Warning "PowerShell module list not found: $ModuleListPath"
        return
    }

    Get-Content -Path $ModuleListPath |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object {
            Write-Verbose "Updating PowerShell module: $_"
            Update-Module -Name $_ -Force -ErrorAction Stop
        }
}

function Invoke-ProvisioningUpgrades {
    [CmdletBinding()]
    param ()

    $registryPath = 'HKLM:\SOFTWARE\Denave\Provision'

    $paths = Get-ProvisionPackagePaths -RegistryPath $registryPath

    Update-ChocolateyPackages -PackageListPath $paths.ChocoPackages
    Update-PowerShellModules  -ModuleListPath  $paths.PsModules
}

# Main
Invoke-ProvisioningUpgrades
