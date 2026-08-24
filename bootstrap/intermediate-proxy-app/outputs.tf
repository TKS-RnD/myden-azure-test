# Application Client ID
output "application_id" {
  value = azuread_application.ad_proxy_app.client_id
}

# Service Principal Object ID
output "service_principal_id" {
  value = azuread_service_principal.ad_proxy_app_sp.object_id
}

# Tenant ID
output "tenant_id" {
  value = azuread_service_principal.ad_proxy_app_sp.application_tenant_id
}

# Client Secret
output "client_secret" {
  sensitive = true
  value     = azuread_application_password.ad_proxy_app_pwd.value
}
