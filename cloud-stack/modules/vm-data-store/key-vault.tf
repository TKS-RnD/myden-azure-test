
# Current subscription and tenant
data "azurerm_subscription" "current" {}
data "azuread_client_config" "current" {}

# Create Key Vault
resource "azurerm_key_vault" "war_storage_vault" {

  # Key Vault Name
  name = var.mount_share_control.keyvault_name

  # Location and Resource Group Name
  location            = var.location
  resource_group_name = azurerm_resource_group.war_storage.name

  # Tenant and SKU
  tenant_id = data.azurerm_subscription.current.tenant_id
  sku_name  = "standard"

  # Retention for 7 days.
  soft_delete_retention_days = 7

  tags = var.tags
}

# Grant the signed-in (Azure CLI) principal write access to Key Vault secrets
resource "azurerm_key_vault_access_policy" "tf_cli_access" {
  key_vault_id = azurerm_key_vault.war_storage_vault.id

  tenant_id = data.azurerm_subscription.current.tenant_id
  object_id = data.azuread_client_config.current.object_id

  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete",
    "Purge"
  ]
}

# Managed Identity for accessing the vault
resource "azurerm_user_assigned_identity" "vm_identity" {
  name                = var.mount_share_control.managed_identity_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags = merge(var.tags, {
    Storage = azurerm_storage_share.war_storage_file_share.url
  })
}

# Allow the  identity to read secrets from the Key Vault to get SAS Token.
resource "azurerm_key_vault_access_policy" "ad_group" {

  key_vault_id = azurerm_key_vault.war_storage_vault.id
  tenant_id    = data.azurerm_subscription.current.tenant_id
  object_id    = azurerm_user_assigned_identity.vm_identity.principal_id

  key_permissions = [
    "Get",
    "List"
  ]

  secret_permissions = [
    "Get",
    "List"
  ]

}

# Store the Storage Key
resource "azurerm_key_vault_secret" "war_storage_token" {
  key_vault_id = azurerm_key_vault.war_storage_vault.id
  name         = "war-storage-account-key"
  value        = azurerm_storage_account.war_storage.secondary_access_key
  depends_on   = [azurerm_key_vault_access_policy.tf_cli_access]
}
