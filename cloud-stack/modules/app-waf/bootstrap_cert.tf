# Current subscription and tenant
data "azurerm_subscription" "current" {}
data "azuread_client_config" "current" {}
data "azurerm_client_config" "current" {}

# Create Key Vault
resource "azurerm_key_vault" "certificate_vault" {

  # Key Vault Name
  name = var.waf_settings.ssl_certificate.key_vault_name

  # Location and Resource Group Name
  location            = var.location
  resource_group_name = var.resource_group

  # Tenant and SKU
  tenant_id = data.azurerm_subscription.current.tenant_id
  sku_name  = "standard"

  # MANDATORY: Enable RBAC model (ignores legacy access policies)
  rbac_authorization_enabled = true

  # SECURITY: Prevent purging of deleted items
  purge_protection_enabled   = true
  soft_delete_retention_days = 90

  tags = var.tags
}

# Grant Terraform (Runner) the right to WRITE secrets
resource "azurerm_role_assignment" "tf_secrets_officer" {
  scope                = azurerm_key_vault.certificate_vault.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azuread_client_config.current.object_id
}

# Grant Terraform (Runner) the right to WRITE certificates
resource "azurerm_role_assignment" "tf_cert_officer" {
  scope                = azurerm_key_vault.certificate_vault.id
  role_definition_name = "Key Vault Certificates Officer"
  principal_id         = data.azuread_client_config.current.object_id
}

# Create the bootstrap certificate.
resource "azurerm_key_vault_certificate" "bootstrap" {
  name         = var.waf_settings.ssl_certificate.secret_name_bootstrap
  key_vault_id = azurerm_key_vault.certificate_vault.id

  certificate_policy {
    issuer_parameters {
      name = "Self" # Tells Azure to self-sign
    }

    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = true
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      subject            = "CN=*.${var.waf_settings.front_end.domain_name}"
      validity_in_months = 12
      subject_alternative_names {
        dns_names = [
          var.waf_settings.front_end.host_name,
          "*.${var.waf_settings.front_end.domain_name}"
        ]
      }
      key_usage = [
        "cRLSign",
        "dataEncipherment",
        "digitalSignature",
        "keyAgreement",
        "keyCertSign",
        "keyEncipherment",
      ]
    }
  }

  lifecycle {
    ignore_changes = [certificate_policy]
  }

  # Sort out dependencies
  depends_on = [
    azurerm_role_assignment.tf_secrets_officer,
    azurerm_role_assignment.tf_cert_officer
  ]
}

# Create a Managed identity for the gateway to read secrets from the key vault.
resource "azurerm_user_assigned_identity" "app_gw_identity" {
  name                = "mi-app-gateway-${var.environment}"
  resource_group_name = var.resource_group
  location            = var.location
  tags                = var.tags
}

# Create the role and assign it to the gateway.
resource "azurerm_role_assignment" "gw_kv_secrets_user" {
  scope                = azurerm_key_vault.certificate_vault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.app_gw_identity.principal_id
}
