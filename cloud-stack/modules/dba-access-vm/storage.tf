# Create the Storage Account name.
resource "azurerm_storage_account" "dba_workspace" {

  # The Basics
  name                = var.storage_workspace.storage_account_name
  location            = var.storage_workspace.location
  resource_group_name = var.storage_workspace.resource_group_name

  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Security hardening
  min_tls_version            = "TLS1_2" # Enforce modern TLS
  https_traffic_only_enabled = true

  # No Public access
  public_network_access_enabled     = true
  infrastructure_encryption_enabled = true # Double encryption at rest

  # No shared access key
  shared_access_key_enabled = false

  # Blob properties
  blob_properties {
    versioning_enabled = true
    container_delete_retention_policy {
      days = 30
    }
    delete_retention_policy {
      days                     = 30
      permanent_delete_enabled = true
    }
    last_access_time_enabled = true
  }

  # Restrict network access to the application subnets only
  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
    virtual_network_subnet_ids = [
      var.dba_vm_config.subnet_id
    ]
    # No IP Access except via local network.
    ip_rules = []
  }

  tags = var.tags
}

# Create a Blob container for DBA work.
resource "azurerm_storage_container" "dba_container" {
  name                  = var.storage_workspace.blob_name
  storage_account_id    = azurerm_storage_account.dba_workspace.id
  container_access_type = "private"
}

# Delete after X days.
resource "azurerm_storage_management_policy" "delete_after_days" {

  storage_account_id = azurerm_storage_account.dba_workspace.id

  rule {
    name    = "delete-after-days"
    enabled = true

    filters {
      blob_types   = ["blockBlob"]
      prefix_match = ["${var.storage_workspace.blob_name}/"]
    }

    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = var.storage_workspace.delete_after_days
      }
    }
  }
}

# Export the URL for Blob storage
locals {
  blob_storage_url = "${azurerm_storage_account.dba_workspace.primary_blob_endpoint}${var.storage_workspace.blob_name}"
}
