# Functional Specification Document (FSD)

**Project:** MyDen Azure Cloud Platform
**Companion to:** [BRD](brd.md)
**Scope:** How the infrastructure-as-code in this repository functionally delivers the business requirements.

This document describes system components, their behavior, interfaces, and the flows that satisfy each business requirement (BR-x from the BRD). It is reconstructed from the current repository (Terraform modules, Terragrunt units, Packer builds, PowerShell, and shell scripts).

---

## 1. System overview

The platform is delivered in four functional subsystems:

1. **Bootstrap** (`bootstrap/`) — establishes the ability to run Terraform safely (state, proxy app, admin role/PIM).
2. **Cloud stack** (`cloud-stack/`) — the MyDen application environment, built from reusable Terraform modules orchestrated by Terragrunt.
3. **Golden images** (`vm-images/`) — Packer-built Windows Server 2022 images for app and DBA VMs.
4. **Single sign-on** (`single-sign-on/`) — Azure AD ↔ GCP Workforce Identity federation.

Tooling: Terraform **1.13.2**, Terragrunt **0.93.0**, OpenTofu 1.10.6 (optional), Packer (Azure plugin ≥ 1.5.0), Azure CLI, PowerShell Core, Google Cloud CLI. Versions are pinned centrally (`.tool-versions`, `stack-globals.hcl`) — satisfies **BR-14**.

---

## 2. Subsystem: Bootstrap

### 2.1 TF state backend — `bootstrap/ps-scripts/create-tf-state-bucket.ps1`
- **Function:** Interactively creates resource group `rg-tfstate`, storage account `tfstate7shrl`, and container `tfstate`, and applies a lifecycle policy.
- **Interface:** `pwsh create-tf-state-bucket.ps1` (prompts for RG/account/container/location).
- **Satisfies:** BR-2 (central state store).

### 2.2 Intermediate proxy app — `bootstrap/intermediate-proxy-app/`
- **Function:** Creates an Azure AD application (`app.tf`) with the Graph permissions Terraform's AzureAD provider needs (Conditional Access, PIM, Role Management, Application read — `terraform.tfvars`).
- **Interface:** `terraform init -backend-config=azurerm.<env>.tfbackend -var-file=<env>.tfvars` → `apply`.
- **Behavior note:** New permissions require manual Global Admin consent.
- **Satisfies:** BR-1, and enables BR-3.

### 2.3 Terraform Administrator — `bootstrap/terraform-administrator/`
- **Function:** Defines a custom role (`user-role.tf`), an assignable AD group (`group.tf`, `group-role.tf`), Conditional Access policy (`cas-policy.tf`), and PIM eligibility; scopes owner access to named resource groups (`resource_groups_owner_access`).
- **Interface:** standard Terraform 2-liner; PIM activation via `activate-pim-group.ps1` / `activate-pim-role.ps1`.
- **Satisfies:** BR-3 (PIM/JIT), BR-4 (RG-scoped admin).

### 2.4 Operational scripts — `bootstrap/ps-scripts/`
- User lifecycle (`create-new-user.ps1`, `remove-user.ps1`), PIM activation, security attributes/defaults.

---

## 3. Subsystem: Cloud stack

### 3.1 Orchestration model
- **`cloud-stack/live/staging/root.hcl`** generates each unit's `provider.tf` + `provider_versions.tf`, configures the azurerm backend (per-unit state key via `path_relative_to_include()`), and injects common inputs (`environment`, `location`, `tags`). Satisfies BR-2, BR-13, BR-14.
- **`cloud-stack/live/stack-globals.hcl`** pins provider versions.
- Each **unit** is a directory with a `terragrunt.hcl` that sets `terraform.source` to a module in `cloud-stack/modules/` and wires cross-unit data via `dependency` blocks (with `mock_outputs` for standalone `plan`/`validate`).

### 3.2 Functional units

