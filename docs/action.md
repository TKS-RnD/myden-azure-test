# MyDen Action Guide

Exactly what to run, and from which directory, to action each module — `init` / `plan` / `apply` / `destroy` for Terraform & Terragrunt, and `init` / `build` for Packer.

Two tooling styles are used in this repo:

- **Plain Terraform** — `bootstrap/*` and `single-sign-on/`. Backend + vars are passed explicitly with `-backend-config=azurerm.<env>.tfbackend` and `-var-file=<env>.tfvars`.
- **Terragrunt** — everything under `cloud-stack/live/`. Backend, provider, and common inputs are generated from `root.hcl`; you just run `terragrunt <cmd>`.
- **Packer** — `vm-images/packer/*`. Uses `-var-file=<env>.pkvars.hcl`.

Replace `staging` with `prod` / `uat` where those var/backend files exist. Always `az login` (correct tenant) before running.

---

## 0. Prerequisites (install before running anything)

Which tool each phase needs:

| Tool | Needed for | Version note |
| --- | --- | --- |
| Azure CLI (`az`) | everything (auth) | latest |
| PowerShell Core (`pwsh`) | `bootstrap/ps-scripts/*` (state bucket, PIM scripts) | 7.x |
| Terraform | `bootstrap/*`, `single-sign-on/` | **1.13.2** (pinned in `.tool-versions`) |
| Terragrunt | `cloud-stack/live/*` | **0.93.0** (pinned in `cloud-stack/live/.tool-versions`) |
| Packer | `vm-images/packer/*` | latest (Azure plugin `>= 1.5.0`) |
| Google Cloud CLI (`gcloud`) | `single-sign-on/` only | latest |
| OpenTofu (optional) | drop-in for Terraform (`.tool-versions` lists `tofu 1.10.6`) | 1.10.6 |

