# MyDen Dependency Matrix

One row per Terragrunt unit (staging). "Depends On" lists the explicit Terragrunt `dependency` blocks. Inputs/Outputs list the meaningful cross-unit contract only.

| Unit / Module | Purpose | Depends On | Key Inputs (from deps) | Key Outputs | Used By |
| --- | --- | --- | --- | --- | --- |
| `base` (`modules/base`) | Resource groups, AD groups, managed identities, managed applications | — | none (root common inputs only) | `resource_groups`, `ad_groups`, `ad_groups_rdp_access`, `managed_identities`, `managed_applications` | network, war-storage, vault, log-storage, mssql, tomcat-vm, dba-vm, support-vm, app-gateway |
| `network` (`modules/network`) | VNet, subnets, NICs, NSGs, Bastion, WAF public IP, DNS zone | base | `top_level_network.resource_group_name` = `base.resource_groups[network]`; `ad_groups_rdp_access` | `top_level_network.{app_subnet_ids, app_subnet_prefixes, subnet_nic_map, waf_subnet(id,ip,ip_id,name_servers,waf_domain,waf_host), dba_subnet, support_subnet, bastion_*}` | war-storage, log-storage, mssql, tomcat-vm, dba-vm, support-vm, app-gateway |
| `vault-vm-break-glass` (`modules/vault-vm-break-glass`) | Break-glass Key Vault | base | `resource_groups[vault]`, `ad_groups[Azure App VM Administrators]` | `break_glass_keyvault.{id, name, resource_group_name, location, ad_admin_group_access}` | tomcat-vm, dba-vm, support-vm |
| `war-storage` (`modules/war-storage`) | WAR file storage, upload/mount Key Vaults, SAS, Log Analytics | base, network | `resource_group_names`, `network_access_control.app_subnet_ids`, `managed_identities[Application VM/GitHub-War-Pusher]`, `managed_applications[Jenkins-War-Pusher]` | `shares`, `keyvault.{name, secret_names.for_mounting_vms}`, `github`, `jenkins`, `log_analytics_workspace_id` | tomcat-vm |
| `support/log-storage` (`modules/log-storage`) | Log storage account + container + RBAC | base, network | `resource_groups[support]`, `network.app_subnet_ids` + `support_subnet.id`, `managed_identities[Application VM/Support Desktop VM]`, `ad_groups[Support Personnel]` | `shares.{storage_account_name, resource_group, container_name, mi_readers, mi_writers}` | support/vm |
| `myden-app/mssql-db` (`modules/mssql-serverless`) | MSSQL server + databases + firewall/VNet rules | base, network | `resource_groups[databases]`, `ad_groups[Azure Database Administrators]`, `network.app_subnet_ids[my_den]` | (none consumed cross-unit) | — |
| `myden-app/tomcat-vm` (`modules/windows-app-vm`) | Windows Tomcat app VM | base, network, war-storage, vault-vm-break-glass | `resource_groups[app-vms]`, subnet id + `subnet_nic_map[my_den]`, war `shares`/`keyvault`, `break_glass_keyvault.id`, `managed_identities`, `ad_groups` | `vm_data.{ip_addresses, machine_name}` | app-gateway |
| `dba-vm` (`modules/dba-access-vm`) | DBA Windows VM + Key Vault + storage | base, network, vault-vm-break-glass | `resource_groups[dba/vault]`, `dba_subnet.{id,nics}`, `ad_groups`, `managed_identities`, `break_glass_keyvault.id` | (none consumed cross-unit) | — |
| `support/vm` (`modules/support-vm`) | Support Windows VM (`enabled=false`) | base, network, vault-vm-break-glass, log-storage | `resource_groups[support]`, `support_subnet.{id,nics}`, log `shares`, `break_glass_keyvault.id`, identities/groups | `vm_data.{ip_addresses, machine_name}` | — |
| `app-gateway` (`modules/app-waf`) | Application Gateway WAF + firewall policy + certs + DNS | network, base, tomcat-vm | `network.waf_subnet.*` + `app_subnet_prefixes`, `managed_identities[GitHub-Cert-Rotator]`, tomcat `vm_data` | (none consumed cross-unit) | — |
| `myden-app`, `support` (`modules/_noop`) | Grouping units for `run-all` traversal | — | none | `noop` | — |

## Dependency observations

- **No circular dependencies.** The graph is a DAG rooted at `base` → `network`.
- **Terminal (leaf) units:** `mssql-db`, `dba-vm`, `support/vm`, `app-gateway` — nothing consumes their outputs.
- **Hubs:** `base` (used by all) and `network` (used by all resource-bearing units except vault).
- **All ordering is explicit** via `dependency` blocks; no `dependencies` path lists and no in-module cross-unit `depends_on`.
- `app-gateway` → `tomcat-vm` is the only VM-to-gateway output link (`vm_data` feeds the WAF backend pool).
