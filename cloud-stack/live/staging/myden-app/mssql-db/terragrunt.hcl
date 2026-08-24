## Include only the environment root to satisfy Terragrunt's one-level include rule
include "env" {
  path = find_in_parent_folders("root.hcl")
}

# Direct dependency on base.
dependency "base" {
  config_path                             = "../../base"
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
  mock_outputs = {
    resource_groups = {
      databases = "rg-staging-databases"
    }
    ad_groups = {
      "Azure Database Administrators" = "some-id-2"
    }
  }
}

# Direct dependency on networks.
dependency "network" {
  config_path                             = "../../network"
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
  mock_outputs = {
    top_level_network = {
      app_subnet_ids = {
        my_den = "mock-id-1"
      }
    }
  }
}

# use the windows vm module
terraform {
  source = "../../../../modules/mssql-serverless"
}

# For creating a mssql database.
inputs = {

  # Resource group name
  resource_group_name = dependency.base.outputs.resource_groups["databases"]

  # Server configuration
  server_configuration = {

    # name
    name = "my-den-mssql-server"

    # version
    version = "12.0"

    # Break glass user
    break_glass_admin_user = "myden-app-mssql-server"

    # Azure AD access
    admin_aad_group = {
      name = "Azure Database Administrators"
      id   = dependency.base.outputs.ad_groups["Azure Database Administrators"]
    }

    # Allow portal access
    portal_internal_access = true

    # Allowed IP Addresses - For now every IP Address.
    allowed_prefixes = []

    # Allowed Virtual Networks.
    allowed_vnets = [
      dependency.network.outputs.top_level_network.app_subnet_ids["my_den"]
    ]

    # Databases
    databases = [
      {
        name                      = "myden"
        collation                 = "SQL_Latin1_General_CP1_CI_AS"
        gb_size                   = 10
        short_term_retention_days = 15
        long_term_weekly_backups  = 0 # How many long term weekly backups should be kept?
      }
    ]
  }
}