| Unit | Module | Function | Satisfies |
| --- | --- | --- | --- |
| `base` | `modules/base` | Resource groups, AD groups, managed identities, managed applications. | BR-7 |
| `network` | `modules/network` | VNet `192.168.0.0/16`; app/WAF/DBA/support subnets; bastion; WAF public IP; DNS zone; NSGs with controlled reachability. | BR-6 |
| `vault-vm-break-glass` | `modules/vault-vm-break-glass` | Break-glass Key Vault holding VM admin passwords, access-restricted to VM admin AD group. | BR-7 |
| `war-storage` | `modules/war-storage` | WAR artifact storage + file share; upload & mount Key Vaults; SAS token (rotatable); GitHub/Jenkins upload access; Log Analytics. | BR-8 |
| `support/log-storage` | `modules/log-storage` | Log storage account + container + RBAC (writer = App VM, reader = Support VM + Support Personnel). | BR-6, BR-7 |
| `myden-app/mssql-db` | `modules/mssql-serverless` | Serverless MSSQL server + databases; configurable size/retention; VNet/IP firewall rules; AAD admin group. | BR-12 |
| `myden-app/tomcat-vm` | `modules/windows-app-vm` | Windows Tomcat app VM from golden image; data disks; WAR share mount (passwordless via managed identity); AAD join. | BR-2, BR-7, BR-10 |
| `dba-vm` | `modules/dba-access-vm` | DBA Windows VM + Key Vault + storage workspace; AAD join; daily shutdown. | BR-7 |
| `support/vm` | `modules/support-vm` | Support Windows VM (currently `enabled=false`); reads logs + DB. | BR-6, BR-7 |
| `app-gateway` | `modules/app-waf` | Application Gateway WAF: firewall policy (mode, size limits, banned countries, bad user-agents), SSL cert management + rotation identity, backend routing to Tomcat VM, DNS. | BR-5, BR-9 |
| `myden-app`, `support` | `modules/_noop` | Grouping units for `run-all` traversal. | — |

### 3.3 Cross-unit data flow (interfaces)
- `base` → resource groups, AD groups, managed identities/applications → all units.
- `network` → subnet IDs/prefixes, NIC map, WAF/DBA/support subnet objects → storage, DB, VMs, gateway.
- `vault-vm-break-glass` → break-glass Key Vault id → VMs.
- `war-storage` → share + mount-secret name → tomcat-vm.
- `log-storage` → storage account/container → support/vm.
- `tomcat-vm` → `vm_data` (IPs, machine name) → app-gateway WAF backend pool.

(See [dependency.md](dependency.md) for run order; the graph is a DAG rooted at `base`.)

### 3.4 Execution
Per-unit `terragrunt init/plan/apply/destroy`, or whole-stack `terragrunt run-all <cmd>` from `cloud-stack/live/staging/` (auto-orders by dependencies). Detailed commands in [action.md](action.md).

---

## 4. Subsystem: Golden images (Packer)

### 4.1 Tomcat app image — `vm-images/packer/win2022-server-azure/`
- **Entry:** `windows-2022-azure.pkr.hcl`; vars in `inputs.pkr.hcl`; values in `staging.pkvars.hcl`.
- **Function:** Builds a Windows Server 2022 managed image with Chocolatey, PowerShell modules, OpenJDK 17, Tomcat 9.0.89 (hardened config from `vm-images/tomcat/`), a WAR-mount scheduled task, and a WAR-deploy service; runs server tweaks; syspreps.
- **Auth:** Azure CLI auth; auto-generated temporary build credentials.
- **Output:** managed image `win2022-tomcat-base-openjdk17` in RG `golden-images`.
- **Satisfies:** BR-10.

### 4.2 DBA desktop image — `vm-images/packer/win2022-server-dba-desktop/`
- **Entry:** `win2022-server-dba-azure.pkr.hcl`.
- **Function:** Windows Server 2022 DBA desktop image with DBA tooling (`choco-packages.txt`) and first-boot tweaks.
- **Output:** managed image `win2022-server-dba-desktop`.
- **Satisfies:** BR-10.

