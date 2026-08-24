<#
.SYNOPSIS
Creates an Azure resource group, storage account, and private container for Terraform state using Azure CLI.
#>

$ErrorActionPreference = 'Stop'

function New-ResourceGroup {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param (
        [string]$resourceGroupName,
        [string]$location
    )

    # Check if the resource group already exists (use 'az group exists' to avoid relying on errors)
    $rgExists = az group exists --name $resourceGroupName --output tsv
    if ($rgExists -eq 'true') {
        Write-Output "Resource group '$resourceGroupName' already exists."
        return
    }

    # Create the resource group if it doesn't exist
    $target = "Resource group '$resourceGroupName' in location '$location'"
    if ($PSCmdlet.ShouldProcess($target, 'Create')) {
        Write-Output "Creating $target..."
        az group create --name $resourceGroupName --location $location | Out-Null
    } else {
        Write-Verbose "WhatIf: Create $target"
    }
}

function New-StorageAccount {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param (
        [string]$storageAccountName,
        [string]$resourceGroupName,
        [string]$location
    )

    # Use list and filter to avoid error-based existence checks
    $existing = az storage account list `
        --resource-group $resourceGroupName `
        --query "[?name=='$storageAccountName'].name | [0]" `
        --output tsv

    if ($existing) {
        Write-Output "Storage account '$storageAccountName' already exists in resource group '$resourceGroupName'."
        return
    }

    $target = "Storage account '$storageAccountName' in resource group '$resourceGroupName' (location: $location)"
    if ($PSCmdlet.ShouldProcess($target, 'Create and configure')) {
        Write-Output "Creating storage account '$storageAccountName' in resource group '$resourceGroupName' (location: $location)..."
        az storage account create `
            --name $storageAccountName `
            --resource-group $resourceGroupName `
            --location $location `
            --sku Standard_LRS `
            --kind StorageV2 `
            --https-only true `
            --allow-blob-public-access false `
            --min-tls-version TLS1_2 | Out-Null

        # Harden storage account for state safety: enable blob versioning and soft delete
        az storage account blob-service-properties update `
            --account-name $storageAccountName `
            --resource-group $resourceGroupName `
            --enable-versioning `
            --enable-delete-retention true `
            --delete-retention-days 7 `
            --container-retention --enable-container-delete-retention `
            --container-delete-retention-days 7 | Out-Null

        # Build lifecycle management policy JSON in a cross-platform-safe way
        $lifecyclePolicy = @{ rules = @(
                @{ enabled = $true;
                   name = 'delete-old-versions';
                   type = 'Lifecycle';
                   definition = @{ filters = @{ blobTypes = @('blockBlob') };
                                   actions = @{ version = @{ delete = @{ daysAfterCreationGreaterThan = 180 } } } }
                }
            )
        }
        $json = $lifecyclePolicy | ConvertTo-Json -Depth 6

        # Write to a temp file to avoid quoting issues on Windows PowerShell
        $tmp = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), '.json')
        try {
            Set-Content -Path $tmp -Value $json -Encoding UTF8

            # Assign to blob storage.
            Write-Output "Applying lifecycle management policy to $storageAccountName..."
            az storage account management-policy create `
                --account-name $storageAccountName `
                --resource-group $resourceGroupName `
                --policy (Get-Content -Path $tmp -Raw) | Out-Null
        } finally {
            # Cleanup temp file
            if (Test-Path $tmp) { Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue }
        }

        # Try to require infrastructure encryption if supported (ignore failure)
        try {
            az storage account update `
                --name $storageAccountName `
                --resource-group $resourceGroupName `
                --encryption-services blob file table queue | Out-Null
        } catch {
            Write-Output "Infrastructure encryption not supported in this region/SKU; proceeding without it."
        }
    } else {
        Write-Verbose "WhatIf: Create and configure $target"
    }
}

function Get-StorageAccountKey {
    param (
        [string]$resourceGroupName,
        [string]$storageAccountName
    )
    return az storage account keys list `
        --resource-group $resourceGroupName `
        --account-name $storageAccountName `
        --query "[0].value" `
        --output tsv
}

