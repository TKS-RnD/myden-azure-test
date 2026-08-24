
# Serverless Database
resource "azurerm_mssql_database" "serverless_db" {

  count = length(var.server_configuration.databases)

  name        = var.server_configuration.databases[count.index].name
  server_id   = azurerm_mssql_server.sql_server.id
  collation   = var.server_configuration.databases[count.index].collation
  sku_name    = "GP_S_Gen5_1" # Serverless SKU
  max_size_gb = var.server_configuration.databases[count.index].gb_size

  # Minimal capacity that database will always have allocated, if not paused.
  min_capacity                = 0.5
  auto_pause_delay_in_minutes = (var.server_configuration.databases[count.index].long_term_weekly_backups == 0) ? 60 : (null)

  # Short Term retention policy
  short_term_retention_policy {
    retention_days = var.server_configuration.databases[count.index].short_term_retention_days
  }

  # Long Term retention policy
  dynamic "long_term_retention_policy" {
    for_each = (var.server_configuration.databases[count.index].long_term_weekly_backups != 0) ? [1] : []
    content {
      weekly_retention = "P${var.server_configuration.databases[count.index].long_term_weekly_backups}W"
    }
  }

  # Prevent the possibility of accidental data loss
  #lifecycle {
  #  prevent_destroy = true
  #}

  # Tags
  tags = var.tags
}
