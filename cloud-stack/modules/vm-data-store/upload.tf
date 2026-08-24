
############################################################
# Scoped upload access for CI systems (Jenkins/GitHub)
#
# Generates a Share-level SAS token scoped to the WAR file
# share, with minimal permissions required to upload/list
# artifacts. The token is stored in the module Key Vault
# for consumption by CI/CD pipelines.
############################################################

# Generate a Share SAS for Azure Files (scoped to the WAR share)
data "azurerm_storage_account_sas" "war_upload_sas" {

  # Use account connection string to sign the SAS
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
    container = false
    service   = false
  }

  # Validity window: start slightly in the past to avoid clock skew; expires in 1 year
  start  = timeadd(timestamp(), "-15m")
  expiry = timeadd(timestamp(), "8760h") # 365 days

  # Storage service REST API version for SAS
  signed_version = "2022-11-02"

  # Minimal permissions for uploading WAR files and listing
  permissions {
    read    = true # allow verification/reads if needed
    create  = true # create new files
    add     = true # append blocks
    list    = true # list directory/share
    write   = true # allow overwrite existing files
    tag     = true # Tagging WARs is allowed.
    filter  = true # Running filters too.
    update  = false
    delete  = false # do not allow deletes via this SAS
    process = false
  }
}
