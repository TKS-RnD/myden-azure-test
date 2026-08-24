# Environment
variable "environment" {
  type        = string
  description = "Environment in which is deployed"
}

# Default Tags
variable "tags" {
  type        = map(string)
  description = "Default Tags"
}

# Location
variable "location" {
  type        = string
  description = "Location"
}

# List of resource groups to create.
variable "resource_groups" {
  type = list(object({
    purpose = string
    name    = string
    needed = object({
      storage_data_plane_access = bool # Do we need storage data plane access at resource group level for runner?
    })
  }))
  description = "Resource Groups to create"
}

# List of security-enabled AD groups to create.
variable "ad_groups" {
  type = list(object({
    description = string
    name        = string
    rdp_access  = bool
  }))
  description = "AD groups for security purposes"
}

# List of Managed Identities and their purpose.
variable "managed_identities" {
  type = list(object({
    mnemonic    = string # Exported as a Map in outputs.
    name        = string # Actual name of the identity.
    description = string # Description of the Identity.
  }))
  description = "Managed Identities to create"
}

# List of Managed applications and the service principals.
variable "managed_applications" {
  type = list(object({
    mnemonic    = string # Exported as a Map in outputs.
    name        = string # Actual name of the Application.
    description = string # Description of the Application.
    cert_login  = bool   # Does it require a Certificate login
    password    = bool   # Is it password login
  }))
}
