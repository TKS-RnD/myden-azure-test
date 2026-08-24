# Azure Subscription ID
azure_subscription_id = "9ccb8868-af6b-4944-8ff4-ad802d53370b"

# Terraform user group built-in roles.
terraform-builtin-roles-users = {
  "Attribute Assignment Administrator" = [
    "rahul.raina@Denave064.onmicrosoft.com"
  ],
  "User Administrator" = [
    "rahul.raina@Denave064.onmicrosoft.com"
  ],
  "SharePoint Administrator" = [
    "rahul.raina@Denave064.onmicrosoft.com"
  ]
}

# Proxy App workspace
proxy_app_workspace = {
  resource_group_name  = "rg-terraformuat"
  storage_account_name = "terraform101uat"
  container_name       = "terraform101"
  key                  = "bootstrap/intermediate-proxy-app"
}

# Users
terraform-admin-group-eligible-users = [
  "rahul.raina@Denave064.onmicrosoft.com"
]

# Owner access to be given to these resource group names
resource_groups_owner_access = [
  "myden-staging"
]