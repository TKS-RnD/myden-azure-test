
# Inherit from global environment.
include "env" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

# Direct dependency on networks
dependency "network" {
  config_path                             = "../../network"
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
  mock_outputs = {
    top_level_network = {
      app_subnet_ids = {
        network-a = "mock-id-1"
        network-b = "mock-id-2"
      }
      support_subnet = {
        id = "mock-support-subnet-id"
      }
    }
  }
}

# Direct dependency on base.
dependency "base" {
  config_path                             = "../../base"
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
  mock_outputs = {
    ad_groups = {
      "Support Personnel" = "mocked-id"
    }
    resource_groups = {
      support = "rg-staging-support"
    }
    managed_identities = {
      "Application VM" = {
        name         = "mi-app-vm-staging"
        principal_id = "mock-id"
      }
      "Support Desktop VM" = {
        name         = "mi-support-staging"
        principal_id = "mock-id2"
      }
    }
  }
}

# Source modules for terraform
terraform {
  source = "../../../../modules/log-storage"
}

# Inputs to the WAR Storage module
inputs = {

  # Resource group name
  resource_group_name = dependency.base.outputs.resource_groups["support"]

  # Storage account name
  storage_account_name = "denave1support1${include.env.locals.environment}"

  # Network Access Control  for Storage account, which are the ones that will have access to it
  network_access_control = merge(dependency.network.outputs.top_level_network.app_subnet_ids,
  { support = dependency.network.outputs.top_level_network.support_subnet.id })

  # Managed identities writer.
  managed_identities_writer = [
    dependency.base.outputs.managed_identities["Application VM"].principal_id
  ]

  # Managed identities reader.
  managed_identities_reader = [
    dependency.base.outputs.managed_identities["Support Desktop VM"].principal_id
  ]

  # AD groups reader.
  ad_groups_reader = [
    dependency.base.outputs.ad_groups["Support Personnel"]
  ]
}
