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

# Key Vault Name
variable "keyvault_name" {
  type        = string
  description = "Key Vault Name"
}

# Group name that should have access to break glass Key Vault.
variable "ad_group_name" {
  type = object({
    name = string # Group Name
    id   = string # Object iD
  })
  description = "Group name that should have access to break glass Key Vault."
}
