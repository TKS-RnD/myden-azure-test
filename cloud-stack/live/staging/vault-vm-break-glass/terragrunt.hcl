
# Inherit from global environment.
include "env" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

# Source modules for terraform
terraform {
  source = "../../../modules/vault-vm-break-glass"
}

# Direct dependency on base.
dependency "base" {
  config_path                             = "../base"
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
  mock_outputs = {
    resource_groups = {
      vault = "rg-staging-vault"
    }
    ad_groups = {
      "${local.ad_group_name}" = "some-id"
    }
  }
}

# Group which has access to the Vault.
locals {
  ad_group_name = "Azure App VM Administrators"
}

# Inputs to the VM Break glass module
inputs = {

  # Resource group name
  resource_group_name = dependency.base.outputs.resource_groups["vault"]

  # Key Vault Name
  keyvault_name = "break-glass-vms-${include.env.locals.environment}"

  # Group name that should have access to break glass Key Vault.
  ad_group_name = {
    name = local.ad_group_name
    id   = dependency.base.outputs.ad_groups[local.ad_group_name]
  }
}
