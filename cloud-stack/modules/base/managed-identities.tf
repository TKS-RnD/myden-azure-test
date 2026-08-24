# Managed Identities for everyone!
resource "azurerm_user_assigned_identity" "vm_identity" {
  count = length(var.managed_identities)

  name                = var.managed_identities[count.index].name
  resource_group_name = azurerm_resource_group.own.name
  location            = var.location
  tags = merge(var.tags, {
    mnemonic    = var.managed_identities[count.index].mnemonic
    description = var.managed_identities[count.index].description
  })
}
