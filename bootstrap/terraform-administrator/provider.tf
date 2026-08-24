
# Terraform provider block
terraform {

  # Back end configuration
  backend "azurerm" {
  }

  # Terraform itself.
  required_version = ">= 1.10.0"

  # Providers.
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.6.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.32"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.4.0"
    }
  }
}

# Azure RM provider
provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
}

# Default Azure AD provider
provider "azuread" {}

# Azure API provider
provider "azapi" {}

# Get Azure RM Subscription details
data "azurerm_subscription" "primary" {}

# Use outputs from Intermediate proxy-app workspace
data "terraform_remote_state" "proxy_app" {
  backend = "azurerm"
  config  = var.proxy_app_workspace
}

# Aliased Azure AD Provider.
provider "azuread" {
  alias         = "proxy_app"
  client_id     = data.terraform_remote_state.proxy_app.outputs.application_id
  client_secret = data.terraform_remote_state.proxy_app.outputs.client_secret
  tenant_id     = data.terraform_remote_state.proxy_app.outputs.tenant_id
}
