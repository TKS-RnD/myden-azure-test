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

# DBA Storage Area
variable "storage_workspace" {
  type = object({
    storage_account_name = string
    resource_group_name  = string
    location             = string
    blob_name            = string
    delete_after_days    = number
  })
  description = "DBA Storage Area"
}

# DBA Keyvault - only App VM and Machines have access to this.
variable "dba_keyvault" {
  type = object({
    name                     = string
    resource_group_name      = string
    location                 = string
    write_access_ad_group_id = string
  })
  description = "DBA Key Vault"
}

# Managed Identities
variable "identities" {
  type = object({
    app_vm = object({
      id           = string
      principal_id = string
    })
    dba_vm = object({
      id           = string
      principal_id = string
    })
  })
  description = "Managed Identities for various reasons."
}

# DBA VM additional configurations.
variable "dba_vm_config" {

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

    # custom image and the existing scripts to run inside as an extension.
    custom_image = object({
      name                = string
      location            = string
      resource_group_name = string
      existing_scripts    = list(string)
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

    # Daily shutdown schedule.
    daily_shutdown_time = string
  })

}
