
# Azure AD Groups to create
resource "azuread_group" "baseline_groups" {

  count = length(var.ad_groups)

  display_name               = var.ad_groups[count.index].name
  description                = var.ad_groups[count.index].description
  prevent_duplicate_names    = true
  security_enabled           = true
  mail_enabled               = false
  external_senders_allowed   = false
  auto_subscribe_new_members = false

  # Timeouts are mandatory or else API Limits will be hit.
  timeouts {
    create = "30m"
    delete = "30m"
    read   = "5m"
  }

  # No need to keep searching for AD Group names.
  lifecycle {
    ignore_changes = [display_name]
  }
}
