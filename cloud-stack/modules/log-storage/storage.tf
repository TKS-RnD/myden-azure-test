# Use the naming module.
module "naming" {
  source = "Azure/naming/azurerm"
  suffix = [
    var.environment
  ]
}

# Storage account
resource "azurerm_storage_account" "app_logs" {

  name                = var.storage_account_name
  resource_group_name = var.resource_group_name
  location            = var.location

  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  # Required for SFTP
  is_hns_enabled = true
  sftp_enabled   = true

  # Security best practices
  min_tls_version                   = "TLS1_2"
  allow_nested_items_to_be_public   = false
  public_network_access_enabled     = true
  shared_access_key_enabled         = false
  infrastructure_encryption_enabled = true

  blob_properties {
    versioning_enabled  = false
    change_feed_enabled = false
  }

  # Network rules
  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = values(var.network_access_control)
  }

  # Tags
  tags = var.tags
}

# Container.
resource "azurerm_storage_container" "app_logs" {
  name                  = module.naming.storage_container.name
  storage_account_id    = azurerm_storage_account.app_logs.id
  container_access_type = "private"
}

# Managed Identities Write access
resource "azurerm_role_assignment" "vm_write_to_storage" {

  count = length(var.managed_identities_writer)

  scope                = azurerm_storage_account.app_logs.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.managed_identities_writer[count.index]

  depends_on = [azurerm_storage_account.app_logs] # to avoid contention errors.
}

# Managed Identities Read access
resource "azurerm_role_assignment" "vm_read_to_storage" {

  count = length(var.managed_identities_reader)

  scope                = azurerm_storage_account.app_logs.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = var.managed_identities_reader[count.index]

  depends_on = [azurerm_storage_account.app_logs] # to avoid contention errors.
}

# AD Groups Read access
resource "azurerm_role_assignment" "ad_group_read_to_storage" {

  count = length(var.ad_groups_reader)

  scope                = azurerm_storage_account.app_logs.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = var.ad_groups_reader[count.index]

  depends_on = [azurerm_storage_account.app_logs] # to avoid contention errors.
}

# Allow the support  group to see the storage account and the blob storage.
# This is required for using the storage explorer and various CLI commands in ARM layer.
resource "azurerm_role_assignment" "ad_group_storage_reader" {

  count = length(var.ad_groups_reader)

  scope                = azurerm_storage_account.app_logs.id
  role_definition_name = "Reader"
  principal_id         = var.ad_groups_reader[count.index]
}
