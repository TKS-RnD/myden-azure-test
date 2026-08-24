### Azure WAF/Edge Security Headers and Settings (for Tomcat 9.x behind WAF)

This document lists the security headers and edge settings that should be applied at the Azure edge (WAF via Front Door or Application Gateway) when the application removes app-side header injection from `web.xml`.

Scope: Headers and behaviors added at the edge so that Tomcat focuses on application logic. Tomcat is already configured with `RemoteIpValve` and container-level method restrictions; this guide complements that setup.

#### Required request/connection behavior
- Forward standard proxy headers to the app:
  - `X-Forwarded-Proto: https`
  - `X-Forwarded-Host: <original host>`
  - `X-Forwarded-For: <client ip>`
  - Do not strip or overwrite these on internal hops.
- Terminate TLS at the edge with modern ciphers/TLS versions (TLS 1.2+, prefer TLS 1.3 where supported). Disable TLS 1.0/1.1.

#### Response headers to add at the edge
- Strict-Transport-Security (set only if every entry point is HTTPS):
  - Example: `Strict-Transport-Security: max-age=31536000; includeSubDomains; preload`
  - If not all subdomains are HTTPS, remove `includeSubDomains` (and do not use `preload`).
- Content-Security-Policy (tailor to your assets/CDNs):
  - Baseline example (adjust as needed):
    - `Content-Security-Policy: default-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'self'; frame-ancestors 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'`
  - Prefer avoiding `'unsafe-inline'`; if needed, move to nonces/hashes.
- X-Content-Type-Options: `nosniff`
- Referrer-Policy: `no-referrer` or `strict-origin-when-cross-origin` (choose per analytics needs)
- Permissions-Policy: disable unused capabilities, e.g.:
  - `Permissions-Policy: accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()`
- Frame-ancestors via CSP (preferred) or X-Frame-Options:
  - If CSP in place, include `frame-ancestors 'self'`.
  - If legacy required, set `X-Frame-Options: SAMEORIGIN`.
- Remove/overwrite server identification:
  - Strip `Server`, `X-Powered-By`, `X-AspNet-Version`, `Via` where feasible.

Optional headers
- Cross-Origin-Resource-Policy (CORP): `same-origin` or `same-site` depending on deployment.
- Cross-Origin-Opener-Policy (COOP): `same-origin` (test impact).
- Cross-Origin-Embedder-Policy (COEP): `require-corp` (only if app is compatible; typically for advanced isolation needs).

Note: Do not rely on `X-XSS-Protection` (deprecated). Use CSP instead.

#### CORS and OPTIONS handling at the edge
- If the API is used cross-origin, configure CORS at the edge to respond to preflight (OPTIONS) with:
  - `Access-Control-Allow-Origin: <allowed-origin or *>`
  - `Access-Control-Allow-Methods: GET,POST,OPTIONS` (and others only if required)
  - `Access-Control-Allow-Headers: Content-Type, Authorization, ...` (minimize list)
  - `Access-Control-Allow-Credentials: true` only if strictly necessary
  - `Access-Control-Max-Age: 600` (tune as needed)
- Keep Tomcat container-level method allowlist (`GET|POST|HEAD|OPTIONS`) as configured; do not expose unsafe methods at the edge.

#### Error handling alignment
- The app maps custom error pages for: 400, 401, 403, 404, 405, 413, 414, 429, 431, 500 (+ Throwable) under `/error/*.html`.
- Configure WAF/custom rules to return neutral, nonverbose responses for blocked requests. Optionally align response codes:
  - Large body: 413
  - Rate limit: 429
  - Method not allowed (if blocked at edge): 405
  - Keep body simple HTML/JSON with no stack traces or version info.

#### Azure Front Door (Standard/Premium) — Rules Engine examples

Add a Rule Set attached to your route, with actions in this order:

