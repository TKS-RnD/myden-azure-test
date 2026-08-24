# Flatten assignments so that it works correctly since azuread_directory_role does not work for lists.
locals {

  flattened_roles_user = flatten([
    for role, users in var.terraform-builtin-roles-users : [
      for user in users : {
        role = role
        user = user
      }
    ]
  ])

  # Create a role-user map with user as value
  role_user_map = {
    for pair in local.flattened_roles_user : "${pair["role"]}_${pair["user"]}" => pair["user"]
  }

  # Create a role-user map with role as value
  role_by_key = {
    for pair in local.flattened_roles_user : "${pair["role"]}_${pair["user"]}" => pair["role"]
  }

}

# Get the user
data "azuread_user" "users" {
  for_each            = local.role_user_map
  user_principal_name = each.value
}

# Activate User roles.
resource "azuread_directory_role" "user_roles" {
  for_each     = toset(keys(var.terraform-builtin-roles-users))
  display_name = each.value
}

# Make users permanently ELIGIBLE for the role (PIM), not directly assigned.
resource "azuread_directory_role_eligibility_schedule_request" "user_role_eligibility" {

  for_each = local.role_user_map

  role_definition_id = azuread_directory_role.user_roles[local.role_by_key[each.key]].template_id
  directory_scope_id = "/"
  principal_id       = data.azuread_user.users[each.key].object_id
  justification      = "Daily work"

  provider = azuread.proxy_app
}
