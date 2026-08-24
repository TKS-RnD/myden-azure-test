# Activate Directory group roles.
resource "azuread_directory_role" "directory_role" {
  for_each     = toset(var.terraform-admin-ad-group-builtin-roles)
  display_name = each.value
}

# Assign Directory role to Terraform administrator group.
resource "azuread_directory_role_assignment" "directory_role_assignment" {
  for_each            = toset(var.terraform-admin-ad-group-builtin-roles)
  role_id             = azuread_directory_role.directory_role[each.value].template_id
  principal_object_id = azuread_group.terraform_admin_group.object_id
}

# Resource group names.
data "azurerm_resource_group" "terraform_role_owner" {
  for_each = var.resource_groups_owner_access
  name     = each.value
}

# Assign Azure Subscription Owner permission to Terraform administrator.
resource "azurerm_role_assignment" "azure_rm_owner_assignment" {
  for_each             = var.resource_groups_owner_access
  scope                = data.azurerm_resource_group.terraform_role_owner[each.value].id
  role_definition_name = "Owner"
  principal_id         = azuread_group.terraform_admin_group.object_id
}

# Storage container and storage account.
data "azurerm_storage_account" "tf_state_storage_account" {
  name                = var.proxy_app_workspace.storage_account_name
  resource_group_name = var.proxy_app_workspace.resource_group_name
}

data "azurerm_storage_container" "tf_state_container" {
  name               = var.proxy_app_workspace.container_name
  storage_account_id = data.azurerm_storage_account.tf_state_storage_account.id
}

# Assign Storage Blob data contributor so that terraform state can be stored by the role.
resource "azurerm_role_assignment" "tf_state_access" {
  scope                = data.azurerm_storage_container.tf_state_container.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_group.terraform_admin_group.object_id
}
