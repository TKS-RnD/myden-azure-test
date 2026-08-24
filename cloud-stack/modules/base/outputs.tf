# Resource groups and their purpose.
output "resource_groups" {
  value = merge({
    for i in range(0, length(var.resource_groups)) :
    var.resource_groups[i].purpose => var.resource_groups[i].name
    }, {
    (local.purpose) = local.name
  })
}

# AD Groups
output "ad_groups" {
  value = {
    for i in range(0, length(var.ad_groups)) :
    var.ad_groups[i].name => azuread_group.baseline_groups[i].object_id
  }
}

# AD Groups that need RDP Access
output "ad_groups_rdp_access" {
  value = {
    for i in range(0, length(var.ad_groups)) :
    var.ad_groups[i].name => azuread_group.baseline_groups[i].object_id if var.ad_groups[i].rdp_access
  }
}

# Managed Identities
output "managed_identities" {
  value = {
    for i in range(0, length(var.managed_identities)) :
    var.managed_identities[i].mnemonic => azurerm_user_assigned_identity.vm_identity[i]
  }
}

# Managed Applications
output "managed_applications" {
  sensitive = true
  value = {
    for i in range(0, length(var.managed_applications)) :
    var.managed_applications[i].mnemonic => {
      service_principal_id = azuread_service_principal.managed_application[i].object_id
      application_id       = azuread_service_principal.managed_application[i].client_id
      tenant_id            = azuread_service_principal.managed_application[i].application_tenant_id

      # Certificate only if desired.
      certificate = var.managed_applications[i].cert_login ? tls_self_signed_cert.managed_app_cert[var.managed_applications[i].mnemonic].cert_pem : null

      # Password only if desired
      password = var.managed_applications[i].password ? azuread_application_password.managed_app_secret[var.managed_applications[i].mnemonic].value : null
    }
  }
}
