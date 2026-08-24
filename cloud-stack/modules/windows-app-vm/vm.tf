# Is it custom image or platform image
locals {
  custom_image   = (var.app_vm_config.image.custom_image != null) ? 1 : 0
  platform_image = (var.app_vm_config.image.gallery_image != null) ? 1 : 0
  hotpatch       = (local.platform_image == 1) ? (var.app_vm_config.image.gallery_image.hotpatch) : false
}

# Get details about a custom image if it is provided and defined.
data "azurerm_image" "custom_image" {

  # Only enabled if we have a custom image specification.
  count = local.custom_image

  # Image information.
  resource_group_name = var.app_vm_config.image.custom_image.resource_group_name
  name                = var.app_vm_config.image.custom_image.name
}

# Create the App VM.
resource "azurerm_windows_virtual_machine" "app_vm" {

  # Count is to control VM creation, deletion for re-building, than using terraform destroy or delete.
  count = var.app_vm_config.enabled ? 1 : 0

  # Basics
  name                = var.app_vm_config.vm_name
  location            = var.location
  resource_group_name = var.resource_group_name

  # VM Size
  size = var.app_vm_config.vm_size

  # Network Interfaces to link with.
  network_interface_ids = var.app_vm_config.nic_ids

  # Image ID based on specification
  source_image_id = (local.custom_image == 1) ? (data.azurerm_image.custom_image[0].id) : null

  # Or based on platform image specification
  dynamic "source_image_reference" {
    for_each = local.platform_image == 1 ? [1] : []
    content {
      publisher = var.app_vm_config.image.gallery_image.publisher
      offer     = var.app_vm_config.image.gallery_image.offer
      sku       = var.app_vm_config.image.gallery_image.sku
      version   = var.app_vm_config.image.gallery_image.version
    }
  }

  # Hot Patch mode
  hotpatching_enabled   = local.hotpatch
  patch_mode            = (local.hotpatch) ? "AutomaticByPlatform" : "AutomaticByOS"
  patch_assessment_mode = "AutomaticByPlatform"

  # Timezone
  timezone = "India Standard Time"

  # OS Disk
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  # Break Glass credentials
  admin_username = "${var.app_vm_config.vm_name}-admin"
  admin_password = random_password.vm_admin_password.result

  # System Managed VM Identity
  identity {
    type = "UserAssigned"
    identity_ids = [
      var.app_vm_config.war_storage.managed_identity
    ]
  }

  # VM Metadata (tags) used by mount-azure-drive.ps1 via Azure IMDS
  # The script expects these tag names: StorageAccount, ShareName, DriveLetter
  # Values below are dummy placeholders and can be overridden per-environment if needed.
  tags = merge(var.tags, {
    WarStorageAccount  = var.app_vm_config.war_storage.storage_account_name
    WarStorageShare    = var.app_vm_config.war_storage.storage_share_name
    WarStorageFolder   = var.app_vm_config.war_storage.share_folder
    WarStorageDrive    = var.app_vm_config.war_storage.local_drive
    WarStorageKeyVault = var.app_vm_config.war_storage.keyvault_name
    WarStorageKeyName  = var.app_vm_config.war_storage.secret_name
    DataDiskLuns       = join(";", local.drive_lun_array)
  })
}

# Manage Domain Join related resources.
locals {
  domain_join = (var.app_vm_config.enabled && var.app_vm_config.domain_join.should_join_aad) ? 1 : 0
  domain_group = ((local.domain_join == 1) &&
    (var.app_vm_config.domain_join.login_aad_id != null) &&
  (var.app_vm_config.domain_join.login_role_name != null)) ? 1 : 0
}

# Role definition
data "azurerm_role_definition" "vm_administrator_login" {

  # Count is to control VM creation, deletion for re-building
  count = local.domain_group

  name  = var.app_vm_config.domain_join.login_role_name
  scope = azurerm_windows_virtual_machine.app_vm[count.index].id
}

# Assign Role to AAD Group.
resource "azurerm_role_assignment" "builtin_vm_login_assignment" {

  # Count is to control VM creation, deletion for re-building
  count = local.domain_group

  scope              = azurerm_windows_virtual_machine.app_vm[count.index].id
  role_definition_id = data.azurerm_role_definition.vm_administrator_login[count.index].id
  principal_id       = var.app_vm_config.domain_join.login_aad_id
}

# Should Join Domain?
resource "azurerm_virtual_machine_extension" "vm_aad_join" {

  # Count is to control VM creation, deletion for re-building
  count = local.domain_join

  # Other Values
  name                       = "AADLoginForWindows"
  virtual_machine_id         = azurerm_windows_virtual_machine.app_vm[count.index].id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADLoginForWindows"
  type_handler_version       = "2.0"
  auto_upgrade_minor_version = true

  // Dependency
  depends_on = [
    azurerm_virtual_machine_data_disk_attachment.app_vm_data_disks
  ]
}

# For running custom scripts.
locals {
  is_custom_scripts = ((local.custom_image == 1) && (var.app_vm_config.enabled) &&
  (length(var.app_vm_config.image.custom_image.existing_scripts) > 0))

  # Construct the PowerShell command to execute multiple scripts.
  # It joins the scripts using '&&' for sequential execution.
  custom_script_command = (local.is_custom_scripts ?
    format("pwsh.exe -ExecutionPolicy Unrestricted -Command \"%s\"",
      join(" && ", formatlist("& '%s'", var.app_vm_config.image.custom_image.existing_scripts))
    ) : ""
  )
}

# Custom images often contain a set of scripts to execute. Adding them here.
resource "azurerm_virtual_machine_extension" "custom_image_scripts" {

  count = (local.is_custom_scripts) ? 1 : 0

  name                 = "startup-scripts"
  virtual_machine_id   = azurerm_windows_virtual_machine.app_vm[count.index].id
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
