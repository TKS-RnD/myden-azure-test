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

  // Build name
  build_name = "${var.build_name_prefix}-${var.openjdk_version}"

  // Managed Image name.
  managed_image_name = "${var.managed_image_prefix}-${var.openjdk_version}"

  // Build purpose
  build_purpose = "${var.build_purpose_prefix}-${var.openjdk_version}"

  // Username must meet Azure/Windows requirements; keep it simple and unique per build
  build_username = "packer-${substr(uuidv4(), 0, 8)}"

  // Strong password: 8 upper hex chars + 4 hex chars + a fixed complex suffix to satisfy complexity
  // Total length >= 15, includes upper, lower, digit, and special characters
  build_password = "${upper(substr(uuidv4(), 0, 8))}${substr(uuidv4(), 9, 4)}!aA1"

  // Where to drop all the run-time scripts
  provision_path = "C:\\Scripts\\Packer-Provision"

  // Name of the Service
  war_deployer_service = "WarDeployService"
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
  managed_image_name                = local.managed_image_name
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
    purpose         = local.build_purpose
    os              = "windows"
    image_publisher = var.image_publisher
    image_offer     = var.image_offer
    image_sku       = var.image_sku
    image_version   = var.image_version
    // Helper tags to make cleanup simpler during tests
    artifact_type = "managed_image"
    deletable     = "true"
    jdk           = var.openjdk_version
    tomcat        = var.tomcat_version
  }
}

// =========================
// Build & Provisioners
// =========================

build {
  name = local.build_name

  // In HCL2, sources must be provided as strings (not HCL references).
  sources = ["source.azure-arm.win2022"]

  # Bootstrap: Upload all common provisioner scripts.
  provisioner "file" {
    source      = "${path.root}/${var.common_scripts_source}"
    destination = local.provision_path
  }

  # Bootstrap: Upload all provisioner scripts.
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

  // Upload hardened versions of tomcat files
  provisioner "file" {
    source      = "${path.root}/${var.tomcat_source}"
    destination = "${local.provision_path}/Tomcat"
  }

  // Run Tomcat Installer
  provisioner "powershell" {
    use_pwsh = true
    inline = [
      "Write-Host 'Running TOMCAT installer script...'",
      "& '${local.provision_path}/07-tomcat-installer.ps1' -JavaPackage ${var.openjdk_version} -TomcatVersion ${var.tomcat_version}"
    ]
  }

  // WARNING; RESIST TEMPTATION TO GENERATE TOMCAT USER PASSWORD GENERATION IN PACKER.
  // DPAPI DOES NOT WORK IN VM BAKING MODE.

  // Create scheduled task for mounting drive
  provisioner "powershell" {
    use_pwsh = true
    inline = [
      "Write-Host 'Running Scheduled Task for Mounting Drive script...'",
      "& '${local.provision_path}/05-create-mount-war-drive-task.ps1' -ServiceName '${local.war_deployer_service}'"
    ]
  }

  // Install WAR Deploy Service
  provisioner "powershell" {
    use_pwsh = true
    inline = [
      "Write-Host 'Installing WAR Deployer service...'",
      "& '${local.provision_path}/06-install-war-deploy-service.ps1' -ServiceName '${local.war_deployer_service}'"
    ]
  }

  // Do all Windows Server Tweaks.
  provisioner "powershell" {
    use_pwsh = true
    inline = [
      "Write-Host 'Making Windows Server Tweaks...'",
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
  }
}
