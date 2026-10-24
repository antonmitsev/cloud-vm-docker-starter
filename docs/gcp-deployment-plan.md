# GCP deployment plan

**Status:** deployment plan with an unapplied [Terraform foundation](../infra/README.md). No paid cloud resources or public site have been created.  
**Scope:** release 0 brings up the VM, persistent disk, Docker, and the existing Caddy readiness page. Release 1 adds a real application after its image, schema, backup, and rollback are defined. The [infrastructure plan](cloud-infra-plan.md) records the architecture and security decisions; the [VM setup guide](google-cloud-vm.md) supplies manual host steps.

## Inputs and release record

Before any `terraform apply` or manual VM creation, record the GCP project ID and billing account, region/zone, domain and DNS owner, monthly spending range, operator identity, and recovery targets. Price the exact VM, boot/data disks, static external IPv4, snapshots, Cloud Storage, logs, and egress in the [Google Cloud calculator](https://cloud.google.com/products/calculator). Configure billing alerts and decide whether an eligible [spend cap](https://docs.cloud.google.com/billing/docs/how-to/budgets-spend-caps) fits the availability requirement; a cap can pause services.

For each deployment, record: Git commit, Terraform plan/apply record, VM image, Docker and Compose versions, Caddy image digest, public IP, DNS name, disk ID and mount UUID, backup location, operator, start/end time, and checks performed. Keep credentials and real `.env` files out of Git.

## Release 0: infrastructure and HTTPS readiness

| Stage | Senior developer action | Evidence required to continue |
| --- | --- | --- |
| 0. Prepare | Review the completed [local simulation](local-simulation.md). Bootstrap the protected remote state bucket and inspect the [Terraform configuration](../infra/README.md). Review the full Terraform plan and estimated monthly cost with the owner. | Approved resource list, region, spend range, and no unintended deletes. |
| 1. Provision | Enable needed APIs; use Terraform for the network rules, reserved IP, Ubuntu VM, boot disk, separate data disk, and backup bucket. Grant operator IAP/OS Login roles; run the documented `set-disk-auto-delete` command for the data disk. Public ingress is TCP 80/443; inspect effective rules so TCP 22 and database ports are not public. Monitoring resources remain a later step. | Terraform outputs/resource inventory; data disk `autoDelete=false`; successful SSH through IAP; effective firewall review. |
| 2. Prepare host | Patch the OS, install Docker Engine plus Compose from the official Ubuntu repository, identify the blank data disk, format it once, and mount by UUID at `/srv/cloud-app-data`. Configure startup to require that mount before Compose starts. | `findmnt /srv/cloud-app-data` identifies the retained disk after a VM reboot; `docker compose version` works; no fallback writes to the boot disk. |
| 3. Prepare gateway | Check out a recorded commit of this repository on the VM. Pin the Caddy image to a reviewed digest before the production release. Create `/srv/cloud-app-data/caddy` and `caddy-config` on the mounted disk. Put the real `APP_DOMAIN` in a root-owned `.env`; leave local port/data overrides unset. Inspect `docker compose config` before starting the service. | Compose resolves to the intended domain, public ports 80/443, and retained disk paths. |
| 4. Publish name and TLS | Point the domain's A record at the reserved IP, then start Caddy with `docker compose up -d`. Caddy obtains and renews a public certificate automatically through an ACME issuer; no certificate purchase or manual file upload is needed. Its `/data` path must be writable and persistent, and public TCP 80/443 must reach the VM. | Gateway starts without errors; DNS resolves to the reserved IP; HTTP redirects to HTTPS; HTTPS has a browser-trusted certificate for the exact domain; `/` returns `Cloud VM ready` and `/health` returns `healthy`. |
| 5. Recoverability | Configure a backup job and off-VM Cloud Storage destination. Use a disposable SQLite database on the retained disk to perform an online backup, upload, download, and restore to a separate path. Add disk snapshots as a second recovery path. | Restored copy passes `PRAGMA integrity_check`; backup age and location are recorded; disk `autoDelete=false` is confirmed. |
| 6. Observe | Configure an HTTPS uptime alert for `/health` that matches `healthy`, disk/memory telemetry, backup-failure alert, and billing notifications. Record log retention and review logging cost. | Operator receives an intentionally triggered alert; dashboard shows VM, HTTPS, backup age, and spend. |

References: [Terraform remote state](https://docs.cloud.google.com/docs/terraform/resource-management/store-state), [IAP SSH](https://docs.cloud.google.com/compute/docs/connect/ssh-using-iap), [Persistent Disk mount](https://docs.cloud.google.com/compute/docs/disks/format-mount-disk-linux), [Caddy automatic HTTPS](https://caddyserver.com/docs/automatic-https), [SQLite online backup](https://www.sqlite.org/backup.html), [uptime checks](https://docs.cloud.google.com/monitoring/uptime-checks).

### HTTPS certificate owner

Caddy manages certificate issuance and renewal. The public ACME issuer is selected by Caddy's automatic HTTPS behavior; the operator owns DNS, firewall reachability, and preservation of Caddy's `/data` directory. The local simulation's certificate is for `localhost` and is not a public certificate. Release 0 is complete only after a client validates the real domain without bypassing certificate checks. See [Caddy's certificate requirements](https://caddyserver.com/docs/automatic-https).

## Release 1: future application

The app does not exist yet, so this stage remains conditional. Build a versioned Node or Java image, push it to a private [Artifact Registry](https://docs.cloud.google.com/artifact-registry/docs/docker/pushing-and-pulling), and let the VM pull it with a narrowly scoped service account. Add the app service to Compose on the internal network; expose only Caddy on public ports. Mount its SQLite directory from `/srv/cloud-app-data`, run schema migrations with a documented rollback or forward-recovery path, and keep secrets outside the image and repository.

For a Node app, select a supported Node.js security release when building its container, pin the reviewed base image by digest, and record the runtime version in the release record. Run a package vulnerability audit as a separate check; it does not cover vulnerabilities in the Node.js binary. After a Node.js security release, rebuild and publish the application image, record its new digest, and roll it out through Compose. Updating Node.js on the gateway host does not update a containerized app. See the [Node.js security releases](https://nodejs.org/en/blog/vulnerability/october-2026-security-releases) for the current example; recheck supported versions at deployment time.

Before routing traffic to the app, take a fresh off-VM backup and record the prior image digest. Replace the Caddy readiness response with `reverse_proxy` only after the app's health endpoint works locally. Check public HTTPS, normal user flow, restart behavior, backup completion, and resource usage. Roll back the image/Caddy revision if the release fails; database schema changes must have their own compatible rollback or forward-recovery procedure. Source: [Artifact Registry and Compute Engine](https://docs.cloud.google.com/artifact-registry/docs/integrate-compute).

## Stop and rollback rules

- Stop deployment if the data disk is missing, public SSH/database access appears, DNS points elsewhere, TLS is untrusted, or backup/restore fails.
- For a gateway/configuration failure, restore the recorded Git revision and Caddy image digest, keeping the data disk attached. Recheck the mount before restarting Compose.
- For VM loss, provision a replacement from Terraform, attach the retained disk and remount it by UUID, then redeploy the recorded revision. If the disk is unavailable, restore the latest verified off-VM backup to a new disk.
- If cloud costs exceed the reviewed range, stop adding resources and inspect billing before continuing. A stopped VM can still leave billable disks, IPs, snapshots, and storage.

**Release 0 completion:** trusted public HTTPS readiness page; restricted administrative access; retained and correctly mounted data disk; off-VM backup and restore drill; working uptime/backup/billing alerts; recorded resource inventory and recovery instructions. Only then start a real application deployment.
