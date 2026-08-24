output "break_glass_keyvault" {
  value = {
    name                  = azurerm_key_vault.break_glass_vault.name
    resource_group_name   = var.resource_group_name
    location              = var.location
    id                    = azurerm_key_vault.break_glass_vault.id
    ad_admin_group_access = var.ad_group_name
  }
}
