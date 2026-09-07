# MyDen Teardown / Destroy Guide

What to keep in mind when destroying the platform so a fresh start on the **same subscription** is clean. Two parts:

1. **Resource groups created during apply** — what they are, which unit creates them, and how to delete manually.
2. **Everything NOT inside those resource groups** — tenant-level Azure AD objects, subscription-scoped role definitions, soft-deleted Key Vaults, Terraform state, and images. These survive RG deletion and often **block a re-apply**.

> **Golden rule:** always run `terragrunt run-all destroy` (leaves → base) first. Manual deletion is only for cleaning up leftovers or when state is lost. Never delete Terraform **state** until the real resources are actually gone — deleting state first orphans them.

## Do you need to follow dependency order when destroying?

**Yes — destroy in the REVERSE of the apply/dependency order (leaves → roots). You cannot destroy modules in any order.**

Units reference each other's outputs (subnet IDs, resource groups, managed identities), so a downstream unit must be gone before the unit it depends on. For example `app-gateway` points at `tomcat-vm`'s IP, and every unit depends on `base` (resource groups + AD identities) — so `base` is destroyed **last**.

| Situation | Do you sequence manually? |
| --- | --- |
| `terragrunt run-all destroy` (from `cloud-stack/live/staging/`) | **No.** Terragrunt reads the `dependency` graph and destroys in the correct reverse order automatically. Preferred method. |
| Per-unit `terragrunt destroy` | **Yes.** You must run them leaves → roots yourself (see order below). |
| Manual `az group delete` (state lost) | **Yes.** Azure will delete RGs in any order, but doing it out of order leaves orphaned cross-RG references (e.g. NICs pointing at a deleted subnet). Follow the same reverse order. |

**Reverse destroy order (leaves → roots):**
```
app-gateway
  → myden-app/tomcat-vm  (and support/vm if enabled)
    → war-storage, support/log-storage, myden-app/mssql-db, dba-vm
      → network, vault-vm-break-glass
        → base            ← destroy LAST (owns the resource groups + AD identities)
```
See [dependency.md](dependency.md) for the full graph. This is exactly the apply order reversed.

---

## Part 1 — Resource groups created during apply

All values shown for `staging` (`<env>` = the `environment` local in `root.hcl`). Region: `centralindia`.

| Resource group (staging) | Created by (unit → module) | Path |
| --- | --- | --- |
| `rg-base-staging` | `base` → `modules/base` (`resource_group.own`) | `cloud-stack/live/staging/base/` |
| `rg-staging-network` | `base` → `modules/base` (`resource_group.baseline`) | `cloud-stack/live/staging/base/terragrunt.hcl` (`resource_groups[]`) |
| `rg-staging-vaults` | `base` → `modules/base` | same |
| `rg-staging-app-vms` | `base` → `modules/base` | same |
| `rg-staging-databases` | `base` → `modules/base` | same |
| `rg-staging-dba` | `base` → `modules/base` | same |
| `rg-staging-support` | `base` → `modules/base` | same |
| WAR storage RG (value of `resource_group_name`) | `war-storage` → `modules/war-storage`/`vm-data-store` | `cloud-stack/live/staging/war-storage/terragrunt.hcl` |
| Log storage RG (value of `resource_group_name`) | `support/log-storage` → `modules/log-storage` | `cloud-stack/live/staging/support/log-storage/terragrunt.hcl` |
| `rg-tfstate` *(bootstrap, NOT part of apply)* | `bootstrap/ps-scripts/create-tf-state-bucket.ps1` | holds Terraform state — see Part 2 §4 |
| `golden-images` *(bootstrap, NOT part of apply)* | Packer builds | holds golden images — see Part 2 §5 |

> The six `rg-staging-*` names and their purposes are defined in `cloud-stack/live/staging/base/terragrunt.hcl` under `resource_groups[]`. `myden-app` and `support` are grouping units (`modules/_noop`) and create no resource groups.

### Preferred destroy (Terragrunt handles RGs automatically)
```bash
cd cloud-stack/live/staging
terragrunt run-all destroy       # destroys all units in reverse dependency order (removes the RGs above)
```
Or per unit — **must be run in the reverse order shown above** (`app-gateway` → VMs → storage/db → `network`/`vault-vm-break-glass` → `base`). `base` is always last:
```bash
cd cloud-stack/live/staging/base
terragrunt destroy               # removes rg-base-staging + the six rg-staging-* groups — run LAST
```

### Manual RG deletion (only if state is lost / leftovers remain)
```bash
az login
az account set --subscription "d32407a7-5c5f-4491-ad3a-f2731fec7b4d"

# List what exists
az group list -o table

# Delete a specific RG (repeat per group)
az group delete --name rg-staging-network --yes --no-wait
az group delete --name rg-staging-vaults  --yes --no-wait     # NOTE: vaults inside are soft-deleted, see Part 2 §1
# ... rg-staging-app-vms, rg-staging-databases, rg-staging-dba, rg-staging-support,
#     rg-base-staging, <war-storage RG>, <log-storage RG>
```
> Do **not** delete `rg-tfstate` until you have finished with Terraform state (Part 2 §4).

---

## Part 2 — Resources NOT inside the created resource groups

These live at **tenant** or **subscription** scope (or are held by soft-delete). RG deletion does not remove them, and several block re-apply via `prevent_duplicate_names` / purge protection.

### §1. Key Vaults — soft-deleted AND purge-protected ⚠️ (most common blocker)
Every vault sets `purge_protection_enabled = true` and `soft_delete_retention_days = 90`. After destroy the **name is reserved for 90 days and cannot be purged**.

