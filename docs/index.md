# MyDen Repository Index

A folder-by-folder record of the repository. Each section has two parts:

- **Reuse variables** — what you must change to run this in another project/tenant/subscription, with exact file paths.
- **Functionality** — what the folder, `terragrunt.hcl`, or Packer file actually does.

All paths are relative to the repo root. Never hand-edit generated files (`provider.tf`, `provider_versions.tf`, `.terraform.lock.hcl`) — Terragrunt/Terraform regenerate them.

---

## Global values repeated across the repo (change these first)

These identifiers are hard-coded in multiple files. When reusing for another project, search-and-replace all of them:

| Value | Current setting | Where it appears |
| --- | --- | --- |
| Azure subscription ID | `d32407a7-5c5f-4491-ad3a-f2731fec7b4d` | `cloud-stack/live/staging/root.hcl` (`locals.azure_subscription_id`); `bootstrap/*/staging.tfvars`, `prod.tfvars`, `uat.tfvars`; `single-sign-on/staging.tfvars`, `prod.tfvars`; `vm-images/packer/*/staging.pkvars.hcl` |
| Azure tenant ID | `140753de-dfb5-47e7-a884-77644f9205bf` | `vm-images/packer/*/staging.pkvars.hcl` |
| Azure region | `centralindia` | `cloud-stack/live/staging/root.hcl` (`locals.location`); custom-image blocks in `dba-vm`, `tomcat-vm`, `support/vm` terragrunt files; Packer `inputs.pkr.hcl` defaults |
| TF state backend | RG `rg-tfstate`, storage `tfstate7shrl`, container `tfstate` | `cloud-stack/live/staging/root.hcl` (`remote_state`); every `bootstrap/*/azurerm.*.tfbackend`; `single-sign-on/azurerm.*.tfbackend` |
| Azure AD tenant domain | `Denave064.onmicrosoft.com` | `bootstrap/intermediate-proxy-app/staging.tfvars`, `bootstrap/terraform-administrator/staging.tfvars` (owner/user lists) |
| Golden-image RG | `golden-images` | `vm-images/packer/*/staging.pkvars.hcl`; custom-image blocks in VM terragrunt units |
| Environment name | `staging` | `cloud-stack/live/staging/root.hcl` (`locals.environment`), inherited everywhere via `include.env` |

---

## `bootstrap/` — one-time tenant/identity setup

Provisioned once per tenant before the main stack. Own Terraform roots (not Terragrunt), each with its own `.tfbackend`.

### `bootstrap/intermediate-proxy-app/`
**Reuse variables**
- `terraform.tfvars` — `azure_cli_proxy_app-name`, `azure_cli_proxy_app_description`, `azure_cli_proxy_app_permissions` (Graph permissions requiring admin consent).
- `staging.tfvars` / `prod.tfvars` / `uat.tfvars` — `azure_subscription_id`, `azure_cli_proxy_app_owners` (UPNs on `@Denave064.onmicrosoft.com`).
- `azurerm.<env>.tfbackend` — state backend location + `key`.

**Functionality** — Creates the intermediate Azure AD app used to bootstrap Terraform (grants Graph permissions for Conditional Access, PIM, Role Management, Application read). `app.tf` defines the app + permissions; `inputs.tf`/`outputs.tf` the contract; `provider.tf` the AzureAD/AzureRM providers.

### `bootstrap/terraform-administrator/`
**Reuse variables**
- `terraform.tfvars` — `terraform-admin-role-name`, `terraform-admin-group-name`, `terraform-admin-ad-group-builtin-roles`.
- `staging.tfvars` — `azure_subscription_id`, `terraform-builtin-roles-users` (UPN map), `proxy_app_workspace` (state pointer to the proxy app), `terraform-admin-group-eligible-users`, `resource_groups_owner_access` (e.g. `myden-staging`).
- `azurerm.<env>.tfbackend` — state backend.

**Functionality** — Defines the Terraform Administrator custom role and AD group, assigns built-in roles, and wires PIM eligibility. `group.tf`/`group-role.tf`/`user-role.tf` handle group + role assignment; `cas-policy.tf` Conditional Access; `inputs.tf` the variables.

### `bootstrap/ps-scripts/`
**Reuse variables** — Parameters passed at runtime (UPNs, group names); no hard-coded project IDs. Review before use.
**Functionality** — PowerShell operations helpers: `activate-pim-group.ps1`, `activate-pim-role.ps1` (PIM activation), `create-new-user.ps1`, `remove-user.ps1`, `create-tf-state-bucket.ps1` (provisions the TF state storage account), `manage-security-attributes.ps1`, `set-security-defaults.ps1`.

---

## `cloud-stack/` — the main Terragrunt + Terraform stack

