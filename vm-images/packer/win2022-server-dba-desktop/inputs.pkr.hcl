# -------------------------------------------- Variables that change across environment ------------------------- ###

# Subscription ID.
variable "subscription_id" {
  type        = string
  description = "Azure subscription ID"
}

# Tenant ID
variable "tenant_id" {
  type        = string
  description = "Azure tenant ID"
}

// Resource group to publish the Managed Image into
variable "resource_group_name" {
  type        = string
  description = "Resource Group where the managed image will be stored."
}

# -------------------------------------------- Variables with default values ------------------------- ###

# location
variable "location" {
  type        = string
  description = "Azure region to build the image in."
  default     = "centralindia"
}


// Base image selection - It is always Windows Server by Microsoft. We can list all the Microsoft Publishers via
// az vm image list-publishers -l centralindia --output table | grep -i Windows
variable "image_publisher" {
  type        = string
  description = "Base image publisher"
  default     = "MicrosoftWindowsServer"
}

// List of Images published by the publisher. We can list the images via
// az vm image list-offers --location centralindia --publisher MicrosoftWindowsServer --output table
variable "image_offer" {
  type        = string
  description = "Base image offer"
  default     = "WindowsServer"
}

// The specific SKU - We chose hotpatch variant because of it's unique managed feature.
// List of all SKUs can be seen via
// az vm image list-skus --location centralindia --publisher MicrosoftWindowsServer --offer WindowsServer --output table
variable "image_sku" {
  type        = string
  description = "Base image SKU (e.g., 2022-datacenter-g2)."
  default     = "2022-datacenter-azure-edition-hotpatch-smalldisk"
}

# Always the latest image version.
variable "image_version" {
  type        = string
  description = "Base image version"
  default     = "latest"
}

# The Size of the VM used for building.
variable "vm_size" {
  type        = string
  description = "Temporary build VM size"
  default     = "Standard_D2s_v5"
}

# The Name of the Stored Image.
variable "managed_image_name" {
  type        = string
  description = "Name of the resulting managed image"
  default     = "win2022-server-dba-desktop"
}

# Source path for common powershell scripts
variable "common_scripts_source" {
  type        = string
  description = "Local path to the directory containing common powershell scripts"
  default     = "../../ps-scripts/common/"
}

# Source path for powershell scripts
variable "scripts_source" {
  type        = string
  description = "Local path to the directory containing powershell scripts"
  default     = "../../ps-scripts/win2022-server-dba-desktop/"
}

# Build name for the Packer execution
variable "build_name" {
  type        = string
  description = "The name of the Packer build"
  default     = "win2022-server-dba-desktop"
}

# Purpose tag for Azure resources
variable "build_purpose" {
  type        = string
  description = "The purpose tag for the Azure resources created during the build"
  default     = "packer-build-for-windows-dba-desktop"
}