function New-StorageContainer {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param (
        [string]$containerName,
        [string]$storageAccountName,
        [string]$storageKey
    )

    # Check if the storage container already exists using a non-error-based command
    $containerExists = az storage container exists `
        --name $containerName `
        --account-name $storageAccountName `
        --account-key $storageKey `
        --query "exists" `
        --output tsv

    if ($containerExists -eq 'true') {
        Write-Output "Storage container '$containerName' already exists in the storage account '$storageAccountName'."
        return
    }

    # Create the storage container if it doesn't exist
    $target = "Storage container '$containerName' in storage account '$storageAccountName'"
    if ($PSCmdlet.ShouldProcess($target, 'Create')) {
        Write-Output "Creating $target..."
        az storage container create `
            --name $containerName `
            --account-name $storageAccountName `
            --account-key $storageKey `
            --public-access off | Out-Null
    } else {
        Write-Verbose "WhatIf: Create $target"
    }
}

function Test-AzLogin {
    # Ensure az CLI is installed
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        Write-Error "Azure CLI (az) is not installed."
        Write-Error "Install: https://learn.microsoft.com/cli/azure/install-azure-cli"
        throw "Azure CLI (az) not installed."
    }

    # Ensure user is logged in
    $isLoggedIn = az account show --query "id" --output tsv 2>$null
    if (-not $isLoggedIn) {
        Write-Output "You are not logged in to Azure. Launching 'az login'..."
        az login | Out-Null
    } else {
        Write-Output "You are already logged in to Azure."
    }
}

function Test-UserPermission {
    $roleAssignments = az role assignment list --query "[].roleDefinitionName" --output tsv 2>$null
    $hasPerms = $roleAssignments -and (
        $roleAssignments -contains "Owner" -or $roleAssignments -contains "Contributor"
    )
    if (-not $hasPerms) {
        Write-Output "You may not have sufficient permissions to create resources."
        Write-Output "Ensure your account has 'Owner' or 'Contributor' at subscription or resource group scope."
    } else {
        Write-Output "You appear to have sufficient permissions to create resources."
    }
}

function Get-InputWithDefault {
    param (
        [Parameter(Mandatory=$true)][string]$Prompt,
        [string]$Default = ""
    )
    $displayDefault = if ([string]::IsNullOrWhiteSpace($Default)) { '' } else { " [$Default]" }
    $userInput = Read-Host "$Prompt$displayDefault"
    if ([string]::IsNullOrWhiteSpace($userInput)) { return $Default } else { return $userInput }
}

function Convert-StorageAccountName {
    param ([Parameter(Mandatory=$true)][string]$Name)
    # Storage account rules: 3-24 chars, lowercase letters and numbers only
    $sanitized = ($Name.ToLower() -replace "[^a-z0-9]", "")
    if ($sanitized.Length -gt 24) { $sanitized = $sanitized.Substring(0,24) }
    if ($sanitized.Length -lt 3)   { $sanitized = $sanitized.PadRight(3,'0') }
    return $sanitized
}

function Get-GloballyUniqueStorageAccountName {
    param (
        [Parameter(Mandatory=$true)][string]$BaseName
    )

    $name = $BaseName
    # Check global availability; if unavailable, append a random 4-6 char suffix until available
    for ($i = 0; $i -lt 10; $i++) {
        $available = az storage account check-name --name $name --query "nameAvailable" --output tsv 2>$null
        if ($available -eq 'true') { return $name }
        # Append a short random suffix (keeping <=24 chars)
        $suffix = -join ((48..57 + 97..122) | Get-Random -Count 5 | ForEach-Object {[char]$_})
        $candidate = "$BaseName$suffix"
        if ($candidate.Length -gt 24) {
            $trim = 24 - $suffix.Length
            if ($trim -lt 3) { $trim = 3 }
            $candidate = $BaseName.Substring(0, $trim) + $suffix
        }
        $name = $candidate
    }
    throw "Unable to find a globally unique storage account name based on '$BaseName'. Try a different base."
}

function Convert-ContainerName {
    param ([Parameter(Mandatory=$true)][string]$Name)
    # Container rules: 3-63 chars; lowercase letters, numbers, and hyphen; must start/end with letter or number
    $sanitized = ($Name.ToLower() -replace "[^a-z0-9-]", "-")
    $sanitized = $sanitized.Trim('-')
    if ($sanitized.Length -gt 63) { $sanitized = $sanitized.Substring(0,63).Trim('-') }
    if ($sanitized.Length -lt 3)   { $sanitized = $sanitized.PadRight(3,'a') }
    return $sanitized
}

function Main {

    # Check Azure login status
    Test-AzLogin

    # Check user permissions (warn only)
    Test-UserPermission

    # Defaults (use valid Azure naming conventions)
    $defaultResourceGroupPrefix = "rg-tfstate"
    $defaultStorageAccountPrefix = "tfstate"
    $defaultContainerPrefix = "tfstate"
    $defaultLocation = "centralindia"

    # Prompt user for values (empty input accepts the shown default)
    $rgInput = Get-InputWithDefault -Prompt "Enter Resource Group name" -Default $defaultResourceGroupPrefix
    $resourceGroupName = $rgInput

    $saInput = Get-InputWithDefault -Prompt "Enter Storage Account name (sanitized to meet Azure rules)" -Default $defaultStorageAccountPrefix
    $storageAccountBase = Convert-StorageAccountName -Name $saInput

    # Ensure global uniqueness as required by Azure
    $storageAccountName = Get-GloballyUniqueStorageAccountName -BaseName $storageAccountBase
    if ($storageAccountName -ne $storageAccountBase) {
        Write-Output "Provided storage account name '$storageAccountBase' is not globally unique. Using '$storageAccountName' instead."
    }

    $containerInput = Get-InputWithDefault -Prompt "Enter Blob Container name" -Default $defaultContainerPrefix
    $containerName = Convert-ContainerName -Name $containerInput

    $location = Get-InputWithDefault -Prompt "Enter Azure Location (e.g., eastus, centralindia)" -Default $defaultLocation

    # Create resources
    New-ResourceGroup -resourceGroupName $resourceGroupName -location $location
    New-StorageAccount -storageAccountName $storageAccountName -resourceGroupName $resourceGroupName -location $location
    $storageKey = Get-StorageAccountKey -resourceGroupName $resourceGroupName -storageAccountName $storageAccountName
    New-StorageContainer -containerName $containerName -storageAccountName $storageAccountName -storageKey $storageKey
}

Main
