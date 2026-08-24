
# Get current client configuration for the Terraform runner
data "azurerm_client_config" "current" {}

# Filter resource groups that are used for storage
locals {
  storage_resource_groups = {
    for i, rg in var.resource_groups : rg.name => {
      id   = azurerm_resource_group.baseline[i].id
      name = rg.name
    }
    if rg.needed.storage_data_plane_access
  }
}

# Grant the Terraform Runner data-plane access to Azure Files.
# Required for managing azurerm_storage_share_directory when network rules are active.
resource "azurerm_role_assignment" "tf_runner_file_data_access" {
  for_each = local.storage_resource_groups

  scope                = each.value["id"]
  role_definition_name = "Storage File Data Privileged Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Grant the Terraform Runner data-plane access to Azure Blobs.
# Required for managing blob containers/objects when network rules are active.
resource "azurerm_role_assignment" "tf_runner_blob_data_access" {
  for_each = local.storage_resource_groups

  scope                = each.value["id"]
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}