> Versions are pinned via `.tool-versions` files, so installing [asdf](https://asdf-vm.com/) or [mise](https://mise.jdx.dev/) and running `asdf install` / `mise install` in each directory is the most reliable way to match Terraform/Terragrunt/OpenTofu versions across a team.

### Azure CLI
- **Linux:** `curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash` — [docs](https://learn.microsoft.com/cli/azure/install-azure-cli-linux)
- **macOS:** `brew install azure-cli` — [docs](https://learn.microsoft.com/cli/azure/install-azure-cli-macos)
- **Windows:** `winget install --id Microsoft.AzureCLI -e` — [docs](https://learn.microsoft.com/cli/azure/install-azure-cli-windows)

### PowerShell Core (`pwsh`)
- **Linux:** `sudo apt-get install -y powershell` (after adding the Microsoft repo) — [docs](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux)
- **macOS:** `brew install --cask powershell` — [docs](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-macos)
- **Windows:** `winget install --id Microsoft.PowerShell -e` — [docs](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows)

### Terraform (1.13.2)
- **Linux:** via HashiCorp apt repo, or `asdf install terraform 1.13.2` — [install guide](https://developer.hashicorp.com/terraform/install)
- **macOS:** `brew tap hashicorp/tap && brew install hashicorp/tap/terraform` — [install guide](https://developer.hashicorp.com/terraform/install)
- **Windows:** `winget install --id Hashicorp.Terraform -e` — [install guide](https://developer.hashicorp.com/terraform/install)

### Terragrunt (0.93.0)
- **Linux / macOS:** `brew install terragrunt`, or `asdf install terragrunt 0.93.0`, or download the binary — [install guide](https://terragrunt.gruntwork.io/docs/getting-started/install/)
- **Windows:** `winget install --id Gruntwork.Terragrunt -e` or download the `.exe` — [install guide](https://terragrunt.gruntwork.io/docs/getting-started/install/)

### Packer
- **Linux:** HashiCorp apt repo (`sudo apt-get install packer`) — [install guide](https://developer.hashicorp.com/packer/install)
- **macOS:** `brew tap hashicorp/tap && brew install hashicorp/tap/packer` — [install guide](https://developer.hashicorp.com/packer/install)
- **Windows:** `winget install --id Hashicorp.Packer -e` — [install guide](https://developer.hashicorp.com/packer/install)

### Google Cloud CLI (`gcloud`) — SSO only
- **Linux:** `sudo apt install google-cloud-cli` — [install guide](https://cloud.google.com/sdk/docs/install)
- **macOS:** `brew install --cask google-cloud-sdk` — [install guide](https://cloud.google.com/sdk/docs/install)
- **Windows:** `winget install -e --id Google.CloudSDK` — [install guide](https://cloud.google.com/sdk/docs/install)

### asdf / mise (optional version managers, match pinned versions)
- **asdf:** [asdf-vm.com/guide/getting-started](https://asdf-vm.com/guide/getting-started.html) — then `asdf plugin add terraform && asdf install` inside a directory with `.tool-versions`.
- **mise:** [mise.jdx.dev/getting-started](https://mise.jdx.dev/getting-started.html) — then `mise install` inside a directory with `.tool-versions`.

**Per-phase checklist:**
- Bootstrap state bucket → Azure CLI + PowerShell Core
- Bootstrap proxy app / TF administrator → Azure CLI + PowerShell Core + Terraform
- Single sign-on → Azure CLI + PowerShell Core + Terraform + Google Cloud CLI
- Packer images → Azure CLI + Packer
- Cloud stack → Azure CLI + Terraform + Terragrunt

---

## 1. Bootstrap (plain Terraform, run first, super-admin only)

### 1a. TF state bucket — `bootstrap/ps-scripts/create-tf-state-bucket.ps1`
```bash
cd bootstrap/ps-scripts
pwsh create-tf-state-bucket.ps1     # interactive; creates rg-tfstate / tfstate7shrl / tfstate
```
No init/plan/apply — this is a PowerShell script, must run before any Terraform backend init.

### 1b. Intermediate proxy app — `bootstrap/intermediate-proxy-app/`
```bash
cd bootstrap/intermediate-proxy-app
terraform init  -backend-config=azurerm.staging.tfbackend -var-file=staging.tfvars
terraform plan  -var-file=staging.tfvars
terraform apply -var-file=staging.tfvars
terraform destroy -var-file=staging.tfvars      # teardown
```

### 1c. Terraform administrator — `bootstrap/terraform-administrator/`

> **⚠️ Seed your admin identity BEFORE running this — and before any cloud-stack terragrunt scripts.**
> This module grants a human user admin/owner access and creates the PIM-gated **Terraform Administrator** group that every cloud-stack `terragrunt` command is later run as. Edit **`bootstrap/terraform-administrator/staging.tfvars`** (and `prod.tfvars` / `uat.tfvars` for other envs) and add your Azure AD **UPN** (e.g. `you@yourtenant.onmicrosoft.com`; the user must already exist in the tenant) in these places:
>
> | Variable | Purpose | Add your id here? |
> | --- | --- | --- |
> | `terraform-admin-group-eligible-users` | Makes the user **PIM-eligible** for the Terraform Administrator group you activate and run terragrunt as. | **Yes — required.** |
> | `terraform-builtin-roles-users` | Grants directory/built-in roles (PIM-eligible), e.g. User Administrator. | Usually yes. |
> | `resource_groups_owner_access` | Resource groups the admin gets Owner on (e.g. `myden-staging`). | As needed. |
>
> Values are UPNs resolved via `data "azuread_user"`. After apply, activate the group before running the cloud stack (see below). The in-stack admin **groups** created by `cloud-stack/modules/base` (`Azure App VM Administrators`, `Azure Database Administrators`, `Break Glass Vault Access`, `Support Personnel`) are populated with members *after* `base` is applied, not here.

```bash
cd bootstrap/terraform-administrator
terraform init  -backend-config=azurerm.staging.tfbackend -var-file=staging.tfvars
terraform plan  -var-file=staging.tfvars
terraform apply -var-file=staging.tfvars
terraform destroy -var-file=staging.tfvars
```
Requires Entra ID P2 (PIM). Supporting PIM scripts (not init/apply):
```bash
pwsh bootstrap/ps-scripts/activate-pim-group.ps1     # activate Terraform Administrator group before running cloud-stack terragrunt
pwsh bootstrap/ps-scripts/activate-pim-role.ps1
```

---

## 2. Single sign-on (plain Terraform) — `single-sign-on/`
Requires `gcloud auth application-default login` + `az login` (elevated to Terraform Administrator via `activate-pim-group.ps1`).
```bash
cd single-sign-on
terraform init  -backend-config=azurerm.staging.tfbackend -var-file=staging.tfvars
terraform plan  -var-file=staging.tfvars
terraform apply -var-file=staging.tfvars
terraform destroy -var-file=staging.tfvars
```

---

## 3. Packer golden images (`vm-images/packer/*`)

Run before the VM units in the cloud stack. Uses Azure CLI auth (`use_azure_cli_auth = true`), so `az login` first.

### 3a. Tomcat app image — `vm-images/packer/win2022-server-azure/`
Entry file: `windows-2022-azure.pkr.hcl` (vars in `inputs.pkr.hcl`, values in `staging.pkvars.hcl`)
```bash
cd vm-images/packer/win2022-server-azure
packer init .
packer validate -var-file=staging.pkvars.hcl .
packer build    -var-file=staging.pkvars.hcl .
```
Produces managed image `win2022-tomcat-base-openjdk17` in RG `golden-images`.

### 3b. DBA desktop image — `vm-images/packer/win2022-server-dba-desktop/`
Entry file: `win2022-server-dba-azure.pkr.hcl`
```bash
cd vm-images/packer/win2022-server-dba-desktop
packer init .
packer validate -var-file=staging.pkvars.hcl .
packer build    -var-file=staging.pkvars.hcl .
```
Produces managed image `win2022-server-dba-desktop` in RG `golden-images`.

> Packer has no `destroy`. To remove an image, delete the managed image from the `golden-images` RG via `az image delete` or the portal.

---

## 4. Cloud stack (Terragrunt) — `cloud-stack/live/staging/<unit>/`

No `-backend-config` / `-var-file` flags — `root.hcl` generates them. Run inside each unit directory. `terragrunt` auto-runs `init` on first `plan`/`apply`, but you can init explicitly.

**Single-unit pattern** (replace `<unit>` with the directory):
```bash
cd cloud-stack/live/staging/<unit>
terragrunt init
terragrunt plan
terragrunt apply
terragrunt destroy
```

### Per-unit commands (paths + entry file `terragrunt.hcl`)

| Unit | Directory to run from |
| --- | --- |
| base | `cloud-stack/live/staging/base` |
| network | `cloud-stack/live/staging/network` |
| vault-vm-break-glass | `cloud-stack/live/staging/vault-vm-break-glass` |
| war-storage | `cloud-stack/live/staging/war-storage` |
| support/log-storage | `cloud-stack/live/staging/support/log-storage` |
| myden-app/mssql-db | `cloud-stack/live/staging/myden-app/mssql-db` |
| dba-vm | `cloud-stack/live/staging/dba-vm` |
| myden-app/tomcat-vm | `cloud-stack/live/staging/myden-app/tomcat-vm` |
| support/vm (`enabled=false`) | `cloud-stack/live/staging/support/vm` |
| app-gateway | `cloud-stack/live/staging/app-gateway` |

Example (base):
```bash
cd cloud-stack/live/staging/base
terragrunt init
terragrunt plan
terragrunt apply
```

### Whole stack at once (respects dependency order automatically)
Run from the environment root `cloud-stack/live/staging/`:
```bash
cd cloud-stack/live/staging
terragrunt run --all init
terragrunt run --all plan
terragrunt run --all apply       # base → network/vault → storage/db/dba → VMs → app-gateway
terragrunt run --all destroy     # reverse order
```
See `docs/dependency.md` for the tiered order that `run --all` follows.

> **Terragrunt CLI note:** the old top-level `terragrunt run-all <cmd>` was removed in the Terragrunt [CLI redesign](https://terragrunt.gruntwork.io/docs/migrate/cli-redesign) (versions newer than the `0.93.0` pinned in `.tool-versions`). Use `terragrunt run --all <cmd>` instead. If you see `unknown command: "run-all"`, this is the fix. Single-unit commands (`terragrunt init/plan/apply/destroy`) are unchanged.

---

## 5. Quick reference

| What | Where (path) | Init | Plan/Validate | Create | Destroy |
| --- | --- | --- | --- | --- | --- |
| State bucket | `bootstrap/ps-scripts/create-tf-state-bucket.ps1` | — | — | `pwsh create-tf-state-bucket.ps1` | manual (`az`) |
| Proxy app | `bootstrap/intermediate-proxy-app/` | `terraform init -backend-config=azurerm.staging.tfbackend -var-file=staging.tfvars` | `terraform plan -var-file=staging.tfvars` | `terraform apply -var-file=staging.tfvars` | `terraform destroy -var-file=staging.tfvars` |
| TF administrator | `bootstrap/terraform-administrator/` | same pattern | same | same | same |
| Single sign-on | `single-sign-on/` | same pattern | same | same | same |
| Tomcat image | `vm-images/packer/win2022-server-azure/` | `packer init .` | `packer validate -var-file=staging.pkvars.hcl .` | `packer build -var-file=staging.pkvars.hcl .` | `az image delete` |
| DBA image | `vm-images/packer/win2022-server-dba-desktop/` | `packer init .` | `packer validate -var-file=staging.pkvars.hcl .` | `packer build -var-file=staging.pkvars.hcl .` | `az image delete` |
| Any cloud-stack unit | `cloud-stack/live/staging/<unit>/` | `terragrunt init` | `terragrunt plan` | `terragrunt apply` | `terragrunt destroy` |
| Whole cloud stack | `cloud-stack/live/staging/` | `terragrunt run --all init` | `terragrunt run --all plan` | `terragrunt run --all apply` | `terragrunt run --all destroy` |

> `prod` / `uat`: swap `staging` for the environment in both the `.tfbackend` and `.tfvars` / `.pkvars.hcl` filenames (available where those files exist). The cloud stack currently only has a `staging/` live tree.
