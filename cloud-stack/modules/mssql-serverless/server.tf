
# Random Password
resource "random_password" "db_server_password" {
  length      = 30
  min_lower   = 3
  min_upper   = 3
  min_numeric = 3
  min_special = 3
}

#  MSSQL Server
resource "azurerm_mssql_server" "sql_server" {
  name                = var.server_configuration.name
  resource_group_name = var.resource_group_name
  location            = var.location
  version             = var.server_configuration.version

  # Enforcing Azure AD Auth only
  administrator_login          = var.server_configuration.break_glass_admin_user
  administrator_login_password = random_password.db_server_password.result

  azuread_administrator {
    login_username              = var.server_configuration.admin_aad_group.name
    object_id                   = var.server_configuration.admin_aad_group.id
    azuread_authentication_only = false
  }

  # This allows the Azure Portal and other internal Azure services to connect
  public_network_access_enabled = true

  # Tags
  tags = var.tags
}

# Firewall: Allow Azure Portal & Internal Services
resource "azurerm_mssql_firewall_rule" "allow_azure_services" {

  count = (var.server_configuration.portal_internal_access) ? 1 : 0

  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.sql_server.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Firewall: Allow Multiple CIDR Subnets
resource "azurerm_mssql_firewall_rule" "external_subnets" {

  for_each = {
    for idx, cidr in var.server_configuration.allowed_prefixes : idx => cidr
  }

  name             = "Allow-External-Subnet-${each.key}"
  server_id        = azurerm_mssql_server.sql_server.id
  start_ip_address = cidrhost(each.value, 0)
  end_ip_address   = cidrhost(each.value, -1)
}

# VNet Access (Service Endpoint)
resource "azurerm_mssql_virtual_network_rule" "vnet_rule" {

  for_each = {
    for idx, id in var.server_configuration.allowed_vnets : idx => id
  }

  name      = "Allow-Vnet-Rule-${each.key}"
  server_id = azurerm_mssql_server.sql_server.id
  subnet_id = each.value
}
