# Create the AAD / Entra Group.
resource "azuread_group" "terraform_admin_group" {
  display_name               = var.terraform-admin-group-name
  description                = "Terraform Administrators Group - Used only for running Terraform recipies"
  prevent_duplicate_names    = true
  auto_subscribe_new_members = false
  external_senders_allowed   = false
  mail_enabled               = false
  security_enabled           = true
  assignable_to_role         = true ## This requires AAD P1/P2 License or else this resource creation
}

# Group Management policy
resource "azuread_group_role_management_policy" "devops_group_admins" {

  # For adding members
  group_id = azuread_group.terraform_admin_group.object_id
  role_id  = "member"

  # Active assignments are permanent.
  active_assignment_rules {
    expiration_required                = false
    require_multifactor_authentication = true
  }
  # Eligible assignments are allowed to be permanent (no expiration).
  eligible_assignment_rules {
    expiration_required = false
  }
  # Active only for 12 Hours and requires a re-login with MFA.
  activation_rules {
    maximum_duration                   = "PT12H"
    require_multifactor_authentication = true
  }

  # The provider
  provider = azuread.proxy_app
}

# List of Eligible users.
data "azuread_users" "terraform_admin_users" {
  user_principal_names = var.terraform-admin-group-eligible-users
}

# Group Eligibility
resource "azuread_privileged_access_group_eligibility_schedule" "terraform_admin_group_eligibility" {

  # Foreach
  for_each = toset(data.azuread_users.terraform_admin_users.users.*.object_id)

  # Group and Principal.
  group_id     = azuread_group.terraform_admin_group.object_id
  principal_id = each.value

  # Other parameters
  assignment_type      = "member"
  justification        = "Terraform Administrator Group"
  permanent_assignment = true

  # The provider (via proxy_app)
  provider = azuread.proxy_app
}
