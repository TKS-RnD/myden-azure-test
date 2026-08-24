# Create Key Vault
resource "azurerm_key_vault" "war_upload" {

  # Key Vault Name
  name = var.upload_control.keyvault_name

  # Location and Resource Group Name
  location            = var.location
  resource_group_name = var.resource_group_names.vault

  # Tenant and SKU
  tenant_id = data.azurerm_subscription.current.tenant_id
  sku_name  = "standard"

  # MANDATORY: Enable RBAC model (ignores legacy access policies)
  rbac_authorization_enabled = true

  tags = var.tags
}

# Give ourselves permission to write secrets.
resource "azurerm_role_assignment" "terraform_deployer_kv_admin" {
  scope                = azurerm_key_vault.war_upload.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# SAS Key Start and Expiry. We point back -1 day so that the key is instantly usable.
resource "time_offset" "start_day" {
  offset_hours = -24
  triggers = {
    rotate = var.upload_control.rotate_sas_key
  }
}

resource "time_offset" "end_day" {
  base_rfc3339 = time_offset.start_day.rfc3339
  offset_years = var.upload_control.expiry_after_years
}

####################################################################################################################
# Scoped upload access for CI systems (Jenkins/GitHub)
#
# Generates a Share-level SAS token scoped to the WAR file share, with minimal permissions required to upload/list
# artifacts. The token is stored in the module Key Vault for consumption by CI/CD pipelines.
####################################################################################################################
data "azurerm_storage_account_sas" "war_upload_sas" {

  # Use account connection string to sign the SAS, since we use the secondary for VMs.
  connection_string = azurerm_storage_account.war_storage.primary_connection_string

  # Limit to HTTPS only and CI public IPs if provided
  https_only = true

  # Service and resource scope: Azure Files, object-level within the share
  services {
    file  = true
    blob  = false
    queue = false
    table = false
  }
  resource_types {
    object    = true
    container = true
    service   = true
  }

  # These dates are ignored by Key Vault; it uses 'validity_period' instead
  start  = time_offset.start_day.rfc3339
  expiry = time_offset.end_day.rfc3339

  # Modern version for latest azcopy
  signed_version = "2022-11-02"

  # Minimal permissions for uploading WAR files and listing
  permissions {
    read    = true  # allow verification/reads if needed
    create  = true  # create new files
    add     = true  # append blocks
    list    = true  # list directory/share
    write   = true  # allow overwrite existing files
    delete  = false # do not allow deletes via this SAS
    tag     = false # Tagging WARs is not supported for Azure Files.
    filter  = false # Running filters too.
    update  = false
    process = false
  }
}

# Store the sas Key
resource "azurerm_key_vault_secret" "upload_sas_token" {
  key_vault_id = azurerm_key_vault.war_upload.id
  name         = var.upload_control.sas_token_key_name
  value        = data.azurerm_storage_account_sas.war_upload_sas.sas
  depends_on = [
    azurerm_role_assignment.terraform_deployer_kv_admin
  ]

  tags = merge(var.tags, {
    accessible_by = var.upload_control.github_managed_identity.id
  })
}

# GOVERNANCE: PREVENT ACCIDENTAL DELETION for production.
resource "azurerm_management_lock" "war_upload_vault_lock" {

  count = (var.environment == "production") ? 1 : 0

  name       = "can-not-delete-lock"
  scope      = azurerm_key_vault.war_upload.id
  lock_level = "CanNotDelete"
  notes      = "This is a Uploader Key vault. Deletion requires a change request."
}
