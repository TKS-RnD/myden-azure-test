[CmdletBinding()]
param(
    [string]$TomcatVersion     = "9.0.89",
    [string]$TomcatServiceName = "Tomcat9",
    [int]   $TomcatPort        = 8080,
    [string]$JavaPackage       = "openjdk17",
    [string]$HardenedConfigDir
)

# Initialize paths if not provided
$RegPath      = "HKLM:\SOFTWARE\Denave\Provision"
$regPathName = "ProvisionPath"
$ProvisionDir = (Get-ItemProperty -Path $RegPath -Name $regPathName -ErrorAction SilentlyContinue).ProvisionPath
if (-not $ProvisionDir) {
    throw "Can't Find Registry entry ${regPath}. Quitting."
}
$HardenedConfigDir = Join-Path $ProvisionDir "Tomcat"

# Fail fast on errors; keep output concise for CI
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# -------------------------------
# Utility functions
# -------------------------------
function Write-Info {
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification='Use Write-Host here to emit to Host stream and avoid polluting Success output/pipeline values')]
    param(
        [string]$msg
    )
    # Use Write-Host to avoid emitting to the Success output stream.
    # This prevents polluting function return values with log messages.
    Write-Host "[INFO ] $msg"
}

function Write-Warn([string]$msg) {
    Write-Warning "[WARN ] $msg"
}

function Write-ErrorAndExit([string]$msg) {
    Write-Error "[ERROR] $msg"; exit 1
}

function Test-7Zip {
    Write-Info "Ensuring 7-Zip is installed..."
    choco install 7zip -y | Out-Null
    $sevenZip = "C:\\Program Files\\7-Zip\\7z.exe"
    if (-not (Test-Path $sevenZip)) {
        Write-ErrorAndExit "7-Zip not found at $sevenZip after installation."
    }
    return $sevenZip
}

function Test-Download-FileWithRetry([string]$Uri, [string]$OutFile, [int]$Attempts = 3) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            Write-Info "Downloading: $Uri (attempt $i/$Attempts)"
            Invoke-WebRequest -Uri $Uri -OutFile $OutFile
            return
        } catch {
            if ($i -eq $Attempts) { throw }
            Start-Sleep -Seconds (5 * $i)
        }
    }
}

# -------------------------------
# Java functions
# -------------------------------
function Install-JavaAndConfigureEnv([string]$JavaPackageName) {
    Write-Info "Installing Java package via Chocolatey: $JavaPackageName"
    choco install $JavaPackageName -y | Out-Null

    # 1. Try to detect JAVA_HOME from registry (standard Oracle/Open JDK)
    $javaHome = $null
    $registryPaths = @(
        'HKLM:\SOFTWARE\JavaSoft\JDK',
        'HKLM:\SOFTWARE\JavaSoft\Java Development Kit',
        'HKLM:\SOFTWARE\Eclipse Foundation\JDK'
    )

    foreach ($regPath in $registryPaths) {
        if (Test-Path $regPath) {
            try {
                $jdkKey = Get-ChildItem $regPath -ErrorAction Stop | Sort-Object PSChildName -Descending | Select-Object -First 1
                if ($jdkKey) {
                    $props = Get-ItemProperty $jdkKey.PSPath
                    if ($props.JavaHome) {
                        $javaHome = $props.JavaHome
                        Write-Info "Detected JAVA_HOME from registry ($regPath): $javaHome"
                        break
                    }
                }
            } catch {
                $errMsg = $_.Exception.Message
                Write-Verbose "Failed to detect JAVA_HOME from $regPath. Error: $errMsg"
            }
        }
    }

    # 2. Fallback to common vendor locations (e.g., Adoptium)
    if (-not $javaHome) {
        $vendorPaths = @(
            (Join-Path $env:ProgramFiles 'Eclipse Adoptium'),
            (Join-Path $env:ProgramFiles 'Java'),
            (Join-Path $env:SystemDrive 'openjdk')
        )
        foreach ($vPath in $vendorPaths) {
            if (Test-Path $vPath) {
                $latest = Get-ChildItem $vPath -Directory | Sort-Object Name -Descending | Select-Object -First 1
                if ($latest) {
                    $javaHome = $latest.FullName
                    Write-Info "Detected JAVA_HOME from filesystem ($vPath): $javaHome"
                    break
                }
            }
        }
    }

    # 3. Last resort: use where.exe to find java.exe if it's already in the path (e.g. from Chocolatey shim or install)
    if (-not $javaHome) {
        $javaExe = Get-Command java.exe -ErrorAction SilentlyContinue
        if ($javaExe) {
            # javaExe.Definition might be a path to a shim or the real exe
            # If it's a real path like C:\Program Files\...\bin\java.exe, we can get the parent
            $javaBinPath = Split-Path $javaExe.Definition -Parent
            if ($javaBinPath -and $javaBinPath.EndsWith('bin')) {
                $javaHome = Split-Path $javaBinPath -Parent
                Write-Info "Detected JAVA_HOME from PATH (via java.exe): $javaHome"
            }
        }
    }

    if (-not $javaHome -or -not (Test-Path $javaHome)) {
        Write-ErrorAndExit "JAVA_HOME could not be determined after installing $JavaPackageName."
    }

    Write-Info "Setting JAVA_HOME -> $javaHome"
    [Environment]::SetEnvironmentVariable('JAVA_HOME', $javaHome, 'Machine')

    # Update machine PATH with Java bin if missing
    $javaBin = Join-Path $javaHome 'bin'
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    if ($machinePath -notlike "*$javaBin*") {
        [Environment]::SetEnvironmentVariable('Path', "$machinePath;$javaBin", 'Machine')
    }

    # Make available to current session
    $env:JAVA_HOME = $javaHome
    if ($env:Path -notlike "*$javaBin*") {
        $env:Path += ";$javaBin"
    }

    return $javaHome
}

