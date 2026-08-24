
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
      version = "~> 3.4.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.32"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.4.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 7.9"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }
}

# Azure RM provider
provider "azurerm" {

  # Use Azure CLI
  use_cli = true

  # Subscription ID
  subscription_id = var.azure_subscription_id

  # Enabled Features.
  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
    key_vault {
      purge_soft_deleted_certificates_on_destroy = true
      recover_soft_deleted_certificates          = true
    }
  }

}

# Azure AD provider
provider "azuread" {}

# Azure API provider
provider "azapi" {}

# Google Provider
provider "google" {}

# Client Configuration for Azure AD
data "azuread_client_config" "current" {}

# Azure RM Subscription
data "azurerm_subscription" "current" {}

# GCP Organization name
data "google_organization" "current" {
  domain = var.gcp_domain_name
}

# well known apps
data "azuread_application_published_app_ids" "well_known" {}
