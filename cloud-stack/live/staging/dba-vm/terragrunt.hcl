## Include only the environment root to satisfy Terragrunt's one-level include rule
include "env" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

# Direct dependency on base.
dependency "base" {
  config_path                             = "../base"
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
  mock_outputs = {
    resource_groups = {
      dba     = "rg-staging-dba"
      network = "rg-staging-network"
      vault   = "rg-staging-vault"
      app-vms = "rg-staging-app-vms"
    }
    ad_groups = {
      "Azure Database Administrators" = "some-id"
    }
    managed_identities = {
      "Application VM" = "some-mocked-id1"
      "DBA Desktop VM" = "some-mocked-id2"
    }
  }
}

# Direct dependency on networks.
dependency "network" {
  config_path                             = "../network"
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
  mock_outputs = {
    top_level_network = {
      dba_subnet = {
        id = "subnet_id"
        nics = [
          "nic-id-1",
          "nic-id-2"
        ]
      }
    }
  }
}

# Direct dependencies on break-glass-keyvault
dependency "break_glass" {
  config_path                             = "../vault-vm-break-glass"
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
  mock_outputs = {
    break_glass_keyvault = {
      name                  = "some-key-vault"
      resource_group_name   = "some-resource-group"
      location              = "centralindia"
      id                    = "mocked-id"
      ad_admin_group_access = "vm-administrators"
    }
  }
}

# use the windows vm module
terraform {
  source = "../../../modules/dba-access-vm"
}

# For Tomcat Windows VM
inputs = {

  # DBA Resource group to create VM under.
  resource_group_name = dependency.base.outputs.resource_groups["dba"]

  # DBA Storage workspace. This will be created.
  storage_workspace = {
    storage_account_name = "denave1dba1${include.env.locals.environment}"
    resource_group_name  = dependency.base.outputs.resource_groups["dba"]
    location             = include.env.locals.location
    blob_name            = "dba-workspace"
    delete_after_days    = 30
  }

  # DBA Keyvault. This will be created.
  dba_keyvault = {
    name                     = "denave1-dba-kv-${include.env.locals.environment}"
    resource_group_name      = dependency.base.outputs.resource_groups["vault"]
    location                 = include.env.locals.location
    write_access_ad_group_id = dependency.base.outputs.ad_groups["Azure Database Administrators"]
  }

  # Managed Identities to assign.
  identities = {
    app_vm = {
      id           = dependency.base.outputs.managed_identities["Application VM"].id
      principal_id = dependency.base.outputs.managed_identities["Application VM"].principal_id
    }
    dba_vm = {
      id           = dependency.base.outputs.managed_identities["DBA Desktop VM"].id
      principal_id = dependency.base.outputs.managed_identities["DBA Desktop VM"].principal_id
    }
  }

  # DBA VM configuration
  dba_vm_config = {

    # Enabled or not
    enabled = true

    # Name of the VM
    vm_name = "dba-desktop-vm"

    # Size of the VM
    vm_size = "Standard_D2s_v5"

    # Data disks to attach.
    data_disks = [
      {
        size_in_gb   = 5
        disk_type    = "Standard_LRS"
        drive_letter = "D"
      }
    ]

    # custom image and the existing scripts to run inside as an extension.
    custom_image = {
      name                = "win2022-server-dba-desktop"
      location            = "centralindia"
      resource_group_name = "golden-images"
      existing_scripts = [
        "C:\\Scripts\\Packer-Provision\\c-mount-data-drives.ps1",
        "C:\\Scripts\\Packer-Provision\\first-boot-dba-tweaks.ps1"
      ]
    }

    # domain join information.
    domain_join = {
      should_join_aad = true
      login_aad_id    = dependency.base.outputs.ad_groups["Azure Database Administrators"]
      login_role_name = "Virtual Machine User Login"
    }

    # In which subnet should it be created?
    subnet_id = dependency.network.outputs.top_level_network.dba_subnet.id

    # NIC Ids
    nic_ids = dependency.network.outputs.top_level_network.dba_subnet.nics

    # Key Vault ID where admin group above can find the password
    break_glass_keyvault_id = dependency.break_glass.outputs.break_glass_keyvault.id

    # Daily shutdown time
    daily_shutdown_time = "1900"
  }
}
