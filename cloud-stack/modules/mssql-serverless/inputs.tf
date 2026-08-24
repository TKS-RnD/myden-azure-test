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

# Default Tags
variable "tags" {
  type        = map(string)
  description = "Default Tags"
}

# Resource group name
variable "resource_group_name" {
  type        = string
  description = "Resource group name"
}

# Server Configuration
variable "server_configuration" {
  type = object({

    # Name
    name = string

    # Version
    version = string

    # Break glass administrative user name.
    break_glass_admin_user = string

    # Administrative Group which can access the Serverless service.
    admin_aad_group = object({
      name = string
      id   = string
    })

    # Should allow portal and internal services?
    portal_internal_access = bool

    # Allowed external ip/prefixes.
    allowed_prefixes = list(string)

    # Allowed Virtual Networks. Just their IDs.
    allowed_vnets = list(string)

    # Databases to create
    databases = list(object({
      name                      = string
      collation                 = string
      gb_size                   = number
      short_term_retention_days = number
      long_term_weekly_backups  = number # How many long term weekly backups should be kept? 0 disables auto-pause.
    }))
  })
}
