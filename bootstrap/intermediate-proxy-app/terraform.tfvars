# Proxy app name
azure_cli_proxy_app-name = "Azure Intermediate Proxy App for Bootstrapping Terraform"

# Proxy App Description
azure_cli_proxy_app_description = "Intermediate App for Bootstrapping Terraform"

# Permissions. Note that this is evolved via series of tests. Every time a new permission
# is added here, consent must be added manually by Global Administrator or else the intended effect
# might not happen.
azure_cli_proxy_app_permissions = [
  "Policy.ReadWrite.ConditionalAccess", # For Creating Conditional Access Policies.
  "Policy.Read.All",
  "Application.Read.All",
  "RoleManagementPolicy.ReadWrite.AzureADGroup", # For Role Management and Azure AD Group.
  "RoleManagement.ReadWrite.Directory",
  "PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup", # For PIM Management and Access.
  "PrivilegedAccess.ReadWrite.AzureADGroup",
  "PrivilegedEligibilitySchedule.Remove.AzureADGroup"
]
