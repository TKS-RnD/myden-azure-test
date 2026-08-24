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

# Storage account name.
variable "storage_account_name" {
  type        = string
  description = "Storage account name to create for VMs data folders."
}

# Size of the storage in Gb
variable "storage_size_in_gb" {
  type        = number
  description = "Size of the storage in GB"
}

# Network Access Control  for Storage account
variable "network_access_control" {
  type = object({
    public_ip_mask = list(string) # List of allowed public IP blocks
    app_subnet_ids = map(string)  # Map of application subnet name => subnet ids
  })
}

# Mount control for storage account.
variable "mount_share_control" {
  type = object({
    managed_identity_name = string # Only VMs with this identity will work.
    keyvault_name         = string # Key Vault Name
  })
}
