# Subnet for Bastion Host (mandatory name: Azure requires "AzureBastionSubnet")
resource "azurerm_subnet" "bastion_subnet" {

  # Only do if bastion host is desired
  count = var.bastion_host_in_network.enabled ? 1 : 0

  # Other parameters
  name                = "AzureBastionSubnet"
  resource_group_name = var.top_level_network.resource_group_name

  # Under the top level subnet
  virtual_network_name = azurerm_virtual_network.top_level_network.name
  address_prefixes = [
    var.bastion_host_in_network.subnet_mask
  ]
}

# Public ip for Bastion Host
resource "azurerm_public_ip" "bastion_public_ip" {

  # Only do if bastion host is desired
  count = var.bastion_host_in_network.enabled ? 1 : 0

  # Other parameters
  name                = module.naming.public_ip.name
  location            = var.top_level_network.location
  resource_group_name = var.top_level_network.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = merge(var.tags, {
    bastion = "true"
  })
}

# And the bastion host
resource "azurerm_bastion_host" "bastion_host" {

  # Only do if bastion host is desired
  count = var.bastion_host_in_network.enabled ? 1 : 0

  name                = module.naming.bastion_host.name_unique
  location            = var.top_level_network.location
  resource_group_name = var.top_level_network.resource_group_name

  ip_configuration {
    name                 = "${azurerm_public_ip.bastion_public_ip[count.index].name}-config"
    subnet_id            = azurerm_subnet.bastion_subnet[count.index].id
    public_ip_address_id = azurerm_public_ip.bastion_public_ip[count.index].id
  }

  tags = merge(var.tags, {
    bastion = "true"
  })
}

# Often one needs to give AD groups access to the bastion host. This is done via a Hidden RDP group which has these
# AD groups has members.
resource "azuread_group" "bastion_access_ad_group" {

  display_name               = "Bastion Access Group"
  description                = "AD Group that can access the Bastion"
  prevent_duplicate_names    = true
  security_enabled           = true
  mail_enabled               = false
  external_senders_allowed   = false
  auto_subscribe_new_members = false

  # members
  members = values(var.bastion_host_in_network.ad_groups)

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

# Assign this group to have read access to bastion host
resource "azurerm_role_assignment" "bastion_ad_group_reader" {

  # Only do if bastion host is desired
  count = var.bastion_host_in_network.enabled ? 1 : 0

  scope                = azurerm_bastion_host.bastion_host[count.index].id
  role_definition_name = "Reader"
  principal_id         = azuread_group.bastion_access_ad_group.object_id
}

# Add Reader role to top level subnet for those groups that need AAD login access.
resource "azurerm_role_assignment" "network_reader_ad_group_access" {

  # Iterate through and all groups to get network reader access.
  for_each = var.bastion_host_in_network.ad_groups

  principal_id         = each.value
  scope                = azurerm_virtual_network.top_level_network.id
  role_definition_name = "Reader"
}
