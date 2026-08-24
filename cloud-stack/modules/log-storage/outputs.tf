
# Log Storage account
output "shares" {
  description = "Containers from Log Storage Account"
  value = {
    storage_account_name = var.storage_account_name
    resource_group       = var.resource_group_name
    container_name       = azurerm_storage_container.app_logs.name
    mi_readers           = var.managed_identities_reader
    mi_writers           = var.managed_identities_writer
  }
}