### 4.3 Provisioning scripts — `vm-images/ps-scripts/`
- `common/` (choco bootstrap, PS modules, drive mounts, server tweaks); app-specific Tomcat/WAR scripts; DBA tweaks. Referenced by VM units via `existing_scripts` at `C:\Scripts\Packer-Provision\...`.

---

## 5. Subsystem: Single sign-on — `single-sign-on/`

- **Function (`gcp-sso-app.tf`):** Creates an Azure AD application + service principal for GCP Workforce Identity Federation, emits group/email/name claims, grants Graph scopes (`openid`, `email`, `profile`), rotates the client secret every 6 months, and wires redirect URIs to the GCP workforce pool provider (`gcp-worker-pool.tf`).
- **Interface:** `gcloud auth application-default login` + `az login` (elevated to Terraform Administrator), then the Terraform 2-liner; output `gcp_workforce_login_link` is the SSO entry URL.
- **Config:** `staging.tfvars` (`gcp_domain_name`, `gcp_pool_id`, `gcp_provider_id`).
- **Satisfies:** BR-11.

---

## 6. Certificate rotation — `scripts/shell/rotate-cert.sh`

- **Function:** Issues/renews a Let's Encrypt wildcard certificate via acme.sh using the Azure DNS challenge, converts to PFX, and imports it into a Key Vault.
- **Interface:** `rotate-cert.sh --domain <d> --vault <kv> --name <n> --email <e> [--expiry <days>]`; env `AZUREDNS_SUBSCRIPTIONID` / `AZUREDNS_TENANTID`.
- **Satisfies:** BR-9 (works with the App Gateway rotation identity `GitHub-Cert-Rotator`).

---

## 7. Non-functional behavior

| Aspect | How delivered |
| --- | --- |
| Security | WAF (prevention mode, banned countries, bad UA blocks), segregated subnets, managed identities, break-glass Key Vault, PIM, RG-scoped admin role. |
| Reproducibility | IaC + pinned versions + per-component state; new env = change documented variables (see [index.md](index.md)). |
| Auditability | Version control, central state, Terraform-managed tags, Conditional Access. |
| Least privilege | Managed identities for VM/app access; PIM JIT for humans; upload access limited to named repos/SPs. |
| Maintainability | Reusable modules, single version-pin file, mock outputs for standalone validation. |

---

## 8. Functional configuration points (summary)

Key variables that change system behavior, with locations, are catalogued in [index.md](index.md) and rated for risk in [myden-change-guide.md](myden-change-guide.md). Highlights: region/subscription/environment (`root.hcl`), provider versions (`stack-globals.hcl`), network CIDRs (`network` unit), WAF policy (`app-gateway` unit), DB sizing (`mssql-db` unit), image SKU/JDK/Tomcat (Packer `inputs.pkr.hcl`).

---

## 9. Traceability (BR → components)

| BR | Delivered by |
| --- | --- |
| BR-1 | All subsystems (IaC in VCS) |
| BR-2 | `root.hcl` backend, state bucket script |
| BR-3 | terraform-administrator + PIM scripts, proxy app |
| BR-4 | `resource_groups_owner_access` scoping |
| BR-5 | `app-gateway` / `modules/app-waf` |
| BR-6 | `network`, log-storage RBAC |
| BR-7 | `base` identities, `vault-vm-break-glass`, VM units |
| BR-8 | `war-storage` GitHub/Jenkins access |
| BR-9 | `rotate-cert.sh` + cert-rotator identity |
| BR-10 | Packer image builds |
| BR-11 | `single-sign-on` |
| BR-12 | `mssql-db` / `modules/mssql-serverless` |
| BR-13 | Terragrunt + documented variables |
| BR-14 | `.tool-versions`, `stack-globals.hcl` |
