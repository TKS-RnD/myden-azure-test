# Environment-level configuration for staging

# Local variables, including versions read from parent (cloud-stack/live/root.hcl)
locals {
  parent                = read_terragrunt_config(find_in_parent_folders("stack-globals.hcl"))
  environment           = "staging"
  location              = "centralindia"
  azure_subscription_id = "d32407a7-5c5f-4491-ad3a-f2731fec7b4d"
  default_tags = {
    environment       = local.environment
    owner             = "IT Team"
    terraform-managed = "true"
  }
}

# Generate provider versions from the centralized map
generate "versions" {
  path      = "provider_versions.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = "${local.parent.locals.provider_versions.terraform}"

  # Ensure Terraform recognizes the backend so Terragrunt's -backend-config applies
  backend "azurerm" {}

  required_providers {
    azurerm = {
      source  = "${local.parent.locals.provider_versions.azurerm.source}"
      version = "${local.parent.locals.provider_versions.azurerm.version}"
    }
    random = {
      source  = "${local.parent.locals.provider_versions.random.source}"
      version = "${local.parent.locals.provider_versions.random.version}"
    }
    azuread = {
      source  = "${local.parent.locals.provider_versions.azuread.source}"
      version = "${local.parent.locals.provider_versions.azuread.version}"
    }
    time = {
      source  = "${local.parent.locals.provider_versions.time.source}"
      version = "${local.parent.locals.provider_versions.time.version}"
    }
    tls = {
      source  =  "${local.parent.locals.provider_versions.tls.source}"
      version =  "${local.parent.locals.provider_versions.tls.version}"
    }
 }
}
EOF
}

# Global Remote state to the environment. Child Units can derive directly from it.
remote_state {
  backend = "azurerm"
  config = {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "tfstate7shrl"
    container_name       = "tfstate"
    key                  = "${path_relative_to_include()}/terraform.tfstate"
  }
}

# Generate provider block INCLUDING subscription ID
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "azurerm" {
  features {
    key_vault {
      # This ensures if you delete the KV, it's purged (good for testing, disable for prod)
      purge_soft_delete_on_destroy = true
    }
  }

  # when blob storage creation is required, don't use access keys but Azure AD
  storage_use_azuread = true

  # Subscription ID
  subscription_id = "${local.azure_subscription_id}"
}
EOF
}

# Common inputs for all Child Units
inputs = {
  environment = local.environment
  location    = local.location
  tags        = local.default_tags
}
