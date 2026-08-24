
# Manage Data disks
resource "azurerm_managed_disk" "app_vm_data_disks" {

  count = length(var.app_vm_config.data_disks)

  location            = var.location
  resource_group_name = var.resource_group_name

  storage_account_type = var.app_vm_config.data_disks[count.index].disk_type
  name                 = "${var.app_vm_config.vm_name}-disk-${count.index}"

  # Depends on if source id is present?
  create_option      = (var.app_vm_config.data_disks[count.index].source_id == null) ? "Empty" : "Copy"
  source_resource_id = var.app_vm_config.data_disks[count.index].source_id

  # Disk size
  disk_size_gb = var.app_vm_config.data_disks[count.index].size_in_gb

  # Add tags in the drive letter so that scripts can mount it
  tags = merge(var.tags, {
    DriveLetter = var.app_vm_config.data_disks[count.index].drive_letter
  })
}

# Create LUN to Disk Drive mapping and Tag to pass.
locals {
  drive_to_lun = {
    for index, drive in var.app_vm_config.data_disks[*].drive_letter :
    "${drive}" => tostring(index + 10)
  }
  drive_lun_array = [
    for k, v in local.drive_to_lun : "${v}:${k}"
  ]
}

# Add disks to VM.
resource "azurerm_virtual_machine_data_disk_attachment" "app_vm_data_disks" {

  count = (var.app_vm_config.enabled) ? (length(var.app_vm_config.data_disks)) : 0

  managed_disk_id    = azurerm_managed_disk.app_vm_data_disks[count.index].id
  virtual_machine_id = azurerm_windows_virtual_machine.app_vm[0].id
  lun                = local.drive_to_lun[var.app_vm_config.data_disks[count.index].drive_letter]

  caching = "ReadWrite"
}
