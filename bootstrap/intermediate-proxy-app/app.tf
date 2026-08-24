# Well known applications
data "azuread_application_published_app_ids" "well_known" {}

# MS Graph Application.
resource "azuread_service_principal" "microsoft_graph" {

  client_id    = data.azuread_application_published_app_ids.well_known.result.MicrosoftGraph
  use_existing = true

  # Don't delete on destroy as it messes up the tenant.
  lifecycle {
    prevent_destroy = true
  }

  # tags
  tags = [
    "Terraform Managed",
    "DO NOT DELETE"
  ]
}

# Owners
data "azuread_users" "ad_prox_app_owners" {
  user_principal_names = var.azure_cli_proxy_app_owners
}

# Create the App. Consent must be managed manually though.
resource "azuread_application" "ad_proxy_app" {

  # Name and Description.
  display_name = var.azure_cli_proxy_app-name
  description  = var.azure_cli_proxy_app_description

  # No Duplicate names.
  prevent_duplicate_names = true

  # Single Tenant only
  sign_in_audience = "AzureADMyOrg"

  # Owners are only those who are specified.
  owners = data.azuread_users.ad_prox_app_owners.object_ids

  # What Objects and Resources are needed to access for Microsoft Graph Application?
  required_resource_access {

    resource_app_id = data.azuread_application_published_app_ids.well_known.result.MicrosoftGraph

    dynamic "resource_access" {
      for_each = var.azure_cli_proxy_app_permissions
      content {
        id   = azuread_service_principal.microsoft_graph.app_role_ids[resource_access.value]
        type = "Role" # Use "Scope" for delegated permissions
      }
    }
  }

  # tags
  tags = [
    "Terraform Managed",
    "DO NOT DELETE"
  ]
}

# Rotating schedule for the application credential (every 60 days)
resource "time_rotating" "ad_proxy" {
  rotation_days = 60
}

# Start date captured at each rotation
resource "time_static" "ad_proxy_start" {
  triggers = {
    rotation = time_rotating.ad_proxy.rotation_rfc3339
  }
}

# Rotating application password (client secret)
resource "azuread_application_password" "ad_proxy_app_pwd" {
  application_id = azuread_application.ad_proxy_app.id
  display_name   = "Rotating-Bootstrap"

  # Set start date to now (captured at rotation) and end date to start + 90 days
  start_date = time_static.ad_proxy_start.rfc3339
  end_date   = timeadd(time_static.ad_proxy_start.rfc3339, "2160h")

  # Force rotation when the time_rotating ticker advances
  rotate_when_changed = {
    rotation = time_rotating.ad_proxy.rotation_rfc3339
  }
}

# Create the service principal for the app
resource "azuread_service_principal" "ad_proxy_app_sp" {
  client_id = azuread_application.ad_proxy_app.client_id
  owners    = data.azuread_users.ad_prox_app_owners.object_ids

  # tags
  tags = [
    "Terraform Managed",
    "DO NOT DELETE"
  ]
}
