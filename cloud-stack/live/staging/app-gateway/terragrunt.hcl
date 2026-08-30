# Inherit from global environment.
include "env" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

# Source modules for terraform
terraform {
  source = "../../../modules/app-waf"
}

# Direct dependency on networks.
dependency "network" {
  config_path                             = "../network"
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
  mock_outputs = {
    top_level_network = {
      resource_group_name = "mocked-resource-group-name"
      app_subnet_prefixes = {
        "my_den" = ["192.168.2.0/24"]
      }
      waf_subnet = {
        id           = "waf-subnet-id"
        ip           = "1.2.3.4"
        ip_id        = "waf-public-ip-id"
        name_servers = ["a1.azure.net", "a2.azure.net"]
        waf_host     = "waf.az.example.com"
        waf_domain   = "az.example.com"
      }
    }
  }
}

# Dependency on My-Den App
dependency "my_den_app" {
  config_path                             = "../myden-app/tomcat-vm"
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
  mock_outputs = {
    vm_data = {
      ip_addresses = ["192.168.1.1"]
      machine_name = "myden-tomcat"
    }
  }
}

# Dependency on Base
dependency "base" {
  config_path                             = "../base"
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
  mock_outputs = {
    managed_identities = {
      "GitHub-Cert-Rotator" = {
        id                  = "some-mocked-id"
        principal_id        = "some-mocked-principal-id"
        resource_group_name = "rg-staging-base"
      }
    }
  }
}

# Inputs
inputs = {

  # Resource group name
  resource_group = dependency.network.outputs.top_level_network.resource_group_name

  # WAF Settings
  waf_settings = {

    # Firewall Related
    firewall = {
      mode                 = "Prevention"
      max_body_size_kb     = 128
      file_upload_limit_mb = 20
      app_networks         = flatten(values(dependency.network.outputs.top_level_network.app_subnet_prefixes))
      bad_user_agents = [
        "nmap",
        "sqlmap",
        "nikto",
        "acunetix"
      ]
      banned_countries = [
        "RU", # Russia
        "CN", # China
        "IR", # IRAN
        "KP"  # North Korea
      ]
    }
    # Front End part of the WAF.
    front_end = {
      subnet_id     = dependency.network.outputs.top_level_network.waf_subnet.id
      ip_address    = dependency.network.outputs.top_level_network.waf_subnet.ip
      ip_address_id = dependency.network.outputs.top_level_network.waf_subnet.ip_id
      domain_name   = dependency.network.outputs.top_level_network.waf_subnet.waf_domain
      host_name     = dependency.network.outputs.top_level_network.waf_subnet.waf_host
      allow_via_ip  = true
      http_port     = 80
      https_port    = 443
    }

    # WAF Certificate management.
    ssl_certificate = {
      key_vault_name         = "waf-cert-kv-${include.env.locals.environment}"
      secret_name_bootstrap  = "seed-self-certificate"
      secret_name_production = "prod-certificate"
      bootstrap_mode         = false
      mi_rotation = {
        id             = dependency.base.outputs.managed_identities["GitHub-Cert-Rotator"].id
        principal_id   = dependency.base.outputs.managed_identities["GitHub-Cert-Rotator"].principal_id
        resource_group = dependency.base.outputs.managed_identities["GitHub-Cert-Rotator"].resource_group_name
        github_repos = [
          "GRC-Denave/azure-poc:ref:refs/heads/main",
        ]
      }
    }

    # Back end apps of the WAF
    back_end_apps = [
      {
        name         = dependency.my_den_app.outputs.vm_data.machine_name
        ip_addresses = dependency.my_den_app.outputs.vm_data.ip_addresses
        port         = 8080
        health_route = "/docs"
        back_route   = "/myDEN"
        front_route  = "/myDEN"
        dns_cname    = true
      }
    ]
  }

  # Diagnostics Settings
  diagnostics_settings = {
    workspace_name    = "App-Gateway-Log-Analytics"
    sku               = "PerGB2018"
    retention_in_days = 30
  }
}
