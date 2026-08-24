# Outputs
output "vm_data" {
  value = {
    ip_addresses = (var.support_vm_config.enabled) ? azurerm_windows_virtual_machine.support_vm[0].private_ip_addresses : null
    machine_name = (var.support_vm_config.enabled) ? azurerm_windows_virtual_machine.support_vm[0].computer_name : null
  }
}
