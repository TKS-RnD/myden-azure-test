
# Use the naming module.
module "naming" {
  source = "Azure/naming/azurerm"
  suffix = [
    var.environment
  ]
}

# Create the resource group.
resource "azurerm_resource_group" "war_storage" {

  location = var.location
  name     = var.resource_group_name

  tags = var.tags
}

# Create the Storage Account name.
resource "azurerm_storage_account" "war_storage" {

  # The Basics
  name                = var.storage_account_name
  location            = var.location
  resource_group_name = var.resource_group_name

  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Security hardening
  min_tls_version            = "TLS1_2" # Enforce modern TLS
  https_traffic_only_enabled = true

  # Allow public access only for explicitly allow-listed IPs (see network_rules)
  public_network_access_enabled     = true
  infrastructure_encryption_enabled = true # Double encryption at rest

  # Enable Shared key access for Jenkins Upload of WAR
  shared_access_key_enabled = true

  # Harden Azure Files (SMB) and enable soft delete for file shares
  share_properties {
    retention_policy {
      days = 14 # Soft delete retention for accidental deletions
    }

    smb {
      versions             = ["SMB3.0", "SMB3.1.1"]
      authentication_types = ["NTLMv2"]
      # Use widely supported Azure Files SMB channel encryption. Some regions/tenants
      # do not support AES-256-GCM yet, which can cause SMB auth/negotiation to fail
      # with "Access is denied" on mount. AES-128-GCM is broadly supported.
      channel_encryption_type = ["AES-128-GCM"]
    }
  }

  # Restrict network access to the application subnets only
  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = values(var.network_access_control.app_subnet_ids)
    # Allow CI/CD or other trusted public IPs to reach the storage APIs
    ip_rules = var.network_access_control.public_ip_mask
  }

  tags = var.tags
}

# Create a File Share.
resource "azurerm_storage_share" "war_storage_file_share" {

  # File Sharing for dropping WAR builds.
  name               = module.naming.storage_share_directory.name
  storage_account_id = azurerm_storage_account.war_storage.id

  # Only SMB as we use it only on Windows Machines.
  enabled_protocol = "SMB"
  quota            = var.storage_size_in_gb
}

# Directory name sanitization
# 1. replaces all invalid Azure characters at once with "-" via regex.
# 2. normalizes case
# 3. removes leading/trailing dashes
# 4. enforces Azure directory length limit
locals {
  dir_names = keys(var.network_access_control.app_subnet_ids)
  sanitized_dirs = [
    for d in local.dir_names :
    substr(trim(lower(replace(d, "/[\"\\\\/:|<>*?]+/", "-")), "-"), 0, 255)
  ]
  https_share_urls = [
    for d in local.sanitized_dirs :
    "https://${var.storage_account_name}.file.core.windows.net/${azurerm_storage_share.war_storage_file_share.name}/${d}"
  ]
}

# Create multiple directories for application subnets
resource "azurerm_storage_share_directory" "app_subnets" {

  # Iterate through
  for_each = toset(local.sanitized_dirs)

  # Sanitized name
  name              = each.value
  storage_share_url = azurerm_storage_share.war_storage_file_share.url
}
