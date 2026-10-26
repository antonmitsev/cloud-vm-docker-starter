# Terraform foundation for Google Cloud

**Status for this project (25 October 2026):** The VM, network, static IP, retained data disk, backup bucket, DNS/Cloudflare route, snapshots, and uptime check were created **manually**. This Terraform configuration has never been applied or imported into state. The [observed inventory](../docs/gcp-current-state.md) is anonymized and is not a substitute for checking live resources. The current work path remains manual operation and application development; Terraform adoption is optional later.

Do **not** run `terraform apply` against the existing project with an empty state. Terraform would plan to create the resources declared here, even though corresponding resources already exist. First reconcile the configuration with the real environment and plan an import.

This directory declares a VPC/subnet, web and IAP SSH firewall rules, a reserved IPv4 address, an Ubuntu 24.04 VM, a separate Persistent Disk, a private Cloud Storage backup bucket, and a VM service account with bucket-scoped object creation. It does not manage project/billing setup, operator IAM, Docker, disk formatting/mounting, DNS, Cloudflare, certificates, snapshot schedules, monitoring, periodic backups, or an application.

## Differences from the deployed environment

| Area | Configuration in `infra/` | Manually deployed environment |
| --- | --- | --- |
| Web firewall | `google_compute_firewall.web` permits `0.0.0.0/0` on TCP 80/443. | Only [Cloudflare IPv4 ranges](https://www.cloudflare.com/ips/) are allowed; the former public web rule is disabled. Before any import or new deployment, model the intended allowlist and reconcile the existing rules. Never import the disabled broad rule as an enabled web rule. |
| Network and resource names | Names derive from `name_prefix`; subnet CIDR and resource sizes come from variables. | Real names and subnet CIDR are deliberately absent from Git. Obtain them from a private inventory and compare each property. |
| VM and disk | The VM is declared with deletion protection; the data disk has `prevent_destroy`. The attachment's `autoDelete` value is not expressed here. | The data disk is mounted by UUID and set to **Keep disk**; both the attachment setting and actual VM deletion protection must be checked in GCP. |
| Backup bucket | A private bucket and object-creator IAM membership are declared. | The bucket has seven-day soft delete; snapshots and a manual test upload/restore exist. The soft-delete setting, snapshot schedules, and backup automation are not represented by this configuration. |
| Public route and monitoring | No DNS, Cloudflare, TLS, or monitoring resources are declared. | The API hostname uses Cloudflare for SaaS, Caddy HTTPS, and an uptime check. Those remain manually managed unless separately modeled. |

The VM's write-only backup role cannot read objects for restore. Use an operator identity with appropriate access for restore; see the [verified backup test](../docs/gcp-current-state.md#проверка-на-резервно-копие-и-възстановяване).

Terraform is a separate CLI from `gcloud`. You can run it in [Google Cloud Shell](https://docs.cloud.google.com/docs/terraform/install-configure-terraform) after checking `terraform version` and installing it if absent, or from a local shell with Google Cloud Application Default Credentials. Nothing in this directory creates cloud resources until `terraform apply` is run.

## If Terraform is adopted for the existing project

1. Record the live project ID, region/zone, resource names and IDs, network and firewall rules, VM metadata and image, disk attachment flags, bucket settings, IAM memberships, snapshots, and monitoring resources in a **private** inventory. Decide which resources Terraform will own; leave every other resource explicitly outside its scope.
2. Review the current provider and Terraform versions. Create a separate private, versioned state bucket with restricted access and public access prevention; do not reuse the application backup bucket. Keep backend configuration, variables, state, and plan files out of Git.
3. Change the HCL to match the desired live configuration **before import**. In particular, replace the open web firewall rule with the Cloudflare allowlist model, align names and attributes, and decide how to represent or deliberately exclude snapshot schedules, bucket soft delete, and other manual settings. Check that the data disk will remain retained. Do not use `ignore_changes` merely to hide unexplained differences.
4. Create one Terraform destination address and [import block](https://developer.hashicorp.com/terraform/language/import/single-resource) for each existing resource selected for management. Match each address to exactly one real object. Look up its import ID in the relevant [Google provider resource documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs). Include IAM memberships only after checking which identity and scope the resource actually uses.
5. Run `terraform init` with the protected backend, then `terraform plan -var-file=terraform.tfvars` and inspect the **full** proposed actions. An acceptable first adoption plan imports the intended objects and has **zero unexpected creates, updates, replacements, or destroys**. Fix configuration or scope and repeat the plan until it is understood. Save and review the final plan before any apply. After an explicitly reviewed import, run a fresh plan to check for drift.

Importing creates a Terraform state binding; it does not prove that the checked-in arguments match the real resource. The [Terraform import workflow](https://developer.hashicorp.com/terraform/language/import/single-resource) calls for reconciling unexpected changes before applying an import plan. Do not assume the old `name_prefix` defaults identify existing resources. Terraform state can contain sensitive values.

## If creating a separate new environment

This draft needs review before use: set the intended region, sizes, names, costs, and firewall policy; decide whether Cloudflare will be in front of the VM at launch; and include the resources needed for that design. The example `europe-west3` region differs from the manually deployed `europe-west1`. A public `0.0.0.0/0` web rule in the current HCL does **not** match the deployed Cloudflare-restricted setup. Obtain an approved resource and cost plan before creating billable resources. See the [infrastructure plan](../docs/cloud-infra-plan.md) for the other setup gates.

### Prerequisites

1. Create/select a GCP project, link billing, set a budget alert, and estimate the VM, two disks, public IPv4, bucket, logging, and egress costs. Confirm quotas in the target region. Budget alerts do not cap charges.
2. Enable `compute.googleapis.com`, `iam.googleapis.com`, `storage.googleapis.com`, and `iap.googleapis.com` for the project. The operator needs permission to create these resources and attach the custom service account.
3. Create a **separate, private** Cloud Storage bucket for Terraform state before initialization. Enable object versioning, public access prevention, and uniform bucket-level access. Restrict read/write access to the Terraform operator or deployment identity. State can contain sensitive values; do not commit it. The backup bucket declared here is a different bucket.
4. Prepare an operator identity with IAP Tunnel User, OS Login or OS Admin Login, the Compute Engine privileges needed to connect, and Service Account User on the VM identity. Grant these to a named identity after reviewing the [IAP](https://docs.cloud.google.com/iap/docs/using-tcp-forwarding) and [OS Login](https://docs.cloud.google.com/compute/docs/connect/ssh-best-practices/login-access) instructions. This module cannot choose your user or group.
5. Review region, zone, CIDR, machine size, disk sizes, globally unique backup bucket name, and expected monthly cost. The example values are illustrative. If the project is in an organization, inspect inherited firewall policies too.

### Review and apply to a separate new environment only

From `infra/`:

```sh
cp terraform.tfvars.example terraform.tfvars
cp backend.hcl.example backend.hcl
# Edit both files with real, reviewed values.
terraform init -backend-config=backend.hcl
terraform plan -var-file=terraform.tfvars -out=planned.tfplan
terraform show planned.tfplan
terraform apply planned.tfplan
terraform output
```

`terraform plan` reads live cloud state but does not create the planned resources. `terraform apply` creates billable resources and must be run only after reviewing the plan and costs. These commands are **not** an adoption procedure for the existing manual project. Keep `backend.hcl`, `terraform.tfvars`, and the plan file out of Git. Commit `.terraform.lock.hcl` after the first successful `init` so provider selection is reproducible.

### Required post-apply steps for a new environment

The Terraform provider does not expose `autoDelete` for the additional disk attachment. Before writing data, explicitly set the data disk to survive VM deletion, then inspect the instance disk list and confirm `autoDelete: false` for the data disk:

```sh
gcloud compute instances set-disk-auto-delete VM_NAME \
  --project=PROJECT_ID --zone=ZONE --disk=DATA_DISK_NAME --no-auto-delete
gcloud compute instances describe VM_NAME \
  --project=PROJECT_ID --zone=ZONE \
  --format='json(disks)'
```

Use `terraform output` for `VM_NAME`, `ZONE`, and `DATA_DISK_NAME`. The VM has deletion protection and the data disk and backup bucket have Terraform `prevent_destroy` guards. **Do not remove these guards or replace/destroy the VM before confirming the disk deletion rule and a restorable backup.** Recheck `autoDelete` whenever a disk is reattached to a replacement VM.

Next, use [the host setup guide](../docs/google-cloud-vm.md) to identify, format **only a new blank data disk**, mount it by UUID, install Docker Engine/Compose, and deploy Caddy. Set up DNS and origin reachability for the chosen routing design; the [deployed Cloudflare route](../docs/cloudflare-single-subdomain-bg.md) uses a CNAME through Cloudflare, not a direct A record for the API hostname. The backup bucket is only a destination: implement a scheduled backup job and restore drill before storing real app data. The backup writer can create objects, but cannot list or delete them; use a separate operator identity for restore and retention management.

Sources: [Terraform import](https://developer.hashicorp.com/terraform/language/import/single-resource), [Google Terraform commands](https://docs.cloud.google.com/docs/terraform/basic-commands), [remote state](https://docs.cloud.google.com/docs/terraform/resource-management/store-state), [IAP TCP forwarding](https://docs.cloud.google.com/iap/docs/using-tcp-forwarding), [disk deletion rule](https://docs.cloud.google.com/compute/docs/disks/modify-persistent-disk), [Ubuntu image families](https://docs.cloud.google.com/compute/docs/images/os-details).
