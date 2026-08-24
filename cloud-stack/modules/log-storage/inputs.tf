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
  description = "Resource Group name."
}

# Default Tags
variable "tags" {
  type        = map(string)
  description = "Default Tags"
}

# Storage account name.
variable "storage_account_name" {
  type        = string
  description = "Storage account name to create for keeping Logs"
}

# Network Access Control  for Storage account
variable "network_access_control" {
  type        = map(string)
  description = "Map of application subnet name to subnet ids"
}

# Managed Identities that need to be given access to the Log Storage for writing.
variable "managed_identities_writer" {
  type        = list(string)
  description = "Managed Identities that need to be given write access"
}

# Managed Identities that need to be given access to the Log Storage for reading.
variable "managed_identities_reader" {
  type        = list(string)
  description = "Managed Identities that need to be given read access"
}

# AD groups that need to be given read access to the log storage.
variable "ad_groups_reader" {
  type        = list(string)
  description = "AD Group that need to be given read access"
}
