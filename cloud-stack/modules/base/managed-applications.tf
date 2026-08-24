# Managed applications for everyone!
resource "azuread_application" "managed_application" {

  count = length(var.managed_applications)

  display_name = var.managed_applications[count.index].name
  description  = var.managed_applications[count.index].description
}

# Service Principals for managed applications.
resource "azuread_service_principal" "managed_application" {

  count = length(var.managed_applications)

  client_id   = azuread_application.managed_application[count.index].client_id
  description = var.managed_applications[count.index].description
}

# Do we need certs and login passwords for each of these?
locals {
  apps_requiring_cert = {
    for i, app in var.managed_applications :
    app.mnemonic => {
      index  = i
      name   = app.name
      id     = azuread_application.managed_application[i].id
      obj_id = azuread_application.managed_application[i].object_id
    }
    if app.cert_login
  }
  apps_requiring_password = {
    for i, app in var.managed_applications :
    app.mnemonic => {
      index  = i
      name   = app.name
      id     = azuread_application.managed_application[i].id
      obj_id = azuread_application.managed_application[i].object_id
    }
    if app.password
  }
}

# Time rotating resource for both certificate and login
resource "time_rotating" "app_cred" {
  rotation_years = 1
}

# Generate Private Keys for those apps
resource "tls_private_key" "managed_app_key" {
  for_each  = local.apps_requiring_cert
  algorithm = "RSA"
  rsa_bits  = 2048
  lifecycle {
    replace_triggered_by = [
      time_rotating.app_cred
    ]
  }
}

# Create Self-Signed Certificates
resource "tls_self_signed_cert" "managed_app_cert" {
  for_each        = local.apps_requiring_cert
  private_key_pem = tls_private_key.managed_app_key[each.key].private_key_pem

  subject {
    common_name  = each.value.name
    organization = "Denave"
  }

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth",
  ]
}

# Associate Certificates with the Azure AD Applications
resource "azuread_application_certificate" "managed_app_cert" {
  for_each       = local.apps_requiring_cert
  application_id = each.value.id
  type           = "AsymmetricX509Cert"
  value          = tls_self_signed_cert.managed_app_cert[each.key].cert_pem
  end_date       = tls_self_signed_cert.managed_app_cert[each.key].validity_end_time
}

# Generate an application password which is valid for 1 year.
resource "azuread_application_password" "managed_app_secret" {
  for_each       = local.apps_requiring_password
  application_id = each.value.id
  display_name   = "${each.value.name}-secret"
  end_date       = timeadd(time_rotating.app_cred.rfc3339, "8760h")
}
