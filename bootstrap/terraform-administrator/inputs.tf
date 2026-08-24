# The name of the Terraform administrator role.
variable "terraform-admin-role-name" {
  type        = string
  description = "Name of the Terraform Administrator role"
}

# The name of the group name in Azure AD to which this role can be assigned.
variable "terraform-admin-group-name" {
  type        = string
  description = "Name of the Terraform Administrator Group Name."
}

# List of built-in roles that should be added to the group.
variable "terraform-admin-ad-group-builtin-roles" {
  type        = list(string)
  description = "List of built-in roles that should be added to the group."
}

# Should enable conditional access policy for the Terraform administrator group
variable "enable_conditional_access" {
  type        = bool
  description = "Should Enable Conditional Access for Terraform administrator group"
  default     = false
}

##############    Variables that depend upon Staging or Production follow from here #######.

# Azure Subscription ID
variable "azure_subscription_id" {
  type        = string
  description = "Azure Subscription ID"
}

# Remote workspace to import values from
variable "proxy_app_workspace" {
  type = object({
    resource_group_name  = string,
    storage_account_name = string,
    container_name       = string,
    key                  = string
  })
}

# List of users who are eligible to join the group
variable "terraform-admin-group-eligible-users" {
  type        = list(string)
  description = "List of users who are eligible to join the group"
}

# List of built-in roles and users who need to be assigned to those roles.
variable "terraform-builtin-roles-users" {
  type        = map(list(string))
  description = "List of built-in roles and users that should be added to the users."
}

# Resource groups to which owner access needs to be given for Terraform administrator.
# This means that resource groups needs to be pre-created and must be added here by root administrator.
variable "resource_groups_owner_access" {
  type        = set(string)
  description = "Resource groups to which owner access needs to be given for Terraform administrator"
}
