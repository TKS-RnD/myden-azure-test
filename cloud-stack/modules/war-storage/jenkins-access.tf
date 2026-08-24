
# Define a Custom Role that only allows WAR upload (via File Share) and minimal read/list access.
# No network management is needed as Jenkins uses a static public IP.
resource "azurerm_role_definition" "jenkins_war_uploader" {
  name        = "Jenkins-WAR-Uploader"
  description = "Allows Jenkins to upload WAR files to specific file shares and list resources."

  scope = azurerm_storage_account.war_storage.id

  permissions {

    # Needs these control plane actions.
    actions = [
      "Microsoft.Storage/storageAccounts/read",
      "Microsoft.Storage/storageAccounts/fileServices/read",
      "Microsoft.Storage/storageAccounts/fileServices/shares/read"
    ]

    # Explicitly DENY destructive and sensitive actions (copied from GitHub uploader for consistency)
    not_actions = [
      "Microsoft.Storage/storageAccounts/delete",
      "Microsoft.Storage/storageAccounts/fileServices/shares/delete",
      "Microsoft.Storage/storageAccounts/blobServices/containers/delete",
      "Microsoft.Storage/storageAccounts/listKeys/action",
      "Microsoft.Storage/storageAccounts/regenerateKey/action",
      "Microsoft.Storage/storageAccounts/listAccountSas/action",
      "Microsoft.Authorization/roleAssignments/write",
      "Microsoft.Authorization/roleAssignments/delete",
      "Microsoft.Authorization/locks/delete"
    ]
  }

  # WAR Storage
  assignable_scopes = [
    azurerm_storage_account.war_storage.id
  ]
}

# Assign the Custom Role to the Jenkins Managed application
resource "azurerm_role_assignment" "jenkins_custom_assignment" {
  scope              = azurerm_storage_account.war_storage.id
  role_definition_id = azurerm_role_definition.jenkins_war_uploader.role_definition_resource_id
  principal_id       = var.upload_control.jenkins_managed_application.service_principal_id
}

# Permission: Give Jenkins managed application access to read the generated SAS from Key Vault
resource "azurerm_role_assignment" "jenkins_kv_access" {
  scope                = azurerm_key_vault.war_upload.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.upload_control.jenkins_managed_application.service_principal_id
}