| Vault | Defined in |
| --- | --- |
| WAF certificate vault | `cloud-stack/modules/app-waf/bootstrap_cert.tf` |
| Break-glass vault | `cloud-stack/modules/vault-vm-break-glass/key-vault.tf` |
| DBA vault | `cloud-stack/modules/dba-access-vm/key-vault.tf` |
| WAR storage vault(s) | `cloud-stack/modules/war-storage/vm-key-vault.tf`, `upload-key-vault.tf` |

```bash
az keyvault list-deleted -o table            # see soft-deleted vaults + purge date
az keyvault recover --name <vault-name>      # recover so Terraform can re-adopt (purge is BLOCKED by protection)
```
For a fresh start you must either **recover-and-reuse** the same names, or **change the vault names** in the tfvars/terragrunt inputs. You cannot purge a purge-protected vault to reclaim its name early.

### §2. Azure AD / Entra objects (tenant-level, `prevent_duplicate_names`)
Removed by `terragrunt destroy`/`terraform destroy` when state is intact; delete manually only if state is lost.

| Object | Defined in |
| --- | --- |
| AD groups: `Azure App VM Administrators`, `Azure Database Administrators`, `Break Glass Vault Access`, `Support Personnel` | `cloud-stack/modules/base/ad-groups.tf` (names in `base/terragrunt.hcl`) |
| Managed identities: `mi-app-vm-*`, `mi-github-*`, `mi-dba-*`, `mi-support-*`, `mi-github-cert-rotator-*` | `cloud-stack/modules/base/managed-identities.tf` |
| Managed application + SP: `app-jenkins-war-pusher-*` | `cloud-stack/modules/base/managed-applications.tf` |
| Terraform Administrator group + PIM policies | `bootstrap/terraform-administrator/group.tf` |
| Intermediate proxy app | `bootstrap/intermediate-proxy-app/app.tf` |
| SSO app + client secret | `single-sign-on/gcp-sso-app.tf` |

```bash
az ad group list  --display-name "Azure App VM Administrators" -o table
az ad group delete --group <objectId>
az ad app list    --display-name "app-jenkins-war-pusher-staging" -o table
az ad app delete  --id <appId>
```

### §3. Custom role definitions + role assignments (subscription-scoped)
Not in any RG. Same-name re-creation can conflict.

| Custom role | Defined in |
| --- | --- |
| `DNS-TXT-Manager-<env>` | `cloud-stack/modules/app-waf/rotation_cert.tf` |
| `KV-Cert-Manager-<env>` | `cloud-stack/modules/app-waf/rotation_cert.tf` |
| `vm_power_manager` (DBA) | `cloud-stack/modules/dba-access-vm/ad-group-access.tf` |
| `vm_power_manager` (support) | `cloud-stack/modules/support-vm/ad-group-role-access.tf` |

Role assignments to verify gone: subscription **Owner** granted to the Terraform Admin group (`bootstrap/terraform-administrator/group-role.tf`), and Key Vault Secrets/Certificates Officer (`modules/app-waf/bootstrap_cert.tf`).
```bash
az role definition list --custom-role-only true -o table
az role definition delete --name "DNS-TXT-Manager-staging"
az role assignment list --all --assignee <principalId> -o table
```

### §4. Terraform / Terragrunt state (reset for a true fresh start)
State lives in storage account `tfstate7shrl` / container `tfstate` in `rg-tfstate` — separate from everything above.

- Per-unit state blobs (cloud-stack keys are per-unit relative paths; bootstrap/SSO keys are listed in each `azurerm.<env>.tfbackend`).
- Delete state blobs **only after** resources are destroyed, or you orphan them.
- Local `.terraform/` dirs and `.terraform.lock.hcl` regenerate on `init` — safe to leave; delete `.terraform/` for a fully clean init.

```bash
az storage blob list --account-name tfstate7shrl --container-name tfstate -o table
az storage blob delete --account-name tfstate7shrl --container-name tfstate --name <unit/key>
```

### §5. Packer golden images (no Terraform destroy)
Built into RG `golden-images`; Packer has no `destroy`.

| Image | Built by |
| --- | --- |
| `win2022-tomcat-base-openjdk17` | `vm-images/packer/win2022-server-azure/` |
| `win2022-server-dba-desktop` | `vm-images/packer/win2022-server-dba-desktop/` |

```bash
az image list -g golden-images -o table
az image delete -g golden-images -n win2022-tomcat-base-openjdk17
```

### §6. Other tenant/subscription leftovers to verify
- **Public DNS zone + records** (`network` / `app-waf` flow) — RG-scoped but often shared; confirm before deleting.
- **Conditional Access policy** — `bootstrap/terraform-administrator/cas-policy.tf` (tenant-level).
- **PIM eligibility schedules** for the admin group/roles — `bootstrap/terraform-administrator/`.
- **Custom security attributes** if applied via `bootstrap/ps-scripts/manage-security-attributes.ps1` (directory-level).

---

## Recommended fresh-start teardown order

1. `cd cloud-stack/live/staging && terragrunt run-all destroy` (leaves → base; removes all Part 1 RGs).
2. If doing a full reset: `terraform destroy` in `single-sign-on/`, then `bootstrap/terraform-administrator/`, then `bootstrap/intermediate-proxy-app/`.
3. Handle **soft-deleted Key Vaults** (§1) — recover-and-reuse names, or rename for the new deploy.
4. Confirm **AD objects** (§2), **custom roles + assignments** (§3) are gone; delete leftovers by name.
5. Delete **state blobs** (§4) — only after resources are gone.
6. Optionally delete **golden images** (§5) and shared **DNS zone** (§6).
7. Only now delete `rg-tfstate` if you want to remove state storage entirely.

> Two things most often missed that break a fresh apply on the same subscription: **purge-protected soft-deleted Key Vaults** (name reserved 90 days) and **leftover Azure AD objects / custom roles** with `prevent_duplicate_names`.
