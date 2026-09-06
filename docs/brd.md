# Business Requirements Document (BRD)

**Project:** MyDen Azure Cloud Platform
**Owner:** Denave IT / GRC-DevOps
**Environment(s):** staging (live), prod / uat (bootstrap + SSO scaffolding present)
**Document status:** Living document — reconstructed from the current repository state.

---

## 1. Purpose

This document states the business needs the MyDen Azure platform addresses and the requirements the infrastructure-as-code in this repository must satisfy. It is the "why" and "what" — the accompanying [FSD](fsd.md) covers the "how".

## 2. Background

Denave needs a secure, repeatable, auditable way to run its internal MyDen application on Microsoft Azure, and to federate identity between Azure AD and Google Cloud. Today the platform is delivered entirely as code (Terraform + Terragrunt + Packer + PowerShell) so that environments can be recreated, reviewed, and governed rather than hand-built in the portal.

## 3. Business objectives

| # | Objective | Success measure |
| --- | --- | --- |
| BO-1 | Bootstrap the ability to run Terraform safely in the tenant | State backend, proxy app, and a PIM-gated Terraform Administrator role exist and are used for all changes. |
| BO-2 | Run the MyDen application on Azure using security best practices | App runs on hardened Windows VMs behind a WAF, with segregated subnets and least-privilege identities. |
| BO-3 | Centralize identity and enable SSO to GCP | Users log in to GCP through Azure AD without separate GCP credentials. |
| BO-4 | Make every environment reproducible and auditable | All infrastructure is code-defined, version-pinned, and state-managed; changes go through review. |
| BO-5 | Enforce least privilege and just-in-time access | Administrative access is time-bound via PIM; VM/app access uses managed identities, not passwords. |

## 4. Stakeholders

| Role | Interest |
| --- | --- |
| Super Administrator / Subscription Owner | Runs bootstrap; delegates Terraform Administrator role. |
| Terraform Administrator (PIM group) | Applies infrastructure changes to the cloud stack. |
| DBA team | Access databases via a dedicated DBA VM and Key Vault. |
| Support Personnel | Read application logs and run read-only DB queries via a support VM. |
| Application / DevOps engineers | Push WAR artifacts (GitHub/Jenkins) and operate the app tier. |
| Security / GRC | Governs WAF policy, certificate rotation, access controls, auditing. |
| End users | Sign in to GCP through Azure AD (SSO). |

## 5. Scope

### 5.1 In scope
1. **Bootstrap** — TF state storage, intermediate proxy app for Graph permissions, Terraform Administrator custom role + group + PIM.
2. **MyDen application environment** — resource groups, network (VNet/subnets/bastion/WAF/DNS), WAR storage, break-glass Key Vault, MSSQL database, Tomcat application VM, DBA VM, support VM, and Application Gateway WAF.
3. **Golden images** — Packer-built Windows Server 2022 images for the Tomcat app and DBA desktop.
4. **Single sign-on** — Azure AD application federated with GCP Workforce Identity.
5. **Operational tooling** — PowerShell for PIM/user management and a shell script for WAF certificate rotation.

### 5.2 Out of scope
- The MyDen application source code itself (only its runtime environment and image config).
- Production data migration.
- Non-Azure/non-GCP cloud targets (AWS SSO is mentioned as a future intent only).
- Full prod/uat cloud-stack live trees (only `staging` is currently defined).

## 6. Business requirements

| ID | Requirement | Priority |
| --- | --- | --- |
| BR-1 | All infrastructure must be defined as code and stored in version control. | Must |
| BR-2 | Terraform state must be centrally stored and isolated per component. | Must |
| BR-3 | Administrative access must be gated by PIM (just-in-time, Entra ID P2). | Must |
| BR-4 | The Terraform Administrator role must be scoped to specific resource groups, not the whole subscription. | Must |
| BR-5 | The application must sit behind a Web Application Firewall with a configurable security policy. | Must |
| BR-6 | Network tiers (app, WAF, DBA, support) must be segregated with controlled reachability. | Must |
| BR-7 | VM and application access must use managed identities / passwordless auth where possible; VM admin passwords stored in a break-glass Key Vault. | Must |
| BR-8 | WAR artifact uploads must be restricted to approved GitHub repos and a Jenkins service principal. | Must |
| BR-9 | TLS certificates for the WAF must be rotatable in an automated, auditable way. | Should |
| BR-10 | Golden images must be reproducible and version-pinned (OS SKU, JDK, Tomcat). | Must |
| BR-11 | Users must be able to access GCP via Azure AD SSO. | Should |
| BR-12 | Databases must support configurable sizing, retention, and network/firewall restrictions. | Must |
| BR-13 | The platform must be reproducible across environments by changing a small, documented set of variables. | Must |
| BR-14 | Provider and tool versions must be pinned centrally. | Must |

## 7. Assumptions & constraints

- Azure AD Entra ID **P2** licenses are required for PIM (BR-3); the Terraform Administrator recipe fails without them.
- Some steps are inherently manual: MFA enablement, admin consent for Graph permissions, and creation of resource groups that the admin role is later scoped to.
- Azure CLI is a first-party multi-tenant app with restricted permissions, so an **intermediate proxy app** is required to grant the Graph permissions Terraform's AzureAD provider needs.
- Region is `centralindia`; state lives in `rg-tfstate` / `tfstate7shrl`.
- Bootstrap actions are restricted to the Super Administrator / subscription owner.

## 8. Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Missing/incomplete Graph consent on proxy app | Terraform runs fail | Global Admin grants consent when permissions change. |
| No P2 license | PIM recipe fails | Confirm licensing before bootstrap. |
| State backend misconfiguration | Orphaned/lost state | Central backend, per-component state keys, documented in `root.hcl`. |
| Certificate expiry | WAF outage | Automated rotation via `scripts/shell/rotate-cert.sh` + rotation identity. |
| Over-broad admin access | Security exposure | Role scoped to named resource groups only (BR-4). |

## 9. Related documents

- [FSD](fsd.md) — functional specification.
- [Infrastructure flow](myden-infrastructure-flow.md), [Dependency matrix](myden-dependency-matrix.md), [Dependencies](dependency.md).
- [Change guide](myden-change-guide.md), [Action guide](action.md), [Index](index.md).
