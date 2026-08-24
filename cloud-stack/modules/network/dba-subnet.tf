# Subnet for Database Administrator
resource "azurerm_subnet" "dba_subnet" {

  # Other parameters
  name                = var.dba_subnet.name
  resource_group_name = var.top_level_network.resource_group_name

  # Under the top level subnet
  virtual_network_name = azurerm_virtual_network.top_level_network.name
  address_prefixes = [
    var.dba_subnet.subnet_mask
  ]

  # Services
  service_endpoints = var.dba_subnet.services_attached
}

# Create the DBA NICs
resource "azurerm_network_interface" "dba_subnet_nics" {

  count = var.dba_subnet.nic_count

  # The non-ip configuration block
  name                = "${var.dba_subnet.name}-nic-${count.index}"
  location            = var.top_level_network.location
  resource_group_name = var.top_level_network.resource_group_name

  # IP Configuration
  ip_configuration {
    name                          = "${var.dba_subnet.name}-nic-${count.index}-ip"
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.dba_subnet.id
  }

  tags = merge(var.tags, {
    subnet_name = var.dba_subnet.nic_count
  })
}

# Create NSGs for dba subnet
resource "azurerm_network_security_group" "dba_subnet" {

  # Ensure unique NSG name per application subnet to avoid collisions with existing NSGs
  name                = "${module.naming.network_security_group.name}-${var.dba_subnet.name}"
  location            = var.top_level_network.location
  resource_group_name = var.top_level_network.resource_group_name

  tags = merge(var.tags, {
    subnet = azurerm_subnet.dba_subnet.name
  })
}

# Associate NSG with the subnet.
resource "azurerm_subnet_network_security_group_association" "dba_subnet" {

  subnet_id                 = azurerm_subnet.dba_subnet.id
  network_security_group_id = azurerm_network_security_group.dba_subnet.id
}

# Add a rule for the subnet from bastion depending upon configuration
resource "azurerm_network_security_rule" "allow_deny_bastion_to_dba_subnet" {

  # Which NSG this rule belongs to (of application subnet)
  network_security_group_name = azurerm_network_security_group.dba_subnet.name

  # Rule Name
  name = "Bastion-to-${var.dba_subnet.name}"

  # Resource group
  resource_group_name = var.top_level_network.resource_group_name

  # Source and destination
  source_address_prefix      = azurerm_subnet.bastion_subnet[0].address_prefixes[0]
  destination_address_prefix = azurerm_subnet.dba_subnet.address_prefixes[0]

  # Priority
  priority               = 100
  direction              = "Inbound"
  protocol               = "*"
  source_port_range      = "*"
  destination_port_range = "*"

  # Allow or deny based on configuration
  access = (var.dba_subnet.reachable_from_bastion) ? "Allow" : "Deny"
}
