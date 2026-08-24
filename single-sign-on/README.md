# Overview
This terraform recipe creates a single sign-on infrastructure in Azure AD and hooks it up with Azure AD so that when
someone wants to access a GCP project, they can do so via Azure Login and not end up creating a new username manually
in GCP console.

### Pre-requisites
The following tools needs to be installed on the host before the recipe can be run:
1. Azure CLI tool (see instructions on [bootstrap README](../bootstrap/README.md) on how to install it.
2. Google Cloud CLI as below:

##### Linux
**Google Cloud CLI**:
Install Google Cloud CLI by running:
 ```textmate
 sudo apt install google-cloud-cli
 ```
#### MacOS
**Google Cloud CLI**:

Install Google Cloud CLI by running:
```textmate
brew install --cask google-cloud-sdk
```
#### Windows
**Google Cloud CLI**:

Install Google Cloud CLI by running:
```powershell
winget install -e --id Google.CloudSDK
```

#### Login to Google Cloud
Assuming that there is a Google Cloud account for staging environment, the first step is to login:
```textmate
$ gcloud auth application-default login

    Your browser has been opened to visit:

    https://accounts.google.com/o/oauth2/auth?<long-url>

Opening in existing browser session.

You are now logged in as [user@domain].
```

### Login to Azure AD As Terraform administrator
1. Login to your normal user account via 'az login'
2. Then elevate your permission to that of Terraform administrator by running the script activate-pim-group.ps1.
3. Run the standard terraform 2 liner
```terraform
$terraform init -backend-config=azurerm.staging.tfbackend -var-file=staging.tfvars
$terraform apply -var-file=staging.tfvars
gcp_workforce_login_link = "https://auth.cloud.google/signin/locations/global/workforcePools/all-users/providers/azure-ad-global-provider?continueUrl=https://console.cloud.google/"
```

The link can be used to login to GCP via Azure AD Single-Sign on.

## TODO
The exact set of use cases and customization required for SSO for Denave is still not fully scoped out and defined and
hence this recipe may change slightly.
