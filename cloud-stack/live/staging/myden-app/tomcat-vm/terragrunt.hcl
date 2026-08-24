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
      app-vms = "rg-staging-app-vms"
    }
    managed_identities = {
      "Application VM" = "some-mocked-id"
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
      subnet_nic_map = {
        my_den = ["nic-id-1"]
      }
    }
  }
}

# Direct Dependency on war_storage
dependency "war_storage" {
  config_path                             = "../../war-storage"
  mock_outputs_allowed_terraform_commands = ["plan", "validate"]
  mock_outputs = {
    shares = {
      storage_account_name = "war-storage"
      storage_share_name   = "sts-staging"
      directory_shares = {
        my_den = "my_den"
      }
    }
    keyvault = {
      name        = "secret-key-vault"
      secret_name = "secret-name"
      identity    = "mocked-id"
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

# use the windows vm module
terraform {
  source = "../../../../modules/windows-app-vm"
}

# For Tomcat Windows VM
inputs = {

  # All VM Related will go here.
  resource_group_name = dependency.base.outputs.resource_groups["app-vms"]

  # Application VM
  app_vm_config = {

    # Enabled or not
    enabled = true

    # Name of the VM
    vm_name = "myden-tomcat"

    # Size of the VM
    vm_size = "Standard_D2s_v5"

    # Data disks to attach.
    data_disks = [
      {
        size_in_gb   = 2
        disk_type    = "Standard_LRS"
        drive_letter = "D"
      },
      {
        size_in_gb   = 3
        disk_type    = "Standard_LRS"
        drive_letter = "E"
      },
    ]

    # Storage for pushing WARs (mounted as drive:\ to \\account.domain\share\folder)
    war_storage = {
      storage_account_name = dependency.war_storage.outputs.shares.storage_account_name
      storage_share_name   = dependency.war_storage.outputs.shares.storage_share_name
      share_folder         = dependency.war_storage.outputs.shares.directory_shares["my_den"]
      local_drive          = "Z"
      keyvault_name        = dependency.war_storage.outputs.keyvault.name
      secret_name          = dependency.war_storage.outputs.keyvault.secret_names["for_mounting_vms"]
      managed_identity     = dependency.base.outputs.managed_identities["Application VM"].id
    }

    # Image object
    image = {

      # custom image and the existing scripts to run inside as an extension.
      custom_image = {
        name                = "win2022-tomcat-base"
        location            = "centralindia"
        resource_group_name = "golden-images"
        existing_scripts = [
          "C:\\Scripts\\Packer-Provision\\mount-data-drives.ps1",
          "C:\\Scripts\\Packer-Provision\\tomcat-users-password.ps1"
        ]
      }
      # gallery_image = {
      #   location  = "centralindia"
      #   publisher = "MicrosoftWindowsServer"
      #   offer     = "WindowsServer"
      #   sku       = "2022-datacenter-azure-edition-hotpatch-smalldisk"
      #   version   = "latest"
      #   hotpatch  = true
      # }
    }

    # domain join information.
    domain_join = {
      should_join_aad = true
      login_aad_id    = dependency.base.outputs.ad_groups["Azure App VM Administrators"]
      login_role_name = "Virtual Machine User Login"
    }

    # In which subnet should it be created?
    subnet_id = dependency.network.outputs.top_level_network.app_subnet_ids["my_den"]

    # NIC Ids
    nic_ids = dependency.network.outputs.top_level_network.subnet_nic_map["my_den"]

    # Key Vault ID where admin group above can find the password
    break_glass_keyvault_id = dependency.break_glass.outputs.break_glass_keyvault.id
  }
}
