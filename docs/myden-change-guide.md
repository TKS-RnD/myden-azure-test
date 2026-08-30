# MyDen Change Guide

Where to change common things, the impact, and the risk. Paths are relative to the repo root.

Legend:
- 🟢 **Safe** — low blast radius, in-place or easily reversible.
- 🟡 **Caution** — may recreate resources or ripple across dependents.
- 🔴 **Do not change directly** — shared state/identity/backend; coordinate first.

## Change points

| Requirement | File | Variable / Block | Impact | Risk |
| --- | --- | --- | --- | --- |
| Azure region | `cloud-stack/live/staging/root.hcl` | `locals.location` | Applies to all units via inherited `location` input. New resources in new region; most existing resources **recreate**. | 🔴 |
| Environment name | `cloud-stack/live/staging/root.hcl` | `locals.environment` | Feeds names, tags, and state layout. Wide recreation. | 🔴 |
| Subscription id | `cloud-stack/live/staging/root.hcl` | `locals.azure_subscription_id` | Targets a different subscription. All resources move/recreate. | 🔴 |
| Backend / state store | `cloud-stack/live/staging/root.hcl` | `remote_state.config` (`storage_account_name`, `container_name`, `key`) | Changes where state lives; mishandling orphans/loses state. | 🔴 |
| Provider versions | `cloud-stack/live/stack-globals.hcl` | `locals.provider_versions` | Re-renders every unit's `provider_versions.tf`; may force provider upgrade behaviors. | 🟡 |
| Default tags | `cloud-stack/live/staging/root.hcl` | `locals.default_tags` | Tag-only update on most resources; usually in-place. | 🟢 |
| Resource groups (add/rename) | `cloud-stack/live/staging/base/terragrunt.hcl` | `inputs.resource_groups[]` | Renaming recreates the RG and everything referencing it by name. Adding is additive. | 🟡 |
| AD groups | `cloud-stack/live/staging/base/terragrunt.hcl` | `inputs.ad_groups[]` | **Append at bottom only** (indexed outputs). Reordering/removing shifts object-id mapping. | 🟡 |
| Managed identities / apps | `cloud-stack/live/staging/base/terragrunt.hcl` | `inputs.managed_identities[]`, `inputs.managed_applications[]` | Consumed by name/mnemonic across units. Renaming breaks consumers. | 🟡 |
| VNet / subnet CIDRs | `cloud-stack/live/staging/network/terragrunt.hcl` | `top_level_network`, `application_subnets`, `waf_subnet`, `dba_subnet`, `support_subnet` | CIDR/subnet changes recreate subnets, NICs, NSG rules; ripples to VMs. | 🟡 |
| WAF domain / host | `cloud-stack/live/staging/network/terragrunt.hcl` | `waf_subnet.domain_name`, `waf_subnet.host_name` | Changes DNS zone and WAF frontend host; app-gateway reconfigures. | 🟡 |
| Add an application subnet | `cloud-stack/live/staging/network/terragrunt.hcl` | `application_subnets` map | Additive; new subnet flows to `app_subnet_ids`/`subnet_nic_map`. | 🟢 |
| VM size | tomcat: `myden-app/tomcat-vm`; dba: `dba-vm`; support: `support/vm` | `*_vm_config.vm_size` | Resize; usually stop/start, not full recreate. | 🟡 |
| VM enable/disable | same VM units | `*_vm_config.enabled` | Toggling creates/destroys the VM and its disks. `support/vm` is currently `false`. | 🟡 |
| VM data disks | same VM units | `*_vm_config.data_disks[]` | Adding is additive; changing size/type can recreate a disk. | 🟡 |
| VM image | same VM units | `*_vm_config.custom_image` / `image` | Changing the image **recreates the VM**. | 🔴 |
| MSSQL sizing / databases | `myden-app/mssql-db/terragrunt.hcl` | `server_configuration.databases[]` (`gb_size`, retention) | DB size in-place; removing a DB destroys it. | 🟡 |
| MSSQL allowed networks/IPs | `myden-app/mssql-db/terragrunt.hcl` | `server_configuration.allowed_vnets`, `allowed_prefixes` | Firewall/VNet rule changes; in-place. | 🟢 |
| WAF firewall policy | `app-gateway/terragrunt.hcl` | `waf_settings.firewall` (mode, limits, banned_countries, bad_user_agents) | Policy update; in-place. | 🟢 |
| WAF backend routes | `app-gateway/terragrunt.hcl` | `waf_settings.back_end_apps[]` | Routing/health/CNAME changes on the gateway; in-place. | 🟡 |
| WAR storage size / IP allow-list | `war-storage/terragrunt.hcl` | `storage_size_in_gb`, `network_access_control.public_ip_mask` | Size/ACL in-place. | 🟢 |
| Rotate WAR SAS token | `war-storage/terragrunt.hcl` | `upload_control.rotate_sas_key` (increment) | Regenerates SAS secret; consumers must re-read. | 🟡 |
| CI repos allowed to push WARs | `war-storage/terragrunt.hcl` | `upload_control.github_repos`, `ssl_certificate.mi_rotation.github_repos` (app-gateway) | Federated-credential subject changes; access-only. | 🟢 |
| Module input contract | `cloud-stack/modules/<m>/inputs.tf` | `variable` blocks | Changing types/shape forces matching edits in every consuming `terragrunt.hcl`. | 🔴 |
| Module outputs | `cloud-stack/modules/<m>/outputs.tf` | `output` blocks | Renaming/removing breaks `dependency.*.outputs.*` in consumers **and** their mocks. | 🔴 |
| Module dependency wiring | any unit `terragrunt.hcl` | `dependency` blocks (`config_path`, `mock_outputs`) | Wrong `config_path` or stale mocks break `plan`/`run-all` ordering. | 🟡 |

## Notes

- `mock_outputs` must mirror the **real** module output shape; incomplete mocks fail `plan`/`validate` (the class of bug fixed in this audit).
- After changing any cross-unit output name, update both the producing `outputs.tf` and every consumer's `dependency` reference and `mock_outputs`.
- Never edit generated files (`provider.tf`, `provider_versions.tf`, `.terraform.lock.hcl`) by hand; they are regenerated by Terragrunt.
