
# Subscription
data "azurerm_subscription" "current" {}

# Client config
data "azuread_client_config" "current" {}

# Create Key Vault
resource "azurerm_key_vault" "break_glass_vault" {

  # Key Vault Name
  name = var.keyvault_name

  # Location and Resource Group Name
  location            = var.location
  resource_group_name = var.resource_group_name

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
  scope                = azurerm_key_vault.break_glass_vault.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azuread_client_config.current.object_id
}

# Grant Admins the right to ONLY READ secrets via Portal
resource "azurerm_role_assignment" "admin_reader" {
  scope                = azurerm_key_vault.break_glass_vault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.ad_group_name.id
}

# GOVERNANCE: PREVENT ACCIDENTAL DELETION for production.
resource "azurerm_management_lock" "vault_lock" {

  count = (var.environment == "production") ? 1 : 0

  name       = "can-not-delete-lock"
  scope      = azurerm_key_vault.break_glass_vault.id
  lock_level = "CanNotDelete"
  notes      = "This is a break-glass vault. Deletion requires a change request."
}
