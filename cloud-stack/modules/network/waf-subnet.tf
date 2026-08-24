# Create the WAF Zone
resource "azurerm_dns_zone" "waf_zone" {
  name                = var.waf_subnet.domain_name
  resource_group_name = var.top_level_network.resource_group_name
  tags                = var.tags
}

# Subnet for Azure WF.
resource "azurerm_subnet" "waf_subnet" {

  # Other parameters
  name                = var.waf_subnet.subnet_name
  resource_group_name = var.top_level_network.resource_group_name

  # Under the top level subnet
  virtual_network_name = azurerm_virtual_network.top_level_network.name
  address_prefixes = [
    var.waf_subnet.subnet_mask
  ]
}

# Create the WAF public ip
resource "azurerm_public_ip" "waf_public_ip" {
  name                = "${module.naming.public_ip.name}-waf"
  resource_group_name = var.top_level_network.resource_group_name
  location            = var.top_level_network.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags = merge(var.tags, {
    subnet = azurerm_subnet.waf_subnet.name
  })
}

# Associate the public ip with the DNS
resource "azurerm_dns_a_record" "waf_dns_record" {
  name                = var.waf_subnet.host_name
  resource_group_name = var.top_level_network.resource_group_name
  zone_name           = azurerm_dns_zone.waf_zone.name
  ttl                 = 86400
  records = [
    azurerm_public_ip.waf_public_ip.ip_address
  ]
}

# Create NSGs for WAF Subnet.
resource "azurerm_network_security_group" "waf_subnet" {

  # Ensure unique NSG name per application subnet to avoid collisions with existing NSGs
  name                = "${module.naming.network_security_group.name}-${var.waf_subnet.subnet_name}"
  location            = var.top_level_network.location
  resource_group_name = var.top_level_network.resource_group_name

  tags = merge(var.tags, {
    subnet = azurerm_subnet.waf_subnet.name
  })
}

# Associate NSG with the subnet.
resource "azurerm_subnet_network_security_group_association" "waf_subnet" {

  subnet_id                 = azurerm_subnet.waf_subnet.id
  network_security_group_id = azurerm_network_security_group.waf_subnet.id
}

# Allow Traffic from Gateway Manager for AppGW Infrastructure.
resource "azurerm_network_security_rule" "allow_app_gw_infra" {

  name      = "Allow-AppGW-Infrastructure"
  priority  = 100
  direction = "Inbound"
  access    = "Allow"
  protocol  = "Tcp"

  source_port_range       = "*"
  destination_port_ranges = ["65200-65535"]

  source_address_prefix      = "GatewayManager"
  destination_address_prefix = "*"

  # Resource group
  resource_group_name = var.top_level_network.resource_group_name

  # Which NSG this rule belongs to (of application subnet)
  network_security_group_name = azurerm_network_security_group.waf_subnet.name
}

# Allow Traffic from Azure load balancer for health probes.
resource "azurerm_network_security_rule" "allow_lb_health_probes" {

  name      = "Allow-LB-Health-Probes"
  priority  = 110
  direction = "Inbound"
  access    = "Allow"
  protocol  = "*"

  source_port_range      = "*"
  destination_port_range = "*"

  source_address_prefix      = "AzureLoadBalancer"
  destination_address_prefix = "*"

  # Resource group
  resource_group_name = var.top_level_network.resource_group_name

  # Which NSG this rule belongs to (of application subnet)
  network_security_group_name = azurerm_network_security_group.waf_subnet.name
}

# Allow Inbound HTTP traffic from internet
resource "azurerm_network_security_rule" "allow_http_inbound" {
  name                        = "Allow-HTTP-Inbound"
  priority                    = 120
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "Internet"
  destination_address_prefix  = "*"
  resource_group_name         = var.top_level_network.resource_group_name
  network_security_group_name = azurerm_network_security_group.waf_subnet.name
}

# Allow Inbound HTTPS traffic from internet
resource "azurerm_network_security_rule" "allow_https_inbound" {
  name                        = "Allow-HTTPS-Inbound"
  priority                    = 130
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "Internet"
  destination_address_prefix  = "*"
  resource_group_name         = var.top_level_network.resource_group_name
  network_security_group_name = azurerm_network_security_group.waf_subnet.name
}

# Need to generate a rule priority index based on app-subnets. Rules for app-subnets will be in 300+index range.
locals {
  app_subnet_rule_index = {
    for index, key in keys(var.application_subnets) : key => 300 + index
  }
}

# Add a rule for the application subnet from bastion depending upon configuration
resource "azurerm_network_security_rule" "allow_deny_waf_to_app_subnet" {

  # Iterate through subnets only when Bastion is enabled
  for_each = var.application_subnets

  # Which NSG this rule belongs to (of application subnet)
  network_security_group_name = azurerm_network_security_group.waf_subnet.name

  # Rule Name
  name = "WAF-to-${each.key}"

  # Resource group
  resource_group_name = var.top_level_network.resource_group_name

  # Source and destination
  source_address_prefix      = azurerm_subnet.waf_subnet.address_prefixes[0]
  destination_address_prefix = azurerm_subnet.app_subnets[each.key].address_prefixes[0]

  # Priority
  priority               = local.app_subnet_rule_index[each.key]
  direction              = "Inbound"
  protocol               = "*"
  source_port_range      = "*"
  destination_port_range = "*"

  # Allow or deny based on configuration
  access = lookup(each.value, "reachable_from_waf", false) ? "Allow" : "Deny"
}
