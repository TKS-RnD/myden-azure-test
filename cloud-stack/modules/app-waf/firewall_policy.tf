# Only Firewall policy.
resource "azurerm_web_application_firewall_policy" "waf_firewall_policy" {
  name                = "waf-policy-${var.environment}"
  resource_group_name = var.resource_group
  location            = var.location

  # GLOBAL POLICY SETTINGS
  policy_settings {
    enabled                     = true
    mode                        = var.waf_settings.firewall.mode
    request_body_check          = true
    max_request_body_size_in_kb = var.waf_settings.firewall.max_body_size_kb
    file_upload_limit_in_mb     = var.waf_settings.firewall.file_upload_limit_mb
  }

  # MANAGED RULES (OWASP CRS)
  managed_rules {

    # --- Required real-world exclusions ---
    exclusion {
      match_variable          = "RequestHeaderNames"
      selector_match_operator = "Equals"
      selector                = "Authorization"
    }

    exclusion {
      match_variable          = "RequestArgNames"
      selector_match_operator = "Equals"
      selector                = "password"
    }

    exclusion {
      match_variable          = "RequestArgNames"
      selector_match_operator = "Equals"
      selector                = "token"
    }

    exclusion {
      match_variable          = "RequestArgNames"
      selector_match_operator = "Equals"
      selector                = "authorization"
    }

    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
  }

  # 1. Allow trusted internal networks (highest priority)
  custom_rules {
    name      = "AllowTrustedNetworks"
    priority  = 1
    rule_type = "MatchRule"
    action    = "Allow"

    match_conditions {
      match_variables {
        variable_name = "RemoteAddr"
      }

      operator     = "IPMatch"
      match_values = var.waf_settings.firewall.app_networks
    }
  }

  # 2. Rate limit anonymous / internet traffic
  # CAF: protect availability (DoS-lite protection)
  custom_rules {
    name      = "RateLimitRequests"
    priority  = 5
    rule_type = "RateLimitRule"
    action    = "Block"

    rate_limit_duration  = "OneMin"
    rate_limit_threshold = 300
    group_rate_limit_by  = "ClientAddr"

    match_conditions {
      match_variables {
        variable_name = "RemoteAddr"
      }

      operator     = "IPMatch"
      match_values = ["0.0.0.0/0"]
    }
  }

  # 3. Block common scanners and exploit frameworks
  custom_rules {
    name      = "BlockMaliciousUserAgents"
    priority  = 10
    rule_type = "MatchRule"
    action    = "Block"

    match_conditions {
      match_variables {
        variable_name = "RequestHeaders"
        selector      = "User-Agent"
      }
      operator     = "Contains"
      match_values = var.waf_settings.firewall.bad_user_agents
    }
  }

  # 4. Geo-block regions with no business presence (CAF: reduce attack surface)
  custom_rules {
    name      = "BlockUntrustedGeos"
    priority  = 20
    rule_type = "MatchRule"
    action    = "Block"

    match_conditions {
      match_variables {
        variable_name = "RemoteAddr"
      }

      operator     = "GeoMatch"
      match_values = var.waf_settings.firewall.banned_countries
    }
  }

  #
  # 5. Default allow for internet traffic (since it is a public WAF)
  #
  custom_rules {
    name      = "AllowInternetTraffic"
    priority  = 100
    rule_type = "MatchRule"
    action    = "Allow"

    match_conditions {
      match_variables {
        variable_name = "RemoteAddr"
      }

      operator     = "IPMatch"
      match_values = ["0.0.0.0/0"]
    }
  }

  # Tags
  tags = var.tags
}
