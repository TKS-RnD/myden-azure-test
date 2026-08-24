
# Subscription
data "azurerm_subscription" "current" {}

# Client config
data "azuread_client_config" "current" {}

# Create Key Vault
resource "azurerm_key_vault" "dba_vm_keyvault" {

  # Key Vault Name
  name = var.dba_keyvault.name

  # Location and Resource Group Name
  location            = var.dba_keyvault.location
  resource_group_name = var.dba_keyvault.resource_group_name

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
  scope                = azurerm_key_vault.dba_vm_keyvault.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azuread_client_config.current.object_id
}

# Grant DBA Administrators the right to WRITE secrets.
resource "azurerm_role_assignment" "dba_admin_writer" {
  scope                = azurerm_key_vault.dba_vm_keyvault.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.dba_keyvault.write_access_ad_group_id
}

# Grant the Managed Identity (DBA VM) the right to WRITE secrets.
resource "azurerm_role_assignment" "dba_vm_writer" {
  scope                = azurerm_key_vault.dba_vm_keyvault.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.identities.dba_vm.principal_id
}

# Grant the Managed Identity (APP VM) the right to WRITE secrets.
resource "azurerm_role_assignment" "app_vm_reader" {
  scope                = azurerm_key_vault.dba_vm_keyvault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.identities.app_vm.principal_id
}

# GOVERNANCE: PREVENT ACCIDENTAL DELETION for production.
resource "azurerm_management_lock" "vault_lock" {

  count = (var.environment == "production") ? 1 : 0

  name       = "can-not-delete-lock"
  scope      = azurerm_key_vault.dba_vm_keyvault.id
  lock_level = "CanNotDelete"
  notes      = "This is a DBA Administrator vault. Deletion requires a change request."
}
