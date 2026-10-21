# Terraform foundation for Google Cloud

This directory describes the first paid resources: a dedicated VPC/subnet, public TCP 80/443 and IAP-only TCP 22 firewall rules, a reserved IPv4 address, an Ubuntu 24.04 VM, a separate Persistent Disk, a private Cloud Storage backup bucket, and a VM service account with bucket-scoped object creation permission. It does not install Docker, configure DNS, create a certificate, schedule backups, or create an application. Review the [deployment plan](../docs/gcp-deployment-plan.md) before applying it.

Terraform is a separate CLI from `gcloud`. You can run it in [Google Cloud Shell](https://docs.cloud.google.com/docs/terraform/install-configure-terraform) after checking `terraform version` and installing it if absent, or from a local shell with Google Cloud Application Default Credentials. Nothing in this directory creates cloud resources until `terraform apply` is run.

## Prerequisites

1. Create/select a GCP project, link billing, set a budget alert, and estimate the VM, two disks, public IPv4, bucket, logging, and egress costs. Confirm quotas in the target region. Budget alerts do not cap charges.
2. Enable `compute.googleapis.com`, `iam.googleapis.com`, `storage.googleapis.com`, and `iap.googleapis.com` for the project. The operator needs permission to create these resources and attach the custom service account.
3. Create a **separate, private** Cloud Storage bucket for Terraform state before initialization. Enable object versioning, public access prevention, and uniform bucket-level access. Restrict read/write access to the Terraform operator or deployment identity. State can contain sensitive values; do not commit it. The backup bucket declared here is a different bucket.
4. Prepare an operator identity with IAP Tunnel User, OS Login or OS Admin Login, the Compute Engine privileges needed to connect, and Service Account User on the VM identity. Grant these to a named identity after reviewing the [IAP](https://docs.cloud.google.com/iap/docs/using-tcp-forwarding) and [OS Login](https://docs.cloud.google.com/compute/docs/connect/ssh-best-practices/login-access) instructions. This module cannot choose your user or group.
5. Review region, zone, CIDR, machine size, disk sizes, globally unique backup bucket name, and expected monthly cost. The example values are illustrative. If the project is in an organization, inspect inherited firewall policies too.

## Review and apply

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

`terraform plan` reads live cloud state but does not create the planned resources. `terraform apply` creates billable resources and must be run only after reviewing the plan and costs. Keep `backend.hcl`, `terraform.tfvars`, and the plan file out of Git. Commit `.terraform.lock.hcl` after the first successful `init` so provider selection is reproducible.

## Required post-apply steps

The Terraform provider does not expose `autoDelete` for the additional disk attachment. Before writing data, explicitly set the data disk to survive VM deletion, then inspect the instance disk list and confirm `autoDelete: false` for the data disk:

```sh
gcloud compute instances set-disk-auto-delete VM_NAME \
  --project=PROJECT_ID --zone=ZONE --disk=DATA_DISK_NAME --no-auto-delete
gcloud compute instances describe VM_NAME \
  --project=PROJECT_ID --zone=ZONE \
  --format='json(disks)'
```

Use `terraform output` for `VM_NAME`, `ZONE`, and `DATA_DISK_NAME`. The VM has deletion protection and the data disk and backup bucket have Terraform `prevent_destroy` guards. **Do not remove these guards or replace/destroy the VM before confirming the disk deletion rule and a restorable backup.** Recheck `autoDelete` whenever a disk is reattached to a replacement VM.

Next, use [the host setup guide](../docs/google-cloud-vm.md) to identify, format **only a new blank data disk**, mount it by UUID, install Docker Engine/Compose, and deploy Caddy. Point your domain's DNS A record to `public_ipv4`; Caddy obtains the certificate only after DNS and public TCP 80/443 are working. The backup bucket is only a destination: implement a scheduled backup job and restore drill before storing real app data. The backup writer can create objects, but cannot list or delete them; use a separate operator identity for restore and retention management.

Sources: [Google Terraform commands](https://docs.cloud.google.com/docs/terraform/basic-commands), [remote state](https://docs.cloud.google.com/docs/terraform/resource-management/store-state), [IAP TCP forwarding](https://docs.cloud.google.com/iap/docs/using-tcp-forwarding), [disk deletion rule](https://docs.cloud.google.com/compute/docs/disks/modify-persistent-disk), [Ubuntu image families](https://docs.cloud.google.com/compute/docs/images/os-details).
