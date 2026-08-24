
# Define a Custom Role that allows dynamic update of network ip and also upload access. This allows GitHub
# scripts to punch a hole in storage firewall for a short time.
resource "azurerm_role_definition" "github_uploader_custom" {
  name        = "GitHub-Storage-Network-Manager"
  description = "Allows GitHub to modify firewall rules but NOT touch data or delete resources."

  scope = azurerm_storage_account.war_storage.id
  permissions {
    actions = [
      "Microsoft.Storage/storageAccounts/read",
      "Microsoft.Storage/storageAccounts/write" # Required for networkRuleSet updates. This is too high a permission but no choice for now.
    ]

    # Explicitly DENY destructive and sensitive actions
    not_actions = [
      # 1. Resource Destruction
      "Microsoft.Storage/storageAccounts/delete",
      "Microsoft.Storage/storageAccounts/fileServices/shares/delete",
      "Microsoft.Storage/storageAccounts/blobServices/containers/delete",

      # 2. Credential Theft
      "Microsoft.Storage/storageAccounts/listKeys/action",
      "Microsoft.Storage/storageAccounts/regenerateKey/action",
      "Microsoft.Storage/storageAccounts/listAccountSas/action", # Prevent generating global SAS tokens

      # 3. Privilege Escalation (Security)
      "Microsoft.Authorization/roleAssignments/write",
      "Microsoft.Authorization/roleAssignments/delete",

      # 4. Lock Bypass
      "Microsoft.Authorization/locks/delete"
    ]
  }

  assignable_scopes = [
    azurerm_storage_account.war_storage.id
  ]
}

# Assign the Custom Role to the Identity
resource "azurerm_role_assignment" "custom_assignment" {
  scope              = azurerm_storage_account.war_storage.id
  role_definition_id = azurerm_role_definition.github_uploader_custom.role_definition_resource_id
  principal_id       = var.upload_control.github_managed_identity.principal_id
}

# Permission: Give GitHub Identity access to read the generated SAS from Key Vault
resource "azurerm_role_assignment" "github_kv_access" {
  scope                = azurerm_key_vault.war_upload.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.upload_control.github_managed_identity.principal_id
}

# Federated Credentials (Repeat for each repo)
resource "azurerm_federated_identity_credential" "github_oidc" {
  for_each            = toset(var.upload_control.github_repos)
  name                = replace(replace(each.value, "/", "-"), ":", "-")
  resource_group_name = var.upload_control.github_managed_identity.resource_group_name
  parent_id           = var.upload_control.github_managed_identity.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = "repo:${each.value}"
}
