
# 1. Create a Log Analytics Workspace specifically for storage analytics (as requested)
resource "azurerm_log_analytics_workspace" "war_storage_analytics" {
  name                = var.log_analytics_workspace_name
  location            = var.location
  resource_group_name = var.resource_group_names.storage

  sku               = "PerGB2018"
  retention_in_days = 30

  tags = var.tags
}

# 2. Enable Diagnostic settings for the Storage Account FILE SERVICE
# We use the file service ID because storage account logs are service-specific.
resource "azurerm_monitor_diagnostic_setting" "war_storage_file_logs" {
  name                       = "war-storage-file-service-logs"
  target_resource_id         = "${azurerm_storage_account.war_storage.id}/fileServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.war_storage_analytics.id

  # Captures all authentication and access logs
  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }
}
