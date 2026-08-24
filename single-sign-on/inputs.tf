# Azure Subscription ID
variable "azure_subscription_id" {
  type        = string
  description = "Subscription ID"
}

# GCP Organization domain name.
variable "gcp_domain_name" {
  type        = string
  description = "GCP Account's domain name"
}

# GCP Pool ID
variable "gcp_pool_id" {
  type        = string
  description = "Workforce Pool ID"
}

# GCP Provider ID
variable "gcp_provider_id" {
  type        = string
  description = "Workforce Provider ID"
}

# Azure AD App's API Permissions.
variable "azure_ad_app_default_scopes" {
  type        = list(string)
  description = "Default API Permissions"
}
