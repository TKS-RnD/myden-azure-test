# Manage Domain Join related resources.
locals {
  domain_group = ((local.domain_join == 1) &&
    (var.support_vm_config.domain_join.login_aad_id != null) &&
  (var.support_vm_config.domain_join.login_role_name != null)) ? 1 : 0
}

# Existing Role definition
data "azurerm_role_definition" "vm_administrator_login" {

  # Count is to control VM creation, deletion for re-building
  count = local.domain_group

  name  = var.support_vm_config.domain_join.login_role_name
  scope = azurerm_windows_virtual_machine.support_vm[count.index].id
}

# Assign Role to AAD Group.
resource "azurerm_role_assignment" "builtin_vm_login_assignment" {

  # Count is to control VM creation, deletion for re-building
  count = local.domain_group

  scope              = azurerm_windows_virtual_machine.support_vm[count.index].id
  role_definition_id = data.azurerm_role_definition.vm_administrator_login[count.index].id
  principal_id       = var.support_vm_config.domain_join.login_aad_id
}

# Assign "Reader" to the Virtual Network (or Subnet).  This allows the group to see the network path to the VM.
resource "azurerm_role_assignment" "support_vnet_reader" {
  scope                = var.support_vm_config.subnet_id
  role_definition_name = "Reader"
  principal_id         = var.support_vm_config.domain_join.login_aad_id
}

# Assign "Reader" to the Network Interfaces (NIC).  Bastion needs to read the Private IP from the NIC.
resource "azurerm_role_assignment" "support_nic_reader" {
  count                = length(var.support_vm_config.nic_ids)
  scope                = var.support_vm_config.nic_ids[count.index]
  role_definition_name = "Reader"
  principal_id         = var.support_vm_config.domain_join.login_aad_id
}

# Assign  "Reader" to the VM.
resource "azurerm_role_assignment" "support_vm_reader" {
  count                = var.support_vm_config.enabled ? 1 : 0
  scope                = azurerm_windows_virtual_machine.support_vm[count.index].id
  role_definition_name = "Reader"
  principal_id         = var.support_vm_config.domain_join.login_aad_id
}

# Define a custom role for Power Management
resource "azurerm_role_definition" "vm_power_manager" {
  count = var.support_vm_config.enabled ? 1 : 0

  name        = "Support-VM-Power-Manager-${var.environment}"
  scope       = azurerm_windows_virtual_machine.support_vm[count.index].id
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
    azurerm_windows_virtual_machine.support_vm[count.index].id
  ]
}

# Assign the custom role to the AD Group
resource "azurerm_role_assignment" "vm_power_management_assignment" {

  count = var.support_vm_config.enabled ? 1 : 0

  scope              = azurerm_windows_virtual_machine.support_vm[count.index].id
  role_definition_id = azurerm_role_definition.vm_power_manager[count.index].role_definition_resource_id
  principal_id       = var.support_vm_config.domain_join.login_aad_id
}
