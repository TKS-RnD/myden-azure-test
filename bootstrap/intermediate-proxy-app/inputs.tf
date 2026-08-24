# Azure Subscription ID
variable "azure_subscription_id" {
  type        = string
  description = "Subscription ID"
}

# The name of the Intermediate Proxy App
variable "azure_cli_proxy_app-name" {
  type        = string
  description = "The name of the Intermediate Proxy App"
}

# Description for the Intermediate Proxy app
variable "azure_cli_proxy_app_description" {
  type        = string
  description = "Description for the Intermediate Proxy app"
}

# Proxy App Permission list.
variable "azure_cli_proxy_app_permissions" {
  type        = list(string)
  description = "Proxy App Permission list."
}

# Owners of the Proxy App
variable "azure_cli_proxy_app_owners" {
  type        = list(string)
  description = "Proxy App owners"
}
