
# Shares from WAR Storage Account
output "shares" {
  description = "Shares from WAR Storage Account"
  value = {
    storage_account_name = var.storage_account_name
    resource_group       = var.resource_group_names.storage
    storage_share_name   = azurerm_storage_share.war_storage_file_share.name
    directory_shares     = zipmap(local.dir_names, local.sanitized_dirs)
    https_shares         = zipmap(local.dir_names, local.https_share_urls)
  }
}

# Key Vault object details for mounting WAR storage
output "keyvault" {
  description = "Key Vault object details for mounting WAR storage"
  value = {
    name           = var.mount_share_control.keyvault_name
    resource_group = var.resource_group_names.vault
    secret_names = {
      for_mounting_vms = azurerm_key_vault_secret.war_storage_token.name
    }
  }
}

# GitHub variables needed for uploading WARs.
output "github" {
  value = {
    client_id       = var.upload_control.github_managed_identity.client_id
    tenant_id       = var.upload_control.github_managed_identity.tenant_id
    subscription_id = data.azurerm_subscription.current.subscription_id
    secret_id       = azurerm_key_vault_secret.upload_sas_token.versionless_id
  }
}

# Jenkins variables needed for uploading WARs.
output "jenkins" {
  sensitive = true
  value = {
    app_id               = var.upload_control.jenkins_managed_application.app_id
    service_principal_id = var.upload_control.jenkins_managed_application.service_principal_id
    tenant_id            = var.upload_control.jenkins_managed_application.tenant_id
    subscription_id      = data.azurerm_subscription.current.subscription_id
    secret_id            = azurerm_key_vault_secret.upload_sas_token.versionless_id
    password             = var.upload_control.jenkins_managed_application.credential
  }
}

# Output the Workspace ID for use in Log Analytics queries
output "log_analytics_workspace_id" {
  value       = azurerm_log_analytics_workspace.war_storage_analytics.id
  description = "The ID of the Log Analytics Workspace created for storage analytics."
}