1) Add/override security response headers
```
Action: Modify response header
  - Strict-Transport-Security = max-age=31536000; includeSubDomains; preload
  - Content-Security-Policy = default-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'self'; frame-ancestors 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'
  - X-Content-Type-Options = nosniff
  - Referrer-Policy = strict-origin-when-cross-origin
  - Permissions-Policy = accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()
  - X-Frame-Options = SAMEORIGIN (only if you cannot rely on CSP frame-ancestors)
  - Remove: Server, X-Powered-By, Via
```

2) CORS (if needed)
```
Action: Modify response header (conditional on request Origin)
  - Access-Control-Allow-Origin = https://example.com
  - Access-Control-Allow-Methods = GET, POST, OPTIONS
  - Access-Control-Allow-Headers = Content-Type, Authorization
  - Access-Control-Allow-Credentials = true (only if required)
  - Access-Control-Max-Age = 600
```

3) Ensure forwarding headers are set
```
Action: Modify request header
  - X-Forwarded-Proto = https (set if missing)
  - Preserve existing X-Forwarded-Host and X-Forwarded-For
```

Terraform sketch for AFD Rules Engine (pseudo — adapt into your TF module):
```
resource "azurerm_cdn_frontdoor_rule_set" "security_headers" { ... }
resource "azurerm_cdn_frontdoor_rule" "add_headers" {
  rule_set_id = azurerm_cdn_frontdoor_rule_set.security_headers.id
  action { response_header_action { header_action = "Overwrite" header_name = "Strict-Transport-Security" value = "max-age=31536000; includeSubDomains; preload" } }
  # Repeat for other headers...
}
```

#### Azure Application Gateway (v2) — Rewrite Rules examples

Create a Rewrite Rule Set and associate with the Listener/Route:

Rewrite rule: Add security headers
```
Condition: Always
Action (Response):
  - Set header Strict-Transport-Security = max-age=31536000; includeSubDomains; preload
  - Set header Content-Security-Policy = default-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'self'; frame-ancestors 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'
  - Set header X-Content-Type-Options = nosniff
  - Set header Referrer-Policy = strict-origin-when-cross-origin
  - Set header Permissions-Policy = accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()
  - Remove Server, X-Powered-By, Via (set to empty or use header removal if supported)
```

Rewrite rule: Ensure forwarded proto
```
Condition: If header "X-Forwarded-Proto" is missing
Action (Request): Set header X-Forwarded-Proto = https
```

Optional: CORS response headers (if cross-origin is required) — same values as above.

#### Size limits, throttling, and method control at edge
- Set maximum request body size to protect upstreams (e.g., 10–25 MB for typical JSON forms; larger if uploads are required). Map rejections to 413.
- Apply basic rate limiting per client/IP on sensitive endpoints (login, password reset, etc.), mapping to 429 on exceed.
- Keep allowed methods minimal in edge WAF custom rules (GET/POST/HEAD/OPTIONS) and block others, aligning with Tomcat’s `RequestFilterValve`.

#### Testing checklist
- Access site through the edge and verify headers via curl or browser devtools:
```
curl -I https://your.domain/ | sed -n '1p;/^Strict-Transport-Security/p;/^Content-Security-Policy/p;/^X-Content-Type-Options/p;/^Referrer-Policy/p;/^Permissions-Policy/p;/^X-Frame-Options/p'
```
- Confirm no duplicate/conflicting headers originate from the app after removing `HttpHeaderSecurityFilter` from `web.xml`.
- Verify cookies are `HttpOnly` and `Secure` (set in app), and `SameSite` as defined at context level if used.
- Exercise CORS preflights if applicable and check `Access-Control-*` headers.
- Trigger WAF blocks (test rules) and confirm neutral body and appropriate status codes (413/429/etc.).

#### Notes about the app layer
- Tomcat `server.xml` already configures `RemoteIpValve` (so `request.isSecure()` reflects edge HTTPS).
- Tomcat’s `RequestFilterValve` allows only `GET|POST|HEAD|OPTIONS`; keep the web tier aligned.
- In `web.xml`, keep session cookie settings and character encoding; remove app-side security header filter if headers are at the edge.
