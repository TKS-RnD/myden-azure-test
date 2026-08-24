# Create a map of Subnets to NIC-IDs.
locals {
  nic_ids = [for nic in azurerm_network_interface.app_subnet_nics : nic.id]
  subnets = [for nic in azurerm_network_interface.app_subnet_nics : nic.tags["subnet_name"]]
  subnet_nic_mapping = {
    for index, key in local.subnets : key => local.nic_ids[index]...
  }
}

# Output variables so that we don't have to keep exporting the same results.
output "top_level_network" {
  value = {
    resource_group_name = var.top_level_network.resource_group_name
    name                = var.top_level_network.name
    location            = var.top_level_network.location
    bastion_host_name   = var.bastion_host_in_network.enabled ? azurerm_bastion_host.bastion_host[0].name : null
    bastion_host_dns    = var.bastion_host_in_network.enabled ? azurerm_bastion_host.bastion_host[0].dns_name : null
    app_subnet_prefixes = local.subnet_prefixes
    app_subnet_ids      = local.subnet_ids
    subnet_nic_map      = local.subnet_nic_mapping
    dba_subnet = {
      id   = azurerm_subnet.dba_subnet.id
      nics = azurerm_network_interface.dba_subnet_nics[*].id
    }
    waf_subnet = {
      id           = azurerm_subnet.waf_subnet.id
      ip           = azurerm_public_ip.waf_public_ip.ip_address
      ip_id        = azurerm_public_ip.waf_public_ip.id
      name_servers = azurerm_dns_zone.waf_zone.name_servers
      waf_domain   = var.waf_subnet.domain_name
      waf_host     = "${var.waf_subnet.host_name}.${var.waf_subnet.domain_name}"
    }
    support_subnet = {
      id   = azurerm_subnet.support_subnet.id
      nics = azurerm_network_interface.support_subnet_nics[*].id
    }
  }
}