### `cloud-stack/live/` — environment roots
**Reuse variables**
- `stack-globals.hcl` — `provider_versions` map (terraform/azurerm/random/azuread/time/tls pins). Change to upgrade providers across every unit.
- `staging/root.hcl` — `locals.environment`, `locals.location`, `locals.azure_subscription_id`, `locals.default_tags`, and the `remote_state` backend block. This is the single most important reuse file: it feeds names, tags, state layout, region, and subscription to all units.

**Functionality** — `root.hcl` generates each unit's `provider.tf` and `provider_versions.tf`, sets the azurerm backend, and injects common inputs (`environment`, `location`, `tags`). `stack-globals.hcl` centralizes version pins.

### `cloud-stack/live/staging/<unit>/terragrunt.hcl` — deployable units

| Unit | Functionality | Key reuse inputs (in that `terragrunt.hcl`) |
| --- | --- | --- |
| `base` | Resource groups, AD groups, managed identities, managed applications (foundation for all units) | `resource_groups[]` names/purposes, `ad_groups[]` (**append only** — indexed outputs), `managed_identities[]`, `managed_applications[]` |
| `network` | VNet, subnets (app/waf/dba/support), NICs, NSGs, Bastion, WAF public IP, DNS zone | `top_level_network.subnet_mask` (`192.168.0.0/16`), `application_subnets`, `waf_subnet.domain_name` (`az-staging.denuds.com`), `dba_subnet`, `support_subnet`, `bastion_host_in_network` |
| `vault-vm-break-glass` | Break-glass Key Vault for VM admin passwords | `keyvault_name`, `ad_group_name` (`Azure App VM Administrators`) |
| `war-storage` | WAR file storage account, upload/mount Key Vaults, SAS token, Log Analytics, GitHub/Jenkins push access | `storage_account_name` (`denave1war1staging`), `storage_size_in_gb`, `network_access_control.public_ip_mask` (allow-list IPs), `upload_control.github_repos`, `rotate_sas_key`, `azure_third_party_networks` (subscription/RG/VNet) |
| `support/log-storage` | Log storage account + container + RBAC for support | `storage_account_name` (`denave1support1staging`), reader/writer identities, `ad_groups_reader` (`Support Personnel`) |
| `myden-app/mssql-db` | Serverless MSSQL server + databases + firewall/VNet rules | `server_configuration.name`, `databases[]` (`gb_size`, retention), `allowed_prefixes`, `allowed_vnets`, `break_glass_admin_user` |
| `myden-app/tomcat-vm` | Windows Tomcat app VM, data disks, WAR share mount, AAD join | `app_vm_config.enabled`, `vm_name` (`myden-tomcat`), `vm_size`, `data_disks[]`, `image.custom_image.name` (`win2022-tomcat-base`) + RG (`golden-images`), `war_storage.local_drive` |
| `dba-vm` | DBA Windows VM + Key Vault + storage workspace | `storage_workspace.storage_account_name` (`denave1dba1staging`), `dba_keyvault.name`, `dba_vm_config` (`vm_name`, `vm_size`, `custom_image`=`win2022-server-dba-desktop`, `daily_shutdown_time`) |
| `support/vm` | Support Windows VM (**currently `enabled = false`**) | `support_vm_config.enabled`, `vm_name` (`support-vm`), `vm_size`, `custom_image`, `daily_shutdown_time` |
| `app-gateway` | Application Gateway WAF, firewall policy, SSL certs, DNS backend routing | `waf_settings.firewall` (mode, limits, `banned_countries`, `bad_user_agents`), `front_end` (ports), `ssl_certificate.key_vault_name` + `mi_rotation.github_repos`, `back_end_apps[]` (routes/health/port `8080`), `diagnostics_settings` |
| `myden-app`, `support` | Grouping units pointing at `modules/_noop` (let `run-all` traverse nested units) | none |

> Every unit uses `mock_outputs` in its `dependency` blocks so `plan`/`validate` work standalone. Mocks must mirror the real module `outputs.tf` shape — the class of bug fixed in the Aug 30 audit.

### `cloud-stack/modules/` — reusable Terraform modules
**Reuse variables** — Module inputs live in each `inputs.tf`; changing input types/shape forces matching edits in every consuming `terragrunt.hcl`, and changing `outputs.tf` breaks consumers' `dependency.*` refs and their mocks. Treat as a contract.
**Functionality** by module:
- `base` — RGs, AD groups, managed identities/applications, storage data-plane access.
- `network` — app/waf/dba/support subnets, bastion host, NSGs, DNS.
- `app-waf` — App Gateway, firewall policy, bootstrap + rotation certs.
- `dba-access-vm` / `windows-app-vm` / `support-vm` — Windows VMs (disks, key-vault, AD-group access).
- `mssql-serverless` — SQL server + databases.
- `war-storage` — WAR storage, GitHub/Jenkins access, key vaults, monitoring.
- `log-storage` — log storage account + outputs.
- `vault-vm-break-glass` / `vm-data-store` — key vaults + data store.
- `_noop` — empty module for grouping units.

