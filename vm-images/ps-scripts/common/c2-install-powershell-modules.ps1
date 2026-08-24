[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ProvisionPath
)

function Install-ProvisioningPowerShellModules {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ProvisionPath
    )

    $ErrorActionPreference = 'Stop'

    $moduleListPath = Join-Path -Path $ProvisionPath -ChildPath 'ps-modules.txt'

    if (-not (Test-Path -Path $moduleListPath -PathType Leaf)) {
        Write-Warning "PowerShell module list not found: $moduleListPath"
        return
    }

    # Ensure TLS 1.2 for PowerShellGet
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # Ensure NuGet provider is available
    if (-not (Get-PackageProvider -Name 'NuGet' -ErrorAction SilentlyContinue)) {
        Install-PackageProvider `
            -Name 'NuGet' `
            -MinimumVersion '2.8.5.201' `
            -Force `
            -Scope AllUsers | Out-Null
    }

    # Ensure PSGallery exists and is trusted
    if (-not (Get-PSRepository -Name 'PSGallery' -ErrorAction SilentlyContinue)) {
        try {
            Register-PSRepository -Default
        } catch {
            Write-Warning "Failed to register PSGallery: $($_.Exception.Message)"
        }
    }

    try {
        Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
    } catch {
        Write-Warning "Failed to trust PSGallery: $($_.Exception.Message)"
    }

    # Read module list
    $modules = Get-Content -Path $moduleListPath | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    }

    # Install modules
    foreach ($moduleName in $modules) {
        Write-Output "Installing PowerShell module: $moduleName"

        try {
            Install-Module `
                -Name $moduleName `
                -Repository 'PSGallery' `
                -Scope AllUsers `
                -AllowClobber `
                -Force `
                -Confirm:$false
        } catch {
            Write-Error "Failed to install module '$moduleName': $($_.Exception.Message)"
            throw
        }
    }

    # Pre-warm modules (JIT / metadata load)
    foreach ($moduleName in $modules) {
        Write-Output "Pre-loading module: $moduleName"

        try {
            Import-Module -Name $moduleName -Global -ErrorAction Stop
            Get-Command -Module $moduleName | Out-Null
        } catch {
            Write-Warning "Warm-up failed for module '$moduleName': $($_.Exception.Message)"
        }
    }
}

# Main
if (-not $ProvisionPath) {
    $registryPath = "HKLM:\SOFTWARE\Denave\Provision"
    try {
        $ProvisionPath = Get-ItemPropertyValue -Path $registryPath -Name "ProvisionPath" -ErrorAction Stop
    } catch {
        throw "ProvisionPath was not supplied and could not be read from registry."
    }
}
Install-ProvisioningPowerShellModules -ProvisionPath $ProvisionPath
