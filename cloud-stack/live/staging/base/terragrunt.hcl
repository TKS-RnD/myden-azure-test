
# Inherit from global environment.
include "env" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

# Source modules for terraform
terraform {
  source = "../../../modules/base"
}

# Inputs to the base module
inputs = {

  # Resource Groups
  resource_groups = [
    {
      name    = "rg-${include.env.locals.environment}-network"
      purpose = "network"
      needed = {
        storage_data_plane_access = false
      }
    },
    {
      name    = "rg-${include.env.locals.environment}-vaults"
      purpose = "vault"
      needed = {
        storage_data_plane_access = false
      }
    },
    {
      name    = "rg-${include.env.locals.environment}-app-vms"
      purpose = "app-vms"
      needed = {
        storage_data_plane_access = true
      }
    },
    {
      name    = "rg-${include.env.locals.environment}-databases"
      purpose = "databases"
      needed = {
        storage_data_plane_access = false
      }
    },
    {
      name    = "rg-${include.env.locals.environment}-dba"
      purpose = "dba"
      needed = {
        storage_data_plane_access = false
      }
    },
    {
      name    = "rg-${include.env.locals.environment}-support"
      purpose = "support"
      needed = {
        storage_data_plane_access = false
      }
    }
  ]

  # AD Groups to create.
  #########################################################
  # IMPORTANT NOTE - ALWAYS ADD GROUPS TO THE BOTTOM.
  #######################################################
  ad_groups = [
    {
      name        = "Azure App VM Administrators"
      description = "Group that can manage Azure App VMs."
      rdp_access  = true
    },
    {
      name        = "Azure Database Administrators"
      description = "Group that has Database Administrative access in Azure."
      rdp_access  = true
    },
    {
      name        = "Break Glass Vault Access"
      description = "Group that has Access to Break Glass Vault."
      rdp_access  = true
    },
    {
      name        = "Support Personnel"
      description = "Group that offers support (log access and DB read access)"
      rdp_access  = true
    }
  ]

  # Managed Identities
  managed_identities = [
    {
      name        = "mi-app-vm-${include.env.locals.environment}"
      mnemonic    = "Application VM"
      description = "Application VMs - Used for Passwordless Login to access resources"
    },
    {
      name        = "mi-github-${include.env.locals.environment}"
      mnemonic    = "GitHub-War-Pusher"
      description = "GitHub Repos used to push WARs into WAR Storage"
    },
    {
      name        = "mi-dba-${include.env.locals.environment}"
      mnemonic    = "DBA Desktop VM"
      description = "DBA Desktop VM - Used by DBA to configure Databases"
    },
    {
      name        = "mi-support-${include.env.locals.environment}"
      mnemonic    = "Support Desktop VM"
      description = "Support Desktop VM - Used by support to run Read queries on DB and access application logs"
    },
    {
      name        = "mi-github-cert-rotator-${include.env.locals.environment}"
      mnemonic    = "GitHub-Cert-Rotator"
      description = "GitHub Repos used to generate WAF SSL Certificates"
    }
  ]

  # Managed applications
  managed_applications = [
    {
      name        = "app-jenkins-war-pusher-${include.env.locals.environment}"
      mnemonic    = "Jenkins-War-Pusher"
      description = "Jenkins Managed Application to push WARs into WAR Storage"
      cert_login  = false
      password    = true
    }
  ]
}
