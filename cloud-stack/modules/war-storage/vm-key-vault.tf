# Current subscription and tenant
data "azurerm_subscription" "current" {}
data "azuread_client_config" "current" {}
data "azurerm_client_config" "current" {}

# Create Key Vault
resource "azurerm_key_vault" "war_storage_vault" {

  # Key Vault Name
  name = var.mount_share_control.keyvault_name

  # Location and Resource Group Name
  location            = var.location
  resource_group_name = var.resource_group_names.vault

  # Tenant and SKU
  tenant_id = data.azurerm_subscription.current.tenant_id
  sku_name  = "standard"

  # MANDATORY: Enable RBAC model (ignores legacy access policies)
  rbac_authorization_enabled = true

  # SECURITY: Prevent purging of deleted items
  purge_protection_enabled   = true
  soft_delete_retention_days = 90

  tags = var.tags
}

# Grant Terraform (Runner) the right to WRITE secrets
resource "azurerm_role_assignment" "tf_officer" {
  scope                = azurerm_key_vault.war_storage_vault.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azuread_client_config.current.object_id
}

# Store the Storage Key
resource "azurerm_key_vault_secret" "war_storage_token" {
  key_vault_id = azurerm_key_vault.war_storage_vault.id
  name         = "war-storage-account-key"
  value        = azurerm_storage_account.war_storage.secondary_access_key
  depends_on   = [azurerm_role_assignment.tf_officer]

  tags = merge(var.tags, {
    accessible_by = var.mount_share_control.managed_identity_name
  })
}

# Grant the VM's Managed identity to read only this secret from the vault.
resource "azurerm_role_assignment" "admin_reader" {
  scope                = "${azurerm_key_vault.war_storage_vault.id}/secrets/${azurerm_key_vault_secret.war_storage_token.name}"
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.mount_share_control.managed_identity_id
}

# GOVERNANCE: PREVENT ACCIDENTAL DELETION for production.
resource "azurerm_management_lock" "war_storage_vault_lock" {

  count = (var.environment == "production") ? 1 : 0

  name       = "can-not-delete-lock"
  scope      = azurerm_key_vault.war_storage_vault.id
  lock_level = "CanNotDelete"
  notes      = "This is a VM Key vault. Deletion requires a change request."
}
