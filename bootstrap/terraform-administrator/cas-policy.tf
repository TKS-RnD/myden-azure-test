# Writes out a Conditional access policy for Terraform administrator. The policy requires a FIDO Key
# for activating the role.

# 1. Create a custom Authentication Strength policy.
resource "azuread_authentication_strength_policy" "terraform_administrator_elevation" {

  display_name = "Terraform-Admin-Elevation"
  description  = "Custom Policy for Managing Terraform Administrator Elevation"

  allowed_combinations = [
    "fido2",                  # FIDO2 Pass Keys.
    "windowsHelloForBusiness" # Windows Hello For business.
  ]

  # Use Intermediate App because AZ CLI can't handle this.
  provider = azuread.proxy_app
}

# 2. Conditional Access Policy that requires that strength for role activation
# NOTE on 403 AccessDenied (Application.Read.All required):
# - The aliased provider azuread.proxy_app uses the intermediate proxy application's service principal.
# - That app must have admin consent granted for Microsoft Graph permissions used here.
# - If consent is missing, Terraform will fail with:
#     AccessDenied: Insufficient privileges to create or update policy. Application.Read.All scope is required
# - Remediation: Grant admin consent to the intermediate proxy app.
resource "azuread_conditional_access_policy" "require_fido_for_pim_activation" {

  # Should we enable Conditional access?
  count = var.enable_conditional_access ? 1 : 0

  # CAS Policy
  display_name = "Require_FIDO2_for_PIM_Role_Activation"
  state        = "enabled"

  conditions {
    # Apply only to members of the Terraform Administrator group
    users {
      included_groups = [azuread_group.terraform_admin_group.object_id]
    }

    # Keep client app types to relevant flows
    client_app_types = ["browser", "mobileAppsAndDesktopClients"]

    # Applications scope
    applications {
      included_applications = ["All"]
    }
  }

  grant_controls {
    # Use the custom authentication strength policy created above
    authentication_strength_policy_id = azuread_authentication_strength_policy.terraform_administrator_elevation.id

    operator          = "OR"
    built_in_controls = []
  }

  # Use Intermediate App because AZ CLI can't handle this.
  provider = azuread.proxy_app
}
