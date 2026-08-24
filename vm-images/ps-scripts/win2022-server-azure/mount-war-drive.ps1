<#
Minimal Azure Files mounter for WAR storage

#>

[CmdletBinding()]
[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '')]
param(
    [string]$ServiceName = "WarDeployService"
)

function Write-ErrorAndExit([string]$msg, [int]$code = 1) {
    Write-Error -Message $msg
    exit $code
}


# Always fetch from Azure IMDS metadata (must be running inside Azure VM)
try {
    Write-Information -MessageData 'Querying Azure Instance Metadata Service for VM tags (tagsList)...' -InformationAction Continue
    $imdsUri = 'http://169.254.169.254/metadata/instance?api-version=2021-02-01'
    $metadata = Invoke-RestMethod -Headers @{ Metadata = 'true' } -Uri $imdsUri -Method GET -TimeoutSec 5 -ErrorAction Stop
    $tagsList = $metadata.compute.tagsList

    $StorageAccount = ($tagsList | Where-Object { $_.name -ieq 'WarStorageAccount' }).value
    $ShareName      = ($tagsList | Where-Object { $_.name -ieq 'WarStorageShare' }).value
    $ShareFolder    = ($tagsList | Where-Object { $_.name -ieq 'WarStorageFolder' }).value
    $DriveLetter    = ($tagsList | Where-Object { $_.name -ieq 'WarStorageDrive' }).value
    $VaultName      = ($tagsList | Where-Object { $_.name -ieq 'WarStorageKeyVault' }).value
    $VaultWarSecret = ($tagsList | Where-Object { $_.name -ieq 'WarStorageKeyName' }).value
}
catch {
    Write-ErrorAndExit ('Failed to query Azure IMDS. Ensure this is running on an Azure VM and IMDS is accessible. Error: {0}' -f $_.Exception.Message)
}

# Single combined missing-tags check (bail if any missing)
if ([string]::IsNullOrWhiteSpace($StorageAccount) -or
    [string]::IsNullOrWhiteSpace($ShareName)      -or
    [string]::IsNullOrWhiteSpace($ShareFolder)    -or
    [string]::IsNullOrWhiteSpace($DriveLetter)    -or
    [string]::IsNullOrWhiteSpace($VaultName)      -or
    [string]::IsNullOrWhiteSpace($VaultWarSecret)) {
    Write-ErrorAndExit "Missing required VM tag(s). Required: WarStorageAccount, WarStorageShare, WarStorageFolder, WarStorageDrive, WarStorageKeyVault, WarStorageKeyName."
}

# Normalize drive letter (strip colon, take first char)
$DriveLetter = ($DriveLetter -replace ':', '').Trim()
if ($DriveLetter.Length -ne 1 -or ($DriveLetter -notmatch '^[A-Za-z]$')) {
    Write-ErrorAndExit ('Invalid DriveLetter ''{0}''. Provide a single letter (e.g., ''Z'').' -f $DriveLetter)
}

# Build share path and endpoint
$endpoint = "${StorageAccount}.file.core.windows.net"
$sharePath = "\\${endpoint}\${ShareName}"

# Normalize and append mandatory subfolder
$ShareFolder = ($ShareFolder -replace '/', '\\')
$ShareFolder = ($ShareFolder -replace '^[\\/]+', '')
$ShareFolder = ($ShareFolder -replace '[\\/]+$', '')
if ([string]::IsNullOrWhiteSpace($ShareFolder)) {
    Write-ErrorAndExit "ShareFolder tag is present but empty/invalid after normalization. Provide a non-empty relative path inside the share."
}
$sharePath = "${sharePath}\${ShareFolder}"
$driveRoot = ("{0}:" -f $DriveLetter)

