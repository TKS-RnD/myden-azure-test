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
variable "resource_group_names" {
  type = object({
    vault   = string # For the Vault Resource.
    storage = string # For the Storage resource
  })
  description = "Resource Group names to create resources under."
}

# Default Tags
variable "tags" {
  type        = map(string)
  description = "Default Tags"
}

# Storage account name.
variable "storage_account_name" {
  type        = string
  description = "Storage account name to create for keeping WARs"
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
    managed_identity_name = string # Only VMs with this identity will be able to mount it.
    managed_identity_id   = string
    keyvault_name         = string # Key Vault Name
  })
}

# Upload control for storage account
variable "upload_control" {
  type = object({

    # The Key-Vault name
    keyvault_name = string

    # The name of the key to get the SAS token.
    sas_token_key_name = string

    # SAS keys are created with expiry of N years. increment this variable to rotate them.
    rotate_sas_key     = number
    expiry_after_years = number

    # The Managed Identity that is given access in GitHub to access the Key Vault.
    github_managed_identity = object({
      id                  = string
      principal_id        = string
      resource_group_name = string
      client_id           = string
      tenant_id           = string
    })

    # List of Github Repos that can upload WARs.
    github_repos = list(string)

    # The jenkins Managed application that is given access to access the Key Vault.
    jenkins_managed_application = object({
      app_id               = string
      service_principal_id = string
      tenant_id            = string
      credential           = string
    })

    # Other Azure networks from different subscriptions given access.
    azure_third_party_networks = list(object({
      subscription_id = string
      resource_group  = string
      network_name    = string
      subnet_name     = string
    }))
  })
}

# The Log Analytics Workspace name for this storage.
variable "log_analytics_workspace_name" {
  type        = string
  description = "The Log Analytics Workspace name for this storage."
}
