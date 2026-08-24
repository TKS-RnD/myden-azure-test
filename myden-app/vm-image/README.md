# Overview
This recipe creates a Base golden image for running MyDEN application server with the following tools:
1. JDK (version is whatever is appropriate).
2. Tomcat (version is whatever is appropriate).

Packer is used for building the golden image.

## Packer Installation
Below are quick, copy‑pasteable ways to install HashiCorp Packer on common desktop OSes.

### Windows (Desktop/Server)
- Using Winget (recommended on Windows 10/11):
  ```powershell
  winget install --id Hashicorp.Packer -e
  ```

### macOS (Intel and Apple Silicon)
- Using Homebrew (recommended):
  ```bash
  brew tap hashicorp/tap
  brew install hashicorp/tap/packer
  ```
  Upgrade later with:
  ```bash
  brew upgrade hashicorp/tap/packer
  ```

### Linux

- Debian/Ubuntu:
  ```bash
  sudo apt-get update && sudo apt-get install -y gnupg software-properties-common curl
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt-get update && sudo apt-get install -y packer
  ```

After installing on any OS, confirm:
```
packer version
```
You should see a semantic version (for example, `1.11.x`). If the command isn’t found, ensure your install directory is on `PATH` and start a new terminal session.

## Azure Login
The user should have the correct permissions to bake the VM Image. At the minimum these are:
a. Access to the Terraform state to store and read state.
b. Full permission to create and delete resources within the given resource group.

```textmate
$ az login
```

And do role elevation if required via the PS scripts.

## Run Packer
Depending upon the environment (Staging or production), the appropriate variable can be used.
```textmate
$ packer init .
$ packer build -var-file=./staging.pkvars.hcl .
```

This will create a pre-baked VM with the following output to the console (Only example):
```textmate
.... LONG TEXT ....
=> Wait completed after 8 minutes 46 seconds

==> Builds finished. The artifacts of successful builds are:
--> win2022-dc-hot-patch-for-myden-app-vm.azure-arm.win2022: Azure.ResourceManagement.VMImage:

OSType: Windows
ManagedImageResourceGroupName: myden-staging
ManagedImageName: win2022-dc-base-myden-base
ManagedImageId: /URL/
ManagedImageLocation: centralindia
```

The golden image is now available to be used as an base image for a VM and can be listed via:
```textmate
$az image list --resource-group myden-staging --output table
HyperVGeneration    Location      Name                        ProvisioningState    ResourceGroup
------------------  ------------  --------------------------  -------------------  ---------------
V2                  centralindia  win2022-dc-base-myden-base  Succeeded            MYDEN-STAGING

```

### Updating Tomcat and JDK versions
The file [tomcat-installer.ps1](../../vm-images/ps-scripts/tomcat-installer.ps1) has the following variables:
```powershell
param(
    [string]$TomcatVersion     = "9.0.89",
    [string]$TomcatServiceName = "Tomcat9",
    [int]   $TomcatPort        = 8080,
    [string]$JavaPackage       = "openjdk17"
)
```
The variables TomcatVersion, TomcatServiceName and JavaPackage are the editable variables to modify or upgrade Tomcat and
JDK versions. Once done, the golden image can be rebuilt via:
```textmate
$ packer build -var-file=./staging.pkvars.hcl -force .
```