# Fetch storage account token (account key or SAS) via Azure Key Vault using Managed Identity, via Azure CLI
try {
    Write-Information -MessageData "Connecting to Azure via Managed Identity using Azure CLI..." -InformationAction Continue

    # Ensure az CLI is available
    $azCmd = Get-Command az -ErrorAction Stop

    # Login with Managed Identity (fast, no subscriptions needed for Key Vault data-plane)
    & $azCmd.Source login --identity --allow-no-subscriptions 1>$null 2>$null

    Write-Information -MessageData ("Retrieving secret '{0}' from Key Vault '{1}' via az cli..." -f $VaultWarSecret, $VaultName) -InformationAction Continue

    # Use --id because control plane will default due to lack of subscription. Use dataplane directly hence.
    $Id = "https://${VaultName}.vault.azure.net/secrets/${VaultWarSecret}"
    $secretPlain = (& $azCmd.Source keyvault secret show --id $Id --query value -o tsv 2>$null)

    if ([string]::IsNullOrWhiteSpace($secretPlain)) {
        throw "Secret value is empty or could not be retrieved via Azure CLI."
    }

    # Prepare SMB credential material for Azure Files (global mapping will use username/password)
    # PSScriptAnalyzer suppression for plaintext conversion as it is required for PSCredential.
    $securePassword = ConvertTo-SecureString -String $secretPlain -AsPlainText -Force
    $username = "AZURE\$StorageAccount"
}
catch {
    Write-ErrorAndExit ('Failed to acquire storage token from Key Vault using Azure CLI: {0}' -f $_.Exception.Message)
}

# Prefer Global SMB mapping over PSDrive. If a global mapping exists, ensure it matches the target path.
try {
    $existingGlobal = Get-SmbGlobalMapping -LocalPath $driveRoot -ErrorAction SilentlyContinue
} catch { $existingGlobal = $null }
if ($null -ne $existingGlobal) {
    if ($existingGlobal.RemotePath -ieq $sharePath) {
        Write-Warning -Message ("Global mapping for drive letter {0}: already exists (RemotePath: '{1}'). Bailing out." -f $DriveLetter, $existingGlobal.RemotePath)
        exit 0
    } else {
        Write-Information -MessageData ("Drive {0}: currently mapped to '{1}', expected '{2}'. Replacing..." -f $DriveLetter, $existingGlobal.RemotePath, $sharePath) -InformationAction Continue
        try {
            Remove-SmbGlobalMapping -LocalPath $driveRoot -Force -ErrorAction Stop
        } catch {
            Write-Verbose "Failed to remove existing SMB global mapping for '$driveRoot': $($_.Exception.Message)"
        }
    }
}

# Standard reachability check (TCP 445 via Test-NetConnection only; no fallbacks)
Write-Information -MessageData ('Checking reachability for {0} (TCP:445) using Test-NetConnection...' -f $endpoint) -InformationAction Continue
$tnc = Test-NetConnection -ComputerName $endpoint -Port 445 -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
if (-not [bool]$tnc) {
    Write-ErrorAndExit ('Port 445 is not reachable on {0}. Ensure network rules allow SMB (Azure Files) from this subnet.' -f $endpoint)
}

Write-Information -MessageData ('Creating machine-wide SMB mapping for ''{0}'' as drive {1}...' -f $sharePath, $driveRoot) -InformationAction Continue

try {
    # Create a Global SMB Mapping (machine-wide, not per-user) using PSCredential
    $credential = New-Object System.Management.Automation.PSCredential($username, $securePassword)
    New-SmbGlobalMapping -RemotePath $sharePath -LocalPath $driveRoot -Credential $credential -Persistent $true -ErrorAction Stop | Out-Null
}
catch {
    Write-ErrorAndExit ('Failed to create global SMB mapping ''{0}'' to {1}:. Error: {2}' -f $sharePath, $DriveLetter, $_.Exception.Message)
}

if (-not (Test-Path -Path ($driveRoot + "\"))) {
    Write-ErrorAndExit ('Global mapping created but drive {0} is not accessible.' -f $driveRoot)
}

Write-Information -MessageData ('Global mapping created successfully: {0} -> {1}' -f $driveRoot, $sharePath) -InformationAction Continue

# ---------------------------------------------------------
# Start the service after successful mount
# ---------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($ServiceName)) {
    Write-Information -MessageData "No ServiceName provided, skipping service start." -InformationAction Continue
} else {
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($null -eq $service) {
        Write-Warning "Service '$ServiceName' not found. Cannot start."
    } elseif ($service.Status -eq 'Running') {
        Write-Information -MessageData "Service '$ServiceName' is already running." -InformationAction Continue
    } else {
        Write-Information -MessageData "Starting service '$ServiceName'..." -InformationAction Continue
        try {
            Start-Service -Name $ServiceName -ErrorAction Stop
            Write-Information -MessageData "Service '$ServiceName' started successfully." -InformationAction Continue
        } catch {
            Write-Warning "Failed to start service '$ServiceName': $($_.Exception.Message)"
        }
    }
}
