# Azure Subscription ID
azure_subscription_id = "d32407a7-5c5f-4491-ad3a-f2731fec7b4d"

# Terraform user group built-in roles.
terraform-builtin-roles-users = {
  "Attribute Assignment Administrator" = [
    "anand.v@Denave064.onmicrosoft.com"
  ],
  "User Administrator" = [
    "anand.v@Denave064.onmicrosoft.com"
  ],
  "SharePoint Administrator" = [
    "anand.v@Denave064.onmicrosoft.com"
  ]
}

# Proxy App workspace
proxy_app_workspace = {
  resource_group_name  = "rg-tfstate"
  storage_account_name = "tfstate7shrl"
  container_name       = "tfstate"
  key                  = "bootstrap/intermediate-proxy-app"
}

# Users
terraform-admin-group-eligible-users = [
  "anand.v@Denave064.onmicrosoft.com"
]

# Owner access to be given to these resource group names
resource_groups_owner_access = [
  "myden-staging"
]
