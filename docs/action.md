# MyDen Action Guide

Exactly what to run, and from which directory, to action each module — `init` / `plan` / `apply` / `destroy` for Terraform & Terragrunt, and `init` / `build` for Packer.

Two tooling styles are used in this repo:

- **Plain Terraform** — `bootstrap/*` and `single-sign-on/`. Backend + vars are passed explicitly with `-backend-config=azurerm.<env>.tfbackend` and `-var-file=<env>.tfvars`.
- **Terragrunt** — everything under `cloud-stack/live/`. Backend, provider, and common inputs are generated from `root.hcl`; you just run `terragrunt <cmd>`.
- **Packer** — `vm-images/packer/*`. Uses `-var-file=<env>.pkvars.hcl`.

Replace `staging` with `prod` / `uat` where those var/backend files exist. Always `az login` (correct tenant) before running.

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
```bash
cd bootstrap/terraform-administrator
terraform init  -backend-config=azurerm.staging.tfbackend -var-file=staging.tfvars
terraform plan  -var-file=staging.tfvars
terraform apply -var-file=staging.tfvars
terraform destroy -var-file=staging.tfvars
```
Requires Entra ID P2 (PIM). Supporting PIM scripts (not init/apply):
```bash
pwsh bootstrap/ps-scripts/activate-pim-group.ps1
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
terragrunt run-all init
terragrunt run-all plan
terragrunt run-all apply       # base → network/vault → storage/db/dba → VMs → app-gateway
terragrunt run-all destroy     # reverse order
```
See `docs/dependency.md` for the tiered order that `run-all` follows.

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
| Whole cloud stack | `cloud-stack/live/staging/` | `terragrunt run-all init` | `terragrunt run-all plan` | `terragrunt run-all apply` | `terragrunt run-all destroy` |

> `prod` / `uat`: swap `staging` for the environment in both the `.tfbackend` and `.tfvars` / `.pkvars.hcl` filenames (available where those files exist). The cloud stack currently only has a `staging/` live tree.