---

## `single-sign-on/` — GCP ↔ Azure AD workforce SSO
**Reuse variables**
- `staging.tfvars` / `prod.tfvars` — `azure_subscription_id`, `gcp_domain_name` (`riskstrat.in`), `gcp_pool_id` (`all-users`), `gcp_provider_id` (`azure-ad-global-provider`).
- `terraform.tfvars` — `azure_ad_app_default_scopes` (`openid`, `email`, `profile`).
- `azurerm.<env>.tfbackend` — state backend (`key = azure-poc/single-sign-on`).
- `gcp-sso-app.tf` — `display_name`, redirect URIs, `sign_in_audience` (`AzureADMyOrg`).

**Functionality** — Creates the Azure AD application + service principal for GCP Workforce Identity Federation, grants Graph scopes, rotates the client secret every 6 months, and wires the GCP workforce pool provider (`gcp-worker-pool.tf`).

---

## `vm-images/` — Packer golden images + provisioning

### `vm-images/packer/win2022-server-azure/`
**Reuse variables**
- `staging.pkvars.hcl` — `subscription_id`, `tenant_id`, `resource_group_name` (`golden-images`).
- `inputs.pkr.hcl` defaults — `location`, `image_sku`, `vm_size`, `managed_image_prefix` (`win2022-tomcat-base`), `openjdk_version` (`openjdk17`), `tomcat_version` (`9.0.89`), source-path vars.

**Functionality** — `windows-2022-azure.pkr.hcl` builds the Windows Server 2022 + JDK 17 + Tomcat 9.0.89 golden image, running the PowerShell scripts under `vm-images/ps-scripts/`.

### `vm-images/packer/win2022-server-dba-desktop/`
**Reuse variables** — `staging.pkvars.hcl` (`subscription_id`, `tenant_id`, `resource_group_name`); `inputs.pkr.hcl` defaults (`managed_image_name` = `win2022-server-dba-desktop`, `image_sku`, `vm_size`).
**Functionality** — `win2022-server-dba-azure.pkr.hcl` builds the DBA desktop golden image with DBA tooling (`choco-packages.txt`, `first-boot-dba-tweaks.ps1`).

### `vm-images/ps-scripts/`
**Reuse variables** — Package lists (`choco-packages.txt`, `ps-modules.txt`); reference paths inside VM (`C:\Scripts\Packer-Provision\...`) must match the `existing_scripts` lists in the VM terragrunt units.
**Functionality** — `common/` bootstrap (choco installer, PS modules, drive mounts, server tweaks); `win2022-server-azure/` Tomcat install, WAR-mount drive task, WAR-deploy service; `win2022-server-dba-desktop/` DBA tweaks.

### `vm-images/tomcat/` and `vm-images/myden-config/`
**Reuse variables** — `myden-config/newMyDenApp.properties` (app connection/config), `log4j2.xml`; `tomcat/server.xml`, `web.xml`, `tomcat-users.xml`, WAF edge headers doc, error pages.
**Functionality** — Baked-in Tomcat configuration and MyDen app config/error pages used by the golden image.

---

## `myden-app/vm-image/` — app-side image assets (Jenkins/Tomcat)
**Reuse variables** — `Jenkins/pom.xml` (build coordinates), Tomcat conf under `apache-tomcat-9.0.89/Conf/` (`server.xml`, `tomcat-users.xml`, `web.xml`).
**Functionality** — Reference Jenkins build (`pom.xml`) and a full Tomcat 9.0.89 config tree (server config, manager app, ROOT error/favicon) used when producing the app image.

---

## `scripts/shell/`
**Reuse variables** — Passed at runtime: `--domain`, `--vault`, `--name`, `--email`, `--expiry`; env `AZUREDNS_SUBSCRIPTIONID`, `AZUREDNS_TENANTID`.
**Functionality** — `rotate-cert.sh` issues/renews a Let's Encrypt wildcard cert via acme.sh (Azure DNS challenge) and imports the PFX into a Key Vault. Used by the App Gateway WAF cert rotation flow.

---

## `docs/`
**Functionality** — `myden-infrastructure-flow.md` (architecture + Mermaid flow), `myden-dependency-matrix.md` (per-unit dependency table), `myden-change-guide.md` (where-to-change + risk ratings), and this `index.md`.