# -------------------------------
# Tomcat functions
# -------------------------------
function Install-Tomcat {
    param(
        [string]$Version,
        [string]$ServiceName,
        [int]$Port,
        [string]$SevenZipPath
    )

    $tomcatBaseDir   = 'C:\\Tools\\Tomcat'
    $tomcatZipUrl    = "https://archive.apache.org/dist/tomcat/tomcat-9/v$Version/bin/apache-tomcat-$Version-windows-x64.zip"
    $tempDir         = 'C:\\Temp'
    $tomcatZipDest   = Join-Path $tempDir "apache-tomcat-$Version.zip"

    if (-not (Test-Path $tempDir)) {
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path $tomcatBaseDir)) {
        New-Item -Path $tomcatBaseDir -ItemType Directory -Force | Out-Null
    }

    Write-Info "Downloading Tomcat from $tomcatZipUrl"
    Test-Download-FileWithRetry -Uri $tomcatZipUrl -OutFile $tomcatZipDest -Attempts 3

    Write-Info "Extracting Tomcat to $tomcatBaseDir"
    & $SevenZipPath x $tomcatZipDest "-o$tomcatBaseDir" -y | Out-Null
    Remove-Item $tomcatZipDest -Force

    $catalinaHome = Join-Path $tomcatBaseDir "apache-tomcat-$Version"
    if (-not (Test-Path $catalinaHome)) {
        Write-ErrorAndExit "Expected directory not found after extraction: $catalinaHome"
    }

    Write-Info "Setting CATALINA_HOME -> $catalinaHome"
    [Environment]::SetEnvironmentVariable('CATALINA_HOME', $catalinaHome, 'Machine')
    $catalinaBin = Join-Path $catalinaHome 'bin'
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    if ($machinePath -notlike "*$catalinaBin*") {
        [Environment]::SetEnvironmentVariable('Path', "$machinePath;$catalinaBin", 'Machine')
    }

    # Session exports
    $env:CATALINA_HOME = $catalinaHome
    if ($env:Path -notlike "*$catalinaBin*") {
        $env:Path += ";$catalinaBin"
    }

    # Configure HTTP connector port in server.xml if needed BEFORE installing/starting service
    try {
        $serverXmlPath = Join-Path $catalinaHome 'conf\server.xml'
        if (Test-Path $serverXmlPath) {
            [xml]$serverXml = Get-Content -Path $serverXmlPath
            # Find the first HTTP Connector with a port attribute
            $connectors = @()
            if ($serverXml.Server.Service.Connector) {
                $connectors = @($serverXml.Server.Service.Connector)
            }
            $httpConnector = $connectors | Where-Object { $_.port -and ($_.protocol -like '*HTTP*' -or -not $_.protocol) } | Select-Object -First 1
            if ($httpConnector) {
                $currentPort = [int]$httpConnector.port
                if ($currentPort -ne $Port) {
                    Write-Info "Updating Tomcat HTTP connector port: $currentPort -> $Port"
                    $httpConnector.port = "$Port"
                    $serverXml.Save($serverXmlPath)
                } else {
                    Write-Info "Tomcat HTTP connector already configured for port $Port"
                }
            } else {
                Write-Warn "No suitable HTTP Connector found in server.xml to update port."
            }
        } else {
            Write-Warn "server.xml not found at $serverXmlPath; skipping port configuration."
        }
    } catch {
        Write-Warn "Failed to update server.xml port: $($_.Exception.Message)"
    }

    # Install Windows service explicitly with name
    $tomcatBin = $catalinaBin
    Write-Info "Installing Tomcat Windows service as '$ServiceName'"
    & (Join-Path $tomcatBin 'service.bat') install $ServiceName | Out-Null

    # Copy Hardened XML Configuration files.
    $catalinaConf = Join-Path $catalinaHome 'conf'
    Copy-Item -Path (Get-ChildItem -Path $HardenedConfigDir -File -Filter *.xml) -Destination $catalinaConf -Force

    # Copy error files
    # Build path to CATALINA_HOME\webapps\ROOT in a compatible way
    $catalinaWebAppRoot         = Join-Path (Join-Path $catalinaHome 'webapps') 'ROOT'
    $catalinaRootErrorFolder    = Join-Path -Path $catalinaWebAppRoot 'error'
    $HardenedConfigErrorDir     = Join-Path -Path $HardenedConfigDir 'error'
    New-Item -Path $catalinaRootErrorFolder -ItemType Directory -Force | Out-Null
    Copy-Item -Path (Get-ChildItem -Path $HardenedConfigErrorDir -File -Filter *.html) -Destination $catalinaRootErrorFolder -Force

    # Configure and start service
    Set-Service -Name $ServiceName -StartupType Automatic
    Start-Service -Name $ServiceName

    # Open firewall port (non-idempotent as per baking context)
    New-NetFirewallRule `
        -DisplayName "Tomcat HTTP Port $Port" `
        -Direction Inbound `
        -Action Allow `
        -Protocol TCP `
        -LocalPort $Port `
        -Profile Any | Out-Null

    Write-Info "Tomcat $Version installation complete."
}

# -------------------------------
# Main
# -------------------------------
Write-Info "Starting Tomcat installer script"
$sevenZipPath = Test-7Zip
$javaHome = Install-JavaAndConfigureEnv -JavaPackageName $JavaPackage
Install-Tomcat -Version $TomcatVersion -ServiceName $TomcatServiceName -Port $TomcatPort -SevenZipPath $sevenZipPath
