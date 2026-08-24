## Include only the environment root to satisfy Terragrunt's one-level include rule
include "env" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

# Direct dependency on base.
dependency "base" {
  config_path                             = "../../base"
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
  mock_outputs = {
    resource_groups = {
      support = "rg-staging-support"
      network = "rg-staging-network"
    }
    ad_groups = {
      "Azure Database Administrators" = "some-id"
    }
    managed_identities = {
      "Support Desktop VM" = "some-mocked-id2"
    }
  }
}

# Direct dependency on networks.
dependency "network" {
  config_path                             = "../../network"
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
  mock_outputs = {
    top_level_network = {
      support_subnet = {
        id = "subnet_id"
        nics = [
          "nic-id-1",
        ]
      }
    }
  }
}

# Direct dependencies on break-glass-keyvault
dependency "break_glass" {
  config_path                             = "../../vault-vm-break-glass"
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

# Direct dependencies on log storage
dependency "log_storage" {
  config_path                             = "../log-storage"
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
  mock_outputs = {
    shares = {
      storage_account_name = "sa-account-1"
      resource_group       = "rg-staging-support"
      container_name       = "container-1"
    }
  }
}

# use the windows vm module
terraform {
  source = "../../../../modules/support-vm"
}

# For Tomcat Windows VM
inputs = {

  # Support DBA Resource group to create VM under.
  resource_group_name = dependency.base.outputs.resource_groups["support"]

  # Support VM configuration
  support_vm_config = {

    # Enabled or not
    enabled = false

    # Name of the VM
    vm_name = "support-vm"

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
      ]
    }

    # Log Storage
    log_storage = {
      storage_account_name   = dependency.log_storage.outputs.shares.storage_account_name
      storage_container_name = dependency.log_storage.outputs.shares.container_name
      managed_identity       = dependency.base.outputs.managed_identities["Support Desktop VM"].id
    }

    # domain join information.
    domain_join = {
      should_join_aad = true
      login_aad_id    = dependency.base.outputs.ad_groups["Support Personnel"]
      login_role_name = "Virtual Machine User Login"
    }

    # In which subnet should it be created?
    subnet_id = dependency.network.outputs.top_level_network.support_subnet.id

    # NIC Ids
    nic_ids = dependency.network.outputs.top_level_network.support_subnet.nics

    # Key Vault ID where admin group above can find the password
    break_glass_keyvault_id = dependency.break_glass.outputs.break_glass_keyvault.id

    # Daily shutdown time
    daily_shutdown_time = "1900"
  }
}
