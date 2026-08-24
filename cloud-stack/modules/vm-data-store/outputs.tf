
# Shares from WAR Storage Account
output "shares" {
  description = "Shares from WAR Storage Account"
  value = {
    storage_account_name = var.storage_account_name
    storage_share_name   = azurerm_storage_share.war_storage_file_share.name
    directory_shares     = zipmap(local.dir_names, local.sanitized_dirs)
    https_shares         = zipmap(local.dir_names, local.https_share_urls)
  }
}

# Key Vault object details for mounting WAR storage
output "keyvault" {
  description = "Key Vault object details for mounting WAR storage"
  value = {
    name        = var.mount_share_control.keyvault_name
    secret_name = azurerm_key_vault_secret.war_storage_token.name
    identity    = azurerm_user_assigned_identity.vm_identity.id
  }
}

# SAS Token for uploading WAR File
output "upload_sas_token" {
  description = "SAS Token for uploading WAR File"
  value       = data.azurerm_storage_account_sas.war_upload_sas.sas
  sensitive   = true
}
