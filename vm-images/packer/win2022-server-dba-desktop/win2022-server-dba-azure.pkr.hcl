// Only need Azure Builder Plugin.
packer {
  required_plugins {
    // The HashiCorp Azure plugin is named "azure" here, even though the builder type is "azure-arm".
    azure = {
      source  = "github.com/hashicorp/azure"
      version = ">= 1.5.0"
    }
  }
}

// Local values for auto-generated build credentials used by Azure VM admin and WinRM
locals {
  // Username must meet Azure/Windows requirements; keep it simple and unique per build
  build_username = "packer-${substr(uuidv4(), 0, 8)}"

  // Strong password: 8 upper hex chars + 4 hex chars + a fixed complex suffix to satisfy complexity
  // Total length >= 15, includes upper, lower, digit, and special characters
  build_password = "${upper(substr(uuidv4(), 0, 8))}${substr(uuidv4(), 9, 4)}!aA1"

  // Where to drop all the run-time scripts
  provision_path = "C:\\Scripts\\Packer-Provision"
}

// Azure ARM builder.
source "azure-arm" "win2022" {

  // Auth - By default only use Azure CLI Auth.
  use_azure_cli_auth = true
  subscription_id    = var.subscription_id
  tenant_id          = var.tenant_id

  // Size of the VM.
  vm_size = var.vm_size

  // location
  location = var.location

  // Base image
  os_type         = "Windows"
  image_publisher = var.image_publisher
  image_offer     = var.image_offer
  image_sku       = var.image_sku
  image_version   = var.image_version

  // Where the managed image is kept.
  managed_image_name                = var.managed_image_name
  managed_image_resource_group_name = var.resource_group_name

  // WinRM communicator settings
  communicator   = "winrm"
  winrm_use_ssl  = true
  winrm_insecure = true
  winrm_timeout  = "6h"

  // Use auto-generated credentials for the temporary build VM and WinRM connection
  winrm_username = local.build_username
  winrm_password = local.build_password

  // Tags for the easy search.
  azure_tags = {
    purpose         = var.build_purpose
    os              = "windows"
    image_publisher = var.image_publisher
    image_offer     = var.image_offer
    image_sku       = var.image_sku
    image_version   = var.image_version
    // Helper tags to make cleanup simpler during tests
    artifact_type = "managed_image"
    deletable     = "true"
  }
}

// =========================
// Build & Provisioners
// =========================

build {
  name = var.build_name
  // In HCL2, sources must be provided as strings (not HCL references).
  sources = ["source.azure-arm.win2022"]

  # Bootstrap: Upload all common provisioner scripts.
  provisioner "file" {
    source      = "${path.root}/${var.common_scripts_source}"
    destination = local.provision_path
  }

  # Bootstrap: Upload all recipe provisioner scripts.
  provisioner "file" {
    source      = "${path.root}/${var.scripts_source}"
    destination = local.provision_path
  }

  # Run Choco Installer and other related files.
  provisioner "powershell" {
    inline = [
      "Write-Host 'Running choco installer script...'",
      "& '${local.provision_path}/c1-bootstrap-choco-installer.ps1' -ProvisionPath '${local.provision_path}'"
    ]
  }

  # Install Powershell Modules but in newly installed pwsh.exe
  provisioner "powershell" {
    use_pwsh = true
    inline = [
      "Write-Host 'Running powershell modules installer script...'",
      "& '${local.provision_path}/c2-install-powershell-modules.ps1'"
    ]
  }

  # Install automatic package upgrade task
  provisioner "powershell" {
    use_pwsh = true
    inline = [
      "Write-Host 'Installing packagge upgrade task ...'",
      "& '${local.provision_path}/c3-install-package-upgrade-task.ps1'"
    ]
  }

  # Run Windows Server Tweaks
  provisioner "powershell" {
    use_pwsh = true
    inline = [
      "Write-Host 'Running windows server tweaks ...'",
      "& '${local.provision_path}/c4-windows-server-tweaks.ps1'"
    ]
  }

  // Reboot to finalize registration of packages
  provisioner "windows-restart" {
    check_registry = true
  }

  # Sysprep step (MANDATORY: LAST STEP)
  provisioner "powershell" {
    use_pwsh = true
    inline = [
      "Write-Host 'Running Sysprep...'",
      "C:\\Windows\\System32\\Sysprep\\sysprep.exe /oobe /generalize /shutdown /mode:vm"
    ]
    timeout = "20m"
  }
}
