
# subnets for various applications
resource "azurerm_subnet" "app_subnets" {

  # Iterate through subnets
  for_each = var.application_subnets

  # name and resource group.
  name                = each.key
  resource_group_name = var.top_level_network.resource_group_name

  # Under the top level subnet
  virtual_network_name = azurerm_virtual_network.top_level_network.name
  address_prefixes = [
    each.value.subnet_mask
  ]

  # Services
  service_endpoints = each.value.services_attached
}

# Transform into a list of NICs that are mapped to a subnet.
locals {
  vnet_nics = merge([
    for k, v in var.application_subnets : {
      for nic in range(0, v.nic_count) :
      "${k}_nic_${nic}" => {
        subnet_name = k
        subnet_id   = azurerm_subnet.app_subnets[k].id
        nic_index   = nic
      }
    }
  ]...)
}

# Create the Applications NICs
resource "azurerm_network_interface" "app_subnet_nics" {

  for_each = local.vnet_nics

  # The non-ip configuration block
  name                = each.key
  location            = var.top_level_network.location
  resource_group_name = var.top_level_network.resource_group_name

  # IP Configuration
  ip_configuration {
    name                          = "${each.key}-ip"
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = each.value.subnet_id
  }

  tags = merge(var.tags, {
    subnet_name = each.value.subnet_name
  })
}

# Create NSGs for application subnets
resource "azurerm_network_security_group" "app_subnets" {

  # Iterate through subnets
  for_each = var.application_subnets

  # Ensure unique NSG name per application subnet to avoid collisions with existing NSGs
  name                = "${module.naming.network_security_group.name}-${each.key}"
  location            = var.top_level_network.location
  resource_group_name = var.top_level_network.resource_group_name

  tags = merge(var.tags, {
    subnet = azurerm_subnet.app_subnets[each.key].name
  })
}

# Associate NSG with the subnet.
resource "azurerm_subnet_network_security_group_association" "app_subnets" {

  # Iterate through subnets
  for_each = var.application_subnets

  subnet_id                 = azurerm_subnet.app_subnets[each.key].id
  network_security_group_id = azurerm_network_security_group.app_subnets[each.key].id
}

# Add a rule for each subnet from bastion depending upon configuration
resource "azurerm_network_security_rule" "allow_deny_bastion_to_app_subnet" {

  # Iterate through subnets only when Bastion is enabled
  for_each = var.bastion_host_in_network.enabled ? var.application_subnets : {}

  # Which NSG this rule belongs to (of application subnet)
  network_security_group_name = azurerm_network_security_group.app_subnets[each.key].name

  # Rule Name
  name = "Bastion-to-${each.key}"

  # Resource group
  resource_group_name = var.top_level_network.resource_group_name

  # Source and destination
  source_address_prefix      = azurerm_subnet.bastion_subnet[0].address_prefixes[0]
  destination_address_prefix = azurerm_subnet.app_subnets[each.key].address_prefixes[0]

  # Priority
  priority               = 100
  direction              = "Inbound"
  protocol               = "*"
  source_port_range      = "*"
  destination_port_range = "*"

  # Allow or deny based on configuration
  access = lookup(each.value, "reachable_from_bastion", false) ? "Allow" : "Deny"
}

locals {

  // The local output that holds subnets and their address prefixes.
  subnet_prefixes = {
    for k, v in var.application_subnets : k => azurerm_subnet.app_subnets[k].address_prefixes
  }
  subnet_ids = {
    for k, v in var.application_subnets : k => azurerm_subnet.app_subnets[k].id
  }

}
