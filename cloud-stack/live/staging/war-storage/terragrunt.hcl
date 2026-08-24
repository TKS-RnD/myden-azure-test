
# Inherit from global environment.
include "env" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

# Direct dependency on networks
dependency "network" {
  config_path                             = "../network"
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
  mock_outputs = {
    top_level_network = {
      app_subnet_ids = {
        network-a = "mock-id-1"
        network-b = "mock-id-2"
      }
    }
  }
}

# Source modules for terraform
terraform {
  source = "../../../modules/war-storage"
}

# Direct dependency on base.
dependency "base" {
  config_path                             = "../base"
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
  mock_outputs = {
    resource_groups = {
      vault   = "rg-staging-vault"
      app-vms = "rg-staging-app-vms"
    }
    managed_identities = {
      "Application VM" = {
        name         = "mi-app-vm-staging"
        principal_id = "mock-id"
      }
      "GitHub-War-Pusher" = {
        name         = "mi-app-github-staging"
        principal_id = "mock-id-2"
      }
      "Jenkins-War-Pusher" = {
        name         = "mi-jenkins-war-pusher-staging"
        principal_id = "mock-id-2"
      }
    }
  }
}

# Inputs to the WAR Storage module
inputs = {

  # Resource group name
  resource_group_names = {
    vault   = dependency.base.outputs.resource_groups["vault"]
    storage = dependency.base.outputs.resource_groups["app-vms"]
  }

  # Storage account name
  storage_account_name = "denave1war1${include.env.locals.environment}"

  # Size of the storage in Gb
  storage_size_in_gb = 5

  # Log Analytics Workspace name
  log_analytics_workspace_name = "law-war-storage-${include.env.locals.environment}"

  # Network Access Control  for Storage account
  network_access_control = {
    public_ip_mask = [
      "122.172.83.218",
      "74.225.159.123",
      "117.242.38.70"
    ]
    app_subnet_ids = dependency.network.outputs.top_level_network.app_subnet_ids
  }

  # AD Group to manage access to
  mount_share_control = {
    managed_identity_name = dependency.base.outputs.managed_identities["Application VM"].name
    managed_identity_id   = dependency.base.outputs.managed_identities["Application VM"].principal_id
    keyvault_name         = "war-storage-vault"
  }

  # Upload control
  upload_control = {

    # Key Vault where SAS Token can be got.
    keyvault_name      = "war-sas-vault-${include.env.locals.environment}"
    sas_token_key_name = "sas-token"

    # How many times to rotate. Keep incrementing it if rotation is needed.
    rotate_sas_key     = 4
    expiry_after_years = 2

    # The GH Managed identity can upload WARs.
    github_managed_identity = {
      id                  = dependency.base.outputs.managed_identities["GitHub-War-Pusher"].id
      principal_id        = dependency.base.outputs.managed_identities["GitHub-War-Pusher"].principal_id
      resource_group_name = dependency.base.outputs.managed_identities["GitHub-War-Pusher"].resource_group_name
      client_id           = dependency.base.outputs.managed_identities["GitHub-War-Pusher"].client_id
      tenant_id           = dependency.base.outputs.managed_identities["GitHub-War-Pusher"].tenant_id
    }

    # Github Repos that can upload WARs.
    github_repos = [
      "GRC-Denave/test-war:ref:refs/heads/main",
      "GRC-Denave/myden-dev:ref:refs/heads/security-changes"
    ]

    # The Jenkins Managed Application can upload WARs.
    jenkins_managed_application = {
      app_id               = dependency.base.outputs.managed_applications["Jenkins-War-Pusher"].application_id
      service_principal_id = dependency.base.outputs.managed_applications["Jenkins-War-Pusher"].service_principal_id
      tenant_id            = dependency.base.outputs.managed_applications["Jenkins-War-Pusher"].tenant_id
      credential           = dependency.base.outputs.managed_applications["Jenkins-War-Pusher"].password
    }

    # Third Party networks
    azure_third_party_networks = [
      {
        subscription_id = "8ee51430-f894-4a84-9491-6a6a1ab8c94f"
        resource_group  = "central_indiarg"
        network_name    = "Central_India_VNet"
        subnet_name     = "default"
      }
    ]
  }
}
