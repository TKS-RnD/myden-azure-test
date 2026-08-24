
# Create the workforce pool.
resource "google_iam_workforce_pool" "all_users" {
  workforce_pool_id = var.gcp_pool_id
  location          = "global"
  parent            = "organizations/${data.google_organization.current.org_id}"
}

# Create the pool provider.
resource "google_iam_workforce_pool_provider" "azure_ad_provider" {

  # Standard fields.
  display_name = "Azure AD Provider"
  description  = "OIDC provider linking Azure AD"
  provider_id  = var.gcp_provider_id

  # Link with workforce pool.
  location          = google_iam_workforce_pool.all_users.location
  workforce_pool_id = google_iam_workforce_pool.all_users.workforce_pool_id
  disabled          = false

  # Attribute mapping between IDP and Workforce
  attribute_mapping = {

    # Use 'object id' as subject, use 'sub' to bind to id composed of application and directory
    "google.subject" = "assertion.oid"

    # Use 'name' as display name
    "google.display_name" = "assertion.name"

    # Store 'groups' for groups IAM expressions
    "google.groups" = "assertion.groups"
  }

  # OIDC URL and other related stuff.
  oidc {
    issuer_uri = "https://login.microsoftonline.com/${data.azuread_client_config.current.tenant_id}/v2.0"
    client_id  = azuread_application.gcp_sso_app.client_id
    client_secret {
      value {
        plain_text = azuread_application_password.gcp_sso_app_secret.value
      }
    }

    # Required for interactive web SSO with Workforce Identity Federation
    web_sso_config {
      response_type             = "CODE"
      assertion_claims_behavior = "MERGE_USER_INFO_OVER_ID_TOKEN_CLAIMS"
    }
  }

}

## Grant google workforce pool permission to browse resource hierarchy
resource "google_organization_iam_member" "gcp_org_browser_access" {
  org_id = data.google_organization.current.org_id
  role   = "roles/browser"
  member = "principalSet://iam.googleapis.com/${google_iam_workforce_pool.all_users.name}/*"
}
