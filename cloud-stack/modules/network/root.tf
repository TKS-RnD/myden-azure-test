
# Use the naming module.
module "naming" {
  source = "Azure/naming/azurerm"
  suffix = [
    var.environment
  ]
}

# Network Base. Contains all top level network related recipes.
resource "azurerm_virtual_network" "top_level_network" {

  # Name
  name = var.top_level_network.name

  # Location and Resource group
  location            = var.top_level_network.location
  resource_group_name = var.top_level_network.resource_group_name

  # Address space
  address_space = [
    var.top_level_network.subnet_mask
  ]

  # Tags
  tags = var.tags
}
