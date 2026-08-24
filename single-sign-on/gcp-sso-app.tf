# The app to create in AAD for SSO.
resource "azuread_application" "gcp_sso_app" {

  # Display Name.
  display_name = "GCP Workforce SSO via Azure AD"
  description  = "Single Sign-on App for GCP"

  # owners
  owners = [
    data.azuread_client_config.current.object_id
  ]

  # No Duplicates
  prevent_duplicate_names = true

  # Limited to my Org.
  sign_in_audience = "AzureADMyOrg"

  # Emit group claims in ID tokens
  group_membership_claims = [
    "SecurityGroup"
  ]

  # Optional claims to include standard attributes
  optional_claims {
    id_token {
      name      = "email"
      essential = true
    }
    id_token {
      name      = "name"
      essential = true
    }
    id_token {
      name = "groups"
    }
  }

  # Optional web configuration (redirect URIs for OIDC flow)
  web {
    implicit_grant {
      access_token_issuance_enabled = false
      id_token_issuance_enabled     = true
    }
  }

  # Tags
  tags = [
    "Terraform Managed",
    "DO NOT DELETE"
  ]

  # Life cycle management.
  lifecycle {
    ignore_changes = [
      password,                 # managed using azuread_application_password.workforce_identity_federation
      required_resource_access, # managed using azuread_application_api_access.workforce_identity_federation
      web[0].redirect_uris
    ]
  }
}

# Rotate password every 6 months.
resource "time_rotating" "every_6_months" {
  rotation_months = 6
}

# Client secret for the Azure AD application used as the confidential OIDC client
# NOTE: The secret value is stored in Terraform state. Protect state access.
resource "azuread_application_password" "gcp_sso_app_secret" {
  application_id = azuread_application.gcp_sso_app.id
  display_name   = "GCP Workforce OIDC client secret"
  rotate_when_changed = {
    every_6_months = time_rotating.every_6_months.id
  }
}

# All graph applications
data "azuread_service_principal" "microsoft_graph" {
  client_id = data.azuread_application_published_app_ids.well_known.result["MicrosoftGraph"]
}

# API Access for the Application.
resource "azuread_application_api_access" "gcp_sso_identity_federation" {
  application_id = azuread_application.gcp_sso_app.id
  api_client_id  = data.azuread_application_published_app_ids.well_known.result["MicrosoftGraph"]

  scope_ids = [
    for scope in var.azure_ad_app_default_scopes : data.azuread_service_principal.microsoft_graph.oauth2_permission_scope_ids[scope]
  ]
}

# Admin consent openid, email and profile scope ids using enterprise application
resource "azuread_service_principal" "gcp_sso_identity_federation" {
  client_id                    = azuread_application.gcp_sso_app.client_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.current.object_id]
}

# Permission grant.
resource "azuread_service_principal_delegated_permission_grant" "gcp_sso_federation_consent" {
  service_principal_object_id          = azuread_service_principal.gcp_sso_identity_federation.object_id
  resource_service_principal_object_id = data.azuread_service_principal.microsoft_graph.object_id
  claim_values                         = var.azure_ad_app_default_scopes
}

# Allow redirect to workforce identity pool provider
resource "azuread_application_redirect_uris" "gcp_sso_federation_web" {
  application_id = azuread_application.gcp_sso_app.id
  type           = "Web"
  redirect_uris = [
    "https://auth.cloud.google/signin-callback/${google_iam_workforce_pool_provider.azure_ad_provider.name}",
  ]
}
