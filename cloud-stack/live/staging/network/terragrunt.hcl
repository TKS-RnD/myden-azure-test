
# Inherit from global environment.
include "env" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

# Source modules for terraform
terraform {
  source = "../../../modules/network"
}

# Direct dependency on base.
dependency "base" {
  config_path                             = "../base"
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
  mock_outputs = {
    resource_groups = {
      network = "rg-staging-network"
    }
    ad_groups_rdp_access = {
      "Group 1" = "object-id-1"
      "Group 2" = "object-id-2"
    }
  }
}

# Inputs to the networking module
inputs = {

  # Network Configuration
  top_level_network = {
    name                = "Root-Network-${include.env.locals.environment}"
    subnet_mask         = "192.168.0.0/16"
    resource_group_name = dependency.base.outputs.resource_groups["network"]
    location            = include.env.locals.location
  }

  # Bastion host
  bastion_host_in_network = {
    subnet_mask = "192.168.1.0/24"
    enabled     = true
    ad_groups   = dependency.base.outputs.ad_groups_rdp_access
  }

  # Application subnets
  application_subnets = {

    # My DEN App subnet.
    my_den = {
      subnet_mask            = "192.168.2.0/24"
      nic_count              = 1
      reachable_from_bastion = true
      reachable_from_waf     = true
      services_attached = [
        "Microsoft.Storage",
        "Microsoft.KeyVault",
        "Microsoft.Sql"
      ]
    }
  }

  # WAF Subnet
  waf_subnet = {
    subnet_name = "waf"
    subnet_mask = "192.168.251.0/24"
    domain_name = "az-${include.env.locals.environment}.denuds.com"
    host_name   = "waf"
  }

  # Database Administrator Subnet
  dba_subnet = {
    name                   = "dba"
    subnet_mask            = "192.168.252.0/24"
    nic_count              = 1
    reachable_from_bastion = true
    services_attached = [
      "Microsoft.Storage",
      "Microsoft.KeyVault",
      "Microsoft.Sql"
    ]
  }

  # Support Personnel Subnet
  support_subnet = {
    name                      = "support"
    subnet_mask               = "192.168.253.0/24"
    nic_count                 = 1
    reachable_from_bastion    = true
    reachable_from_app_subnet = false
    reachable_from_dba_subnet = false
    services_attached = [
      "Microsoft.Storage",
      "Microsoft.KeyVault",
      "Microsoft.Sql"
    ]
  }

}
