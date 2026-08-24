# Outputs
output "vm_data" {
  value = {
    ip_addresses = (var.app_vm_config.enabled) ? azurerm_windows_virtual_machine.app_vm[0].private_ip_addresses : null
    machine_name = (var.app_vm_config.enabled) ? azurerm_windows_virtual_machine.app_vm[0].computer_name : null
  }
}
