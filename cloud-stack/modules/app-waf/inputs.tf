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

# Location
variable "location" {
  type        = string
  description = "Location"
}

# Resource group name
variable "resource_group" {
  type        = string
  description = "Resource Group Name"
}

# WAF related configuration
variable "waf_settings" {
  description = "WAF Settings"

  type = object({

    # Firewall object
    firewall = object({
      mode                 = string       # Prevention or blocking
      max_body_size_kb     = number       # Body Size Max in KB
      file_upload_limit_mb = number       # File Upload limit in MB
      app_networks         = list(string) # Traffic is allowed from these App networks for back-haul.
      bad_user_agents      = list(string) # Malicious known user agents.
      banned_countries     = list(string) # List of countries from where traffic is banned.
    })

    # Front End part of the WAF.
    front_end = object({
      subnet_id     = string           # Subnet ID where it has to be placed.
      ip_address    = string           # IP Address of the WAF.
      ip_address_id = string           # IP Address ID of the WAF.
      domain_name   = string           # Domain name.
      host_name     = string           # Host name of the WAF
      allow_via_ip  = bool             # Should WAF allow access via IP Address to back ends?
      http_port     = number           # HTTP Port number
      https_port    = optional(number) # HTTPS Port number
    })

    # WAF Certificate management.
    ssl_certificate = object({
      key_vault_name         = string # Name of the Key vault where the certificate is stored.
      secret_name_bootstrap  = string # Name of the secret where the seed certificate is stored.
      secret_name_production = string # Name of the secret where the production certificate is stored.
      bootstrap_mode         = bool   # Which mode to use the certificate currently.
      mi_rotation = object({          # Which GitHub Repos will be allowed to rotate the Certificate?
        id             = string       # Managed Identity to be used for rotating the certificate.
        principal_id   = string       # Managed Identity to be used for rotating the certificate.
        resource_group = string       # Resource group of the Managed Identity
        github_repos   = list(string) # List of repositories that can rotate the certificate.
      })
    })

    # Back end apps of the WAF
    back_end_apps = list(object({
      name         = string       # Name of the App
      ip_addresses = list(string) # List of IP Addresses where the app is running.
      port         = number       # Port where the application is listening.
      health_route = string       # Health Check route.
      back_route   = string       # Route in which the app exists, in the back end.
      front_route  = string       # Front end route for the app. May result in rewrite rule being emitted!
      dns_cname    = bool         # Should we add DNS routing, so that app.dns will result in routing?
    }))
  })
}
