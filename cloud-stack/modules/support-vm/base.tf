
# Random password for the Break Glass Administrator account.
resource "random_password" "vm_admin_password" {
  length      = 15
  min_special = 2
  min_numeric = 2
  min_lower   = 1
  min_upper   = 1
}

# Store the Break glass password in key vault
resource "azurerm_key_vault_secret" "vm_break_glass_password" {
  key_vault_id = var.support_vm_config.break_glass_keyvault_id
  name         = "${var.support_vm_config.vm_name}-admin-password"
  value        = random_password.vm_admin_password.result
  tags         = var.tags
}
