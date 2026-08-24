# Environment
variable "environment" {
  type        = string
  description = "Environment in which is deployed"
}

# Location
variable "location" {
  type        = string
  description = "Location"
}

# Resource Group name.
variable "resource_group_name" {
  type        = string
  description = "Resource Group name to create resources under."
}

# Default Tags
variable "tags" {
  type        = map(string)
  description = "Default Tags"
}

# Application VM's additional configurations.
variable "app_vm_config" {

  type = object({

    # Is the VM Enabled and running?
    enabled = bool

    # Name of the VM
    vm_name = string

    # Size of the VM
    vm_size = string

    # Data disks to attach.
    data_disks = list(object({
      size_in_gb   = number
      drive_letter = string           # D:, E:, F:
      disk_type    = string           # (e.g) Standard_LRS, Premium_LRS..
      source_id    = optional(string) # Source URI if present.
    }))

    # Storage for pushing WARs (mounted as drive:\ to \\account.domain\share\folder)
    war_storage = object({
      storage_account_name = string
      storage_share_name   = string
      share_folder         = string
      local_drive          = string
      keyvault_name        = string
      secret_name          = string
      managed_identity     = string
    })

    # Image object
    image = object({

      # custom image and the existing scripts to run inside as an extension.
      custom_image = optional(object({
        name                = string
        location            = string
        resource_group_name = string
        existing_scripts    = list(string)
      }))
      gallery_image = optional(object({
        location  = string
        publisher = string
        offer     = string
        sku       = string
        version   = string
        hotpatch  = bool
      }))
    })

    # Domain joining related.
    domain_join = object({
      should_join_aad = bool   # Should it join AAD Entra domain?
      login_aad_id    = string # Which AAD group should have login privileges?
      login_role_name = string # What role should be given to this group?
    })

    # In which subnet?
    subnet_id = string

    # And list of NICs to attach to.
    nic_ids = list(string)

    # Key Vault ID where admin group above can find the password
    break_glass_keyvault_id = string
  })


  validation {
    condition = (
      (var.app_vm_config.image.custom_image != null) != (var.app_vm_config.image.gallery_image != null)
    )
    error_message = "Exactly one of image.custom_image or image.gallery_image must be provided (mutually exclusive)."
  }
}
