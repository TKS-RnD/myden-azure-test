# Subnet for support
resource "azurerm_subnet" "support_subnet" {

  # Other parameters
  name                = var.support_subnet.name
  resource_group_name = var.top_level_network.resource_group_name

  # Under the top level subnet
  virtual_network_name = azurerm_virtual_network.top_level_network.name
  address_prefixes = [
    var.support_subnet.subnet_mask
  ]

  # Services
  service_endpoints = var.support_subnet.services_attached
}

# Create the Support NICs
resource "azurerm_network_interface" "support_subnet_nics" {

  count = var.support_subnet.nic_count

  # The non-ip configuration block
  name                = "${var.support_subnet.name}-nic-${count.index}"
  location            = var.top_level_network.location
  resource_group_name = var.top_level_network.resource_group_name

  # IP Configuration
  ip_configuration {
    name                          = "${var.support_subnet.name}-nic-${count.index}-ip"
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.support_subnet.id
  }

  tags = merge(var.tags, {
    subnet_name = var.support_subnet.nic_count
  })
}

# Create NSGs for support subnet
resource "azurerm_network_security_group" "support_subnet" {

  # Ensure unique NSG name per application subnet to avoid collisions with existing NSGs
  name                = "${module.naming.network_security_group.name}-${var.support_subnet.name}"
  location            = var.top_level_network.location
  resource_group_name = var.top_level_network.resource_group_name

  tags = merge(var.tags, {
    subnet = azurerm_subnet.support_subnet.name
  })
}

# Associate NSG with the subnet.
resource "azurerm_subnet_network_security_group_association" "support_subnet" {

  subnet_id                 = azurerm_subnet.support_subnet.id
  network_security_group_id = azurerm_network_security_group.support_subnet.id
}

# Add a rule for the subnet from bastion depending upon configuration
resource "azurerm_network_security_rule" "allow_deny_bastion_to_support_subnet" {

  # Which NSG this rule belongs to (of application subnet)
  network_security_group_name = azurerm_network_security_group.support_subnet.name

  # Rule Name
  name = "Bastion-to-${var.support_subnet.name}"

  # Resource group
  resource_group_name = var.top_level_network.resource_group_name

  # Source and destination
  source_address_prefix      = azurerm_subnet.bastion_subnet[0].address_prefixes[0]
  destination_address_prefix = azurerm_subnet.support_subnet.address_prefixes[0]

  # Priority
  priority               = 100
  direction              = "Inbound"
  protocol               = "*"
  source_port_range      = "*"
  destination_port_range = "*"

  # Allow or deny based on configuration
  access = (var.support_subnet.reachable_from_bastion) ? "Allow" : "Deny"
}

# Add a rule for the subnet from dba subnet depending upon configuration
resource "azurerm_network_security_rule" "allow_deny_dba_to_support_subnet" {

  # Which NSG this rule belongs to (of application subnet)
  network_security_group_name = azurerm_network_security_group.support_subnet.name

  # Rule Name
  name = "Dba-to-${var.support_subnet.name}"

  # Resource group
  resource_group_name = var.top_level_network.resource_group_name

  # Source and destination
  source_address_prefix      = azurerm_subnet.dba_subnet.address_prefixes[0]
  destination_address_prefix = azurerm_subnet.support_subnet.address_prefixes[0]

  # Priority
  priority               = 110
  direction              = "Inbound"
  protocol               = "*"
  source_port_range      = "*"
  destination_port_range = "*"

  # Allow or deny based on configuration
  access = (var.support_subnet.reachable_from_dba_subnet) ? "Allow" : "Deny"
}

# Create a rule index for app subnets
locals {
  support_app_rule_index = {
    for index, key in keys(var.application_subnets) : key => (120 + (index) * 10)
  }
}

# Add a rule for the subnet from app subnets depending upon configuration
resource "azurerm_network_security_rule" "allow_deny_app_subnet_support_subnet" {

  # Iterate through subnets
  for_each = var.application_subnets

  # Which NSG this rule belongs to (of application subnet)
  network_security_group_name = azurerm_network_security_group.support_subnet.name

  # Rule Name
  name = "${each.key}-to-${var.support_subnet.name}"

  # Resource group
  resource_group_name = var.top_level_network.resource_group_name

  # Source and destination
  source_address_prefix      = azurerm_subnet.app_subnets[each.key].address_prefixes[0]
  destination_address_prefix = azurerm_subnet.support_subnet.address_prefixes[0]

  # Priority
  priority               = local.app_subnet_rule_index[each.key]
  direction              = "Inbound"
  protocol               = "*"
  source_port_range      = "*"
  destination_port_range = "*"

  # Allow or deny based on configuration
  access = (var.support_subnet.reachable_from_app_subnet) ? "Allow" : "Deny"
}
