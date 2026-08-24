# Application gateway
resource "azurerm_application_gateway" "app_gw" {

  name                = "App-Gateway"
  location            = var.location
  resource_group_name = var.resource_group

  # The gateway's identity
  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.app_gw_identity.id
    ]
  }

  # V2 SKU with one VM capacity.
  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 1
  }

  # Firewall policy id from before
  firewall_policy_id = azurerm_web_application_firewall_policy.waf_firewall_policy.id

  # Gateway's IP Configuration
  gateway_ip_configuration {
    name      = "Gateway-IPv4"
    subnet_id = var.waf_settings.front_end.subnet_id
  }

  # Front end IP address
  frontend_ip_configuration {
    name                 = "front-end-ipv4"
    public_ip_address_id = var.waf_settings.front_end.ip_address_id
  }

  # HTTP Front end port
  frontend_port {
    name = "http-port"
    port = var.waf_settings.front_end.http_port
  }

  # HTTPS Front end port
  frontend_port {
    name = "https-port"
    port = var.waf_settings.front_end.https_port
  }

  # Front end HTTP Listener
  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "front-end-ipv4"
    frontend_port_name             = "http-port"
    protocol                       = "Http"
    host_name                      = (var.waf_settings.front_end.allow_via_ip) ? (null) : (var.waf_settings.front_end.host_name)
  }

  # SSL Certificate for HTTPS listener
  ssl_certificate {
    name                = "app-gw-https-bootstrap-cert"
    key_vault_secret_id = (var.waf_settings.ssl_certificate.bootstrap_mode) ? (azurerm_key_vault_certificate.bootstrap.secret_id) : (data.azurerm_key_vault_secret.prod_certificate[0].id)
  }

  # Front end HTTPS Listener
  http_listener {
    name                           = "https-listener"
    frontend_ip_configuration_name = "front-end-ipv4"
    frontend_port_name             = "https-port"
    protocol                       = "Https"
    ssl_certificate_name           = "app-gw-https-bootstrap-cert"
    host_name                      = (var.waf_settings.front_end.allow_via_ip) ? (null) : (var.waf_settings.front_end.host_name)
  }

  # Redirect all http to https
  redirect_configuration {
    name                 = "http-to-https-redirect"
    redirect_type        = "Permanent" # Returns a 301 status code
    target_listener_name = "https-listener"
    include_path         = true
    include_query_string = true
  }

  # Default back-end HTTP Settings
  backend_http_settings {
    name                                = "default-backend-http"
    protocol                            = "Http"
    port                                = 8080
    cookie_based_affinity               = "Disabled"
    request_timeout                     = 30
    pick_host_name_from_backend_address = false
    host_name                           = var.waf_settings.front_end.host_name
  }

  # Default back-end. It is only used for http 403 errors.
  backend_address_pool {
    name         = "be-deny"
    ip_addresses = ["10.255.255.254"]
  }

  # Default 403 rewrite rule set. It throws 403 error all the time.
  rewrite_rule_set {
    name = "rewrite-deny-403"

    rewrite_rule {
      name          = "force-403"
      rule_sequence = 1

      response_header_configuration {
        header_name  = "Status"
        header_value = "403"
      }
    }
  }

  # Rewrite rule set for standard headers.
  rewrite_rule_set {
    name = "rewrite-headers"

    rewrite_rule {
      name          = "forwarded-headers"
      rule_sequence = 10

      request_header_configuration {
        header_name  = "X-Forwarded-For"
        header_value = "{var_client_ip}"
      }

      request_header_configuration {
        header_name  = "X-Forwarded-Proto"
        header_value = "http"
      }

      request_header_configuration {
        header_name  = "X-Forwarded-Host"
        header_value = var.waf_settings.front_end.host_name
      }
    }
  }

  # Health Probe for back-end apps.
  dynamic "probe" {
    for_each = var.waf_settings.back_end_apps
    content {
      name                                      = "be-health-probe-app-${probe.value.name}"
      path                                      = probe.value.health_route
      protocol                                  = "Http"
      interval                                  = 600
      timeout                                   = 30
      unhealthy_threshold                       = 3
      pick_host_name_from_backend_http_settings = true
      match {
        status_code = ["200-399"]
      }
    }
  }

  # Back end HTTP Settings for apps
  dynamic "backend_http_settings" {
    for_each = var.waf_settings.back_end_apps
    content {
      name                                = "be-http-${backend_http_settings.value.name}"
      protocol                            = "Http"
      port                                = backend_http_settings.value.port
      cookie_based_affinity               = "Disabled"
      request_timeout                     = 30
      pick_host_name_from_backend_address = false
      host_name                           = var.waf_settings.front_end.host_name
      probe_name                          = "be-health-probe-app-${backend_http_settings.value.name}"
    }
  }

  # Back end pool for apps.
  dynamic "backend_address_pool" {
    for_each = var.waf_settings.back_end_apps

    content {
      name         = "be-pool-${backend_address_pool.value.name}"
      ip_addresses = backend_address_pool.value.ip_addresses
    }
  }

  # URL Mapping for Back end(s)
  url_path_map {
    name                               = "app-path-map"
    default_backend_address_pool_name  = "be-deny"
    default_backend_http_settings_name = "default-backend-http"
    default_rewrite_rule_set_name      = "rewrite-deny-403"

    dynamic "path_rule" {
      for_each = var.waf_settings.back_end_apps

      content {
        name = "rule-for-app-${path_rule.value.name}"
        paths = [
          path_rule.value.back_route,
          "${path_rule.value.back_route}/",
          "${path_rule.value.back_route}/*"
        ]
        backend_address_pool_name  = "be-pool-${path_rule.value.name}"
        backend_http_settings_name = "be-http-${path_rule.value.name}"
        rewrite_rule_set_name      = "rewrite-headers"
      }
    }
  }

  # By default we only use a HTTPS
  request_routing_rule {
    name               = "app-path-routing"
    rule_type          = "PathBasedRouting"
    http_listener_name = "https-listener"
    url_path_map_name  = "app-path-map"
    priority           = 100
  }

  # Route all http to https
  request_routing_rule {
    name                        = "http-redirect-rule"
    rule_type                   = "Basic"
    http_listener_name          = "http-listener"
    redirect_configuration_name = "http-to-https-redirect"
    priority                    = 110
  }

  # Tags
  tags = var.tags
}
