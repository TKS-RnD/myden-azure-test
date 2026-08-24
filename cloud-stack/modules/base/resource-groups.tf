
# Create our own resource group.
locals {
  purpose = "base"
  name    = "rg-base-${var.environment}"
}
resource "azurerm_resource_group" "own" {
  location   = var.location
  name       = local.name
  managed_by = "Terragrunt"
  tags = merge(var.tags, {
    purpose = local.purpose
  })
}

# Create the resource groups.
resource "azurerm_resource_group" "baseline" {
  count      = length(var.resource_groups)
  location   = var.location
  name       = var.resource_groups[count.index].name
  managed_by = "Terragrunt"
  tags = merge(var.tags, {
    purpose = var.resource_groups[count.index].purpose
  })
}
