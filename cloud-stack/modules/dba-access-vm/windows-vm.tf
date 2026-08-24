# Random password for the Break Glass Administrator account.
resource "random_password" "dba_vm_admin_password" {
  length      = 15
  min_special = 2
  min_numeric = 2
  min_lower   = 1
  min_upper   = 1
}

# Store the Break glass password in key vault
resource "azurerm_key_vault_secret" "vm_break_glass_password" {
  key_vault_id = var.dba_vm_config.break_glass_keyvault_id
  name         = "${var.dba_vm_config.vm_name}-admin-password"
  value        = random_password.dba_vm_admin_password.result
  tags         = var.tags
}

# Get details about a custom image
data "azurerm_image" "custom_image" {

  # Image information.
  resource_group_name = var.dba_vm_config.custom_image.resource_group_name
  name                = var.dba_vm_config.custom_image.name
}

# Create the DBA VM.
resource "azurerm_windows_virtual_machine" "dba_vm" {

  # Count is to control VM creation, deletion for re-building, than using terraform destroy or delete.
  count = var.dba_vm_config.enabled ? 1 : 0

  # Basics
  name                = var.dba_vm_config.vm_name
  location            = var.location
  resource_group_name = var.resource_group_name

  # VM Size
  size = var.dba_vm_config.vm_size

  # Network Interfaces to link with.
  network_interface_ids = var.dba_vm_config.nic_ids

  # Image ID based on specification
  source_image_id = data.azurerm_image.custom_image.id

  # Patch mode
  patch_mode = "AutomaticByOS"

  # Timezone
  timezone = "India Standard Time"

  # OS Disk
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  # Break Glass credentials
  admin_username = "${var.dba_vm_config.vm_name}-admin"
  admin_password = random_password.dba_vm_admin_password.result

  # System Managed VM Identity
  identity {
    type = "UserAssigned"
    identity_ids = [
      var.identities.dba_vm.id
    ]
  }

  # VM Metadata (tags) used by mount-azure-drive.ps1 via Azure IMDS
  # The script expects these tag names: StorageAccount, ShareName, DriveLetter
  # Values below are dummy placeholders and can be overridden per-environment if needed.
  tags = merge(var.tags, {
    DbaBlobUrl          = local.blob_storage_url
    DbaKeyVault         = var.dba_keyvault.name
    DataDiskLuns        = join(";", local.drive_lun_array)
    Auto-Power-Off-On   = "true"
    Idle-Duration-Hours = "4"
  })
}

# Manage Domain Join related resources.
locals {
  domain_join = (var.dba_vm_config.enabled && var.dba_vm_config.domain_join.should_join_aad) ? 1 : 0
}



# Should Join Domain?
resource "azurerm_virtual_machine_extension" "vm_aad_join" {

  # Count is to control VM creation, deletion for re-building
  count = local.domain_join

  # Other Values
  name                       = "AADLoginForWindows"
  virtual_machine_id         = azurerm_windows_virtual_machine.dba_vm[count.index].id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADLoginForWindows"
  type_handler_version       = "2.0"
  auto_upgrade_minor_version = true

  // Dependency
  depends_on = [
    azurerm_virtual_machine_data_disk_attachment.dba_vm_data_disks
  ]
}

# For running custom scripts.
locals {
  is_custom_scripts = (var.dba_vm_config.enabled) && (length(var.dba_vm_config.custom_image.existing_scripts) > 0)

  # Construct the PowerShell command to execute multiple scripts.
  # It joins the scripts using '&&' for sequential execution.
  custom_script_command = (local.is_custom_scripts ?
    format("pwsh.exe -ExecutionPolicy Unrestricted -Command \"%s\"",
      join(" && ", formatlist("& '%s'", var.dba_vm_config.custom_image.existing_scripts))
    ) : ""
  )
}

# Custom images often contain a set of scripts to execute. Adding them here.
resource "azurerm_virtual_machine_extension" "custom_image_scripts" {

  count = (local.is_custom_scripts) ? 1 : 0

  name                 = "startup-scripts"
  virtual_machine_id   = azurerm_windows_virtual_machine.dba_vm[count.index].id
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

# Allow the VM to see the storage account and the blob storage.
# This is required for various CLI commands in ARM layer.
resource "azurerm_role_assignment" "dba_vm_storage_reader" {
  scope                = azurerm_storage_account.dba_workspace.id
  role_definition_name = "Reader"
  principal_id         = var.identities.dba_vm.principal_id
}

# Allow the dba VM to write/read backups (AD groups)
resource "azurerm_role_assignment" "dba_vm_storage_access" {
  scope                = azurerm_storage_account.dba_workspace.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = var.identities.dba_vm.principal_id
}

# Daily shutdown schedule
resource "azurerm_dev_test_global_vm_shutdown_schedule" "daily_schedule" {

  count = var.dba_vm_config.enabled ? 1 : 0

  virtual_machine_id = azurerm_windows_virtual_machine.dba_vm[count.index].id
  location           = var.location
  enabled            = true

  daily_recurrence_time = var.dba_vm_config.daily_shutdown_time
  timezone              = "India Standard Time"

  notification_settings {
    enabled = false
  }
}
