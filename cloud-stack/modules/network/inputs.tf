# Environment
variable "environment" {
  type        = string
  description = "Environment in which is deployed"
}

# Default Tags
variable "tags" {
  type        = map(string)
  description = "Default Tags"
}

# Top level network.
variable "top_level_network" {
  type = object({
    name                = string # Name of the Virtual Network.
    subnet_mask         = string # Subnet Mask of the Virtual Network.
    resource_group_name = string # Name of the resource group.
    location            = string # Location of the Resource group.
  })
  description = "Top level network settings"
}

# Bastion host related
variable "bastion_host_in_network" {
  type = object({
    subnet_mask = string      # Bastion Subnet mask.
    enabled     = bool        # Should enable Bastion host related functionality or not
    ad_groups   = map(string) # AD Groups that need access to bastion host.
  })
  description = "Bastion Host network settings"
}

# Web Application Firewall subnet and host related.
variable "waf_subnet" {
  type = object({
    subnet_name = string # Subnet name
    subnet_mask = string # WAF Subnet
    host_name   = string # WAF hostname.
    domain_name = string # Sub-domain under which the WAF should reside.
  })
}

# Application subnets
variable "application_subnets" {
  type = map(object({
    subnet_mask            = string       # Application subnet mask
    nic_count              = number       # NICs that needs to be created for Apps.
    reachable_from_bastion = bool         # Can bastion subnet connect to this network?
    reachable_from_waf     = bool         # Can WAF sub-net connect to this network?
    services_attached      = list(string) # List of services attached to this subnet.
  }))
  description = "Details about Application Subnets"
}

# DBA subnet
variable "dba_subnet" {
  type = object({
    name                   = string
    subnet_mask            = string       # DBA Subnet mask.
    nic_count              = number       # NICs that needs to be created for VMs.
    reachable_from_bastion = bool         # Can bastion subnet connect to this network?
    services_attached      = list(string) # List of services attached to this subnet.
  })
  description = "Database Administrator subnet"
}

# Support subnet
variable "support_subnet" {
  type = object({
    name                      = string
    subnet_mask               = string       # DBA Subnet mask.
    nic_count                 = number       # NICs that needs to be created for VMs.
    reachable_from_bastion    = bool         # Can bastion subnet connect to this network?
    reachable_from_app_subnet = bool         # Should this subnet be reachable from apps?
    reachable_from_dba_subnet = bool         # Should this subnet be reachable from dba vms?
    services_attached         = list(string) # List of services attached to this subnet.
  })
  description = "Database Administrator subnet"
}
