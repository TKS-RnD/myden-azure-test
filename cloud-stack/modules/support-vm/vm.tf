# Get details about a custom image if it is provided and defined.
data "azurerm_image" "custom_image" {

  # Image information.
  resource_group_name = var.support_vm_config.custom_image.resource_group_name
  name                = var.support_vm_config.custom_image.name
}

# Create the App VM.
resource "azurerm_windows_virtual_machine" "support_vm" {

  # Count is to control VM creation, deletion for re-building, than using terraform destroy or delete.
  count = var.support_vm_config.enabled ? 1 : 0

  # Basics
  name                = var.support_vm_config.vm_name
  location            = var.location
  resource_group_name = var.resource_group_name

  # VM Size
  size = var.support_vm_config.vm_size

  # Network Interfaces to link with.
  network_interface_ids = var.support_vm_config.nic_ids

  # Image ID based on specification
  source_image_id = data.azurerm_image.custom_image.id

  # Hot Patch mode
  hotpatching_enabled   = false
  patch_mode            = "AutomaticByOS"
  patch_assessment_mode = "AutomaticByPlatform"

  # Timezone
  timezone = "India Standard Time"

  # OS Disk
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  # Break Glass credentials
  admin_username = "${var.support_vm_config.vm_name}-admin"
  admin_password = random_password.vm_admin_password.result

  # System Managed VM Identity
  identity {
    type = "UserAssigned"
    identity_ids = [
      var.support_vm_config.log_storage.managed_identity
    ]
  }

  # VM Metadata (tags) used for log storage.
  tags = merge(var.tags, {
    LogStorageAccount   = var.support_vm_config.log_storage.storage_account_name
    LogStorageFolder    = var.support_vm_config.log_storage.storage_container_name
    DataDiskLuns        = join(";", local.drive_lun_array)
    Auto-Power-Off-On   = "true"
    Idle-Duration-Hours = "4"
  })
}

# Manage Domain Join related resources.
locals {
  domain_join = (var.support_vm_config.enabled && var.support_vm_config.domain_join.should_join_aad) ? 1 : 0
}

# Should Join Domain?
resource "azurerm_virtual_machine_extension" "vm_aad_join" {

  # Count is to control VM creation, deletion for re-building
  count = local.domain_join

  # Other Values
  name                       = "AADLoginForWindows"
  virtual_machine_id         = azurerm_windows_virtual_machine.support_vm[count.index].id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADLoginForWindows"
  type_handler_version       = "2.0"
  auto_upgrade_minor_version = true

  // Dependency
  depends_on = [
    azurerm_virtual_machine_data_disk_attachment.support_vm_data_disks
  ]
}

# For running custom scripts.
locals {
  is_custom_scripts = ((var.support_vm_config.enabled) && (length(var.support_vm_config.custom_image.existing_scripts) > 0))

  # Construct the PowerShell command to execute multiple scripts.
  # It joins the scripts using '&&' for sequential execution.
  custom_script_command = (local.is_custom_scripts ?
    format("pwsh.exe -ExecutionPolicy Unrestricted -Command \"%s\"",
      join(" && ", formatlist("& '%s'", var.support_vm_config.custom_image.existing_scripts))
    ) : ""
  )
}

# Custom images often contain a set of scripts to execute. Adding them here.
resource "azurerm_virtual_machine_extension" "custom_image_scripts" {

  count = (local.is_custom_scripts) ? 1 : 0

  name                 = "startup-scripts"
  virtual_machine_id   = azurerm_windows_virtual_machine.support_vm[count.index].id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = jsonencode({
    commandToExecute = local.custom_script_command
  })

  // Dependency
  depends_on = [
    azurerm_virtual_machine_extension.vm_aad_join,
  ]
}

# Daily shutdown schedule
resource "azurerm_dev_test_global_vm_shutdown_schedule" "daily_schedule" {

  count = var.support_vm_config.enabled ? 1 : 0

  virtual_machine_id = azurerm_windows_virtual_machine.support_vm[count.index].id
  location           = var.location
  enabled            = true

  daily_recurrence_time = var.support_vm_config.daily_shutdown_time
  timezone              = "India Standard Time"

  notification_settings {
    enabled = false
  }
}
