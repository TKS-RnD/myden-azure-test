# Manage Domain Join related resources.
locals {
  domain_group = ((local.domain_join == 1) &&
    (var.dba_vm_config.domain_join.login_aad_id != null) &&
  (var.dba_vm_config.domain_join.login_role_name != null)) ? 1 : 0
}

# Role definition
data "azurerm_role_definition" "vm_administrator_login" {

  # Count is to control VM creation, deletion for re-building
  count = local.domain_group

  name  = var.dba_vm_config.domain_join.login_role_name
  scope = azurerm_windows_virtual_machine.dba_vm[count.index].id
}

# Assign Role to AAD Group.
resource "azurerm_role_assignment" "builtin_vm_login_assignment" {

  # Count is to control VM creation, deletion for re-building
  count = local.domain_group

  scope              = azurerm_windows_virtual_machine.dba_vm[count.index].id
  role_definition_id = data.azurerm_role_definition.vm_administrator_login[count.index].id
  principal_id       = var.dba_vm_config.domain_join.login_aad_id
}

# Assign "Reader" to the Virtual Network (or Subnet).  This allows the group to see the network path to the VM.
resource "azurerm_role_assignment" "dba_vnet_reader" {
  scope                = var.dba_vm_config.subnet_id
  role_definition_name = "Reader"
  principal_id         = var.dba_vm_config.domain_join.login_aad_id
}

# Assign "Reader" to the Network Interfaces (NIC).  Bastion needs to read the Private IP from the NIC.
resource "azurerm_role_assignment" "dba_nic_reader" {
  count                = length(var.dba_vm_config.nic_ids)
  scope                = var.dba_vm_config.nic_ids[count.index]
  role_definition_name = "Reader"
  principal_id         = var.dba_vm_config.domain_join.login_aad_id
}

# Assign  "Reader" to the VM.
resource "azurerm_role_assignment" "dba_vm_reader" {
  count                = var.dba_vm_config.enabled ? 1 : 0
  scope                = azurerm_windows_virtual_machine.dba_vm[count.index].id
  role_definition_name = "Reader"
  principal_id         = var.dba_vm_config.domain_join.login_aad_id
}

# Allow the dba administrator group to write/read backups (AD groups)
resource "azurerm_role_assignment" "dba_ad_group_storage_access" {
  scope                = azurerm_storage_account.dba_workspace.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = var.dba_vm_config.domain_join.login_aad_id
}

# Allow the dba administrator group to see the storage account and the blob storage.
# This is required for using the storage explorer and various CLI commands in ARM layer.
resource "azurerm_role_assignment" "dba_ad_group_storage_reader" {
  scope                = azurerm_storage_account.dba_workspace.id
  role_definition_name = "Reader"
  principal_id         = var.dba_vm_config.domain_join.login_aad_id
}

# Define a custom role for Power Management
resource "azurerm_role_definition" "vm_power_manager" {
  count = var.dba_vm_config.enabled ? 1 : 0

  name        = "DBA-VM-Power-Manager-${var.environment}"
  scope       = azurerm_windows_virtual_machine.dba_vm[count.index].id
  description = "Allows starting, stopping, and restarting the Support VM."

  permissions {
    actions = [
      "Microsoft.Compute/virtualMachines/read",
      "Microsoft.Compute/virtualMachines/start/action",
      "Microsoft.Compute/virtualMachines/powerOff/action",
      "Microsoft.Compute/virtualMachines/deallocate/action",
      "Microsoft.Compute/virtualMachines/restart/action"
    ]
    not_actions = []
  }

  assignable_scopes = [
    azurerm_windows_virtual_machine.dba_vm[count.index].id
  ]
}

# Assign the custom role to the AD Group
resource "azurerm_role_assignment" "vm_power_management_assignment" {

  count = var.dba_vm_config.enabled ? 1 : 0

  scope              = azurerm_windows_virtual_machine.dba_vm[count.index].id
  role_definition_id = azurerm_role_definition.vm_power_manager[count.index].role_definition_resource_id
  principal_id       = var.dba_vm_config.domain_join.login_aad_id
}
