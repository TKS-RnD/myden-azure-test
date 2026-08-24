# Create a custom role that only allows insertion and deletion of TXT records in the given domain name.
resource "azurerm_role_definition" "dns_txt_manager" {
  name        = "DNS-TXT-Manager-${var.environment}"
  scope       = data.azurerm_subscription.current.id
  description = "Allows insertion and deletion of TXT records in ${var.waf_settings.front_end.domain_name}"

  permissions {
    actions = [
      "Microsoft.Network/dnsZones/read",
      "Microsoft.Network/dnsZones/TXT/read",
      "Microsoft.Network/dnsZones/TXT/write",
      "Microsoft.Network/dnsZones/TXT/delete",
      "Microsoft.Resources/subscriptions/resourceGroups/read"
    ]
    not_actions = []
  }

  assignable_scopes = [
    data.azurerm_subscription.current.id
  ]
}

# Assign this custom role to the managed identity that is responsible for cert rotation.
resource "azurerm_role_assignment" "mi_dns_txt_manager" {
  scope              = data.azurerm_subscription.current.id
  role_definition_id = azurerm_role_definition.dns_txt_manager.role_definition_resource_id
  principal_id       = var.waf_settings.ssl_certificate.mi_rotation.principal_id
}

# Create a custom role that can only read and write certificates in the azure key vault for
# managing certificates by the specific secret name (not bootstrap).
resource "azurerm_role_definition" "kv_cert_manager" {
  name        = "KV-Cert-Manager-${var.environment}"
  scope       = azurerm_key_vault.certificate_vault.id
  description = "Allows reading and writing certificates in Key Vault for ${var.waf_settings.ssl_certificate.secret_name_production}"

  permissions {
    data_actions = [
      "Microsoft.KeyVault/vaults/certificates/read",
      "Microsoft.KeyVault/vaults/certificates/create/action",
      "Microsoft.KeyVault/vaults/certificates/update/action",
      "Microsoft.KeyVault/vaults/certificates/import/action",
      "Microsoft.KeyVault/vaults/certificates/delete"
    ]
  }

  assignable_scopes = [
    azurerm_key_vault.certificate_vault.id
  ]
}

# Assign this custom role to the managed identity.
resource "azurerm_role_assignment" "mi_kv_cert_manager" {
  scope              = azurerm_key_vault.certificate_vault.id
  role_definition_id = azurerm_role_definition.kv_cert_manager.role_definition_resource_id
  principal_id       = var.waf_settings.ssl_certificate.mi_rotation.principal_id
}

# Then add a OIDC credential to this managed identity that can be authenticated via github repos given the input.
resource "azurerm_federated_identity_credential" "github_oidc" {

  for_each = toset(var.waf_settings.ssl_certificate.mi_rotation.github_repos)

  name                = replace(replace(each.value, "/", "-"), ":", "-")
  resource_group_name = var.waf_settings.ssl_certificate.mi_rotation.resource_group
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  parent_id           = var.waf_settings.ssl_certificate.mi_rotation.id
  subject             = "repo:${each.value}"
}

# The production certificate is only available when bootstrap mode is not set. Hence managing the id for that is
# a bit tricky.
data "azurerm_key_vault_secret" "prod_certificate" {
  count        = (var.waf_settings.ssl_certificate.bootstrap_mode) ? 0 : 1
  key_vault_id = azurerm_key_vault.certificate_vault.id
  name         = var.waf_settings.ssl_certificate.secret_name_production
}
