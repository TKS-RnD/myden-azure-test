# Ensure TLS 1.2 (required by Chocolatey)
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ProvisionPath
)

function Install-ChocolateyBootstrap {
    [CmdletBinding()]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '', Justification='Official Chocolatey bootstrapper requires Invoke-Expression of a downloaded script')]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProvisionPath
    )

    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    # Bypass policy only for this process
    Set-ExecutionPolicy Bypass -Scope Process -Force

    # Install Chocolatey (per upstream guidance)
    $chocoInstallScript = 'https://community.chocolatey.org/install.ps1'
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString($chocoInstallScript))

    # Verify installation
    choco --version

    # Install Common tools
    $packages = @(
        "7zip",
        "azure-cli",
        "curl",
        "git",
        "jq",
        "microsoft-windows-terminal",
        "notepadplusplus",
        "powershell-core",
        "psscriptanalyzer",
        "sysinternals",
        "wget"
    )
    foreach ($pkg in $packages) {
       choco install $pkg -y
    }

    # Set Registry entry for Provision Path
    $registryPath = "HKLM:\SOFTWARE\Denave\Provision"
    if (-not (Test-Path $registryPath)) {
        New-Item -Path $registryPath -Force | Out-Null
    }
    Set-ItemProperty -Path $registryPath -Name "ProvisionPath" -Value $ProvisionPath
}

function Install-ChocoPackagesFromFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ProvisionPath
    )

    $packageFile = Join-Path -Path $ProvisionPath -ChildPath 'choco-packages.txt'

    if (-not (Test-Path -Path $packageFile -PathType Leaf)) {
        Write-Warning "Package file not found: $packageFile. Skipping Additional Packages"
        return
    }

    Get-Content -Path $packageFile | ForEach-Object {
        $packageName = $_.Trim()

        if (-not [string]::IsNullOrWhiteSpace($packageName)) {
            Write-Verbose "Installing Chocolatey package: $packageName"
            choco install $packageName --yes
        }
    }
}

# Main
Install-ChocolateyBootstrap -ProvisionPath $ProvisionPath
Install-ChocoPackagesFromFile -ProvisionPath $ProvisionPath
