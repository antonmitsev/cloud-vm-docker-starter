# Cloud infrastructure delivery plan

**Status:** planning reference. The [current environment](gcp-current-state.md) was built manually; the [Terraform draft](../infra/README.md) has not been applied or imported. The delivery phases below describe gates, not the current state of every gate.

**Target:** one Google Cloud Compute Engine VM, Ubuntu 24.04 LTS, Docker Compose, Caddy, one retained Persistent Disk, and an off-VM backup path. The readiness page is live through Cloudflare. Add an application after the infrastructure can be recovered.

## Decisions before paid resources

The senior developer records these values in a short architecture decision record and obtains the owner's review before applying infrastructure changes:

| Decision | Proposed starting point | Evidence to record |
| --- | --- | --- |
| Project, region, zone | Dedicated project; one zone near the intended users | Project ID, region/zone, billing account, data residency need |
| Monthly spend | Estimate the chosen region and exact resources | [Pricing calculator](https://cloud.google.com/products/calculator) export covering VM, two disks, static IPv4, snapshots, storage, logs, and egress |
| Budget control | Alerts at useful thresholds; assess an eligible spend cap separately | Alert recipients, thresholds, and whether a spend cap could pause the service ([budget alerts](https://docs.cloud.google.com/billing/docs/how-to/budgets), [spend caps](https://docs.cloud.google.com/billing/docs/how-to/budgets-spend-caps)) |
| Public name | One owned DNS name and static IPv4 address | Domain, DNS owner, target IP, expected renewal path |
| Recovery targets | Initial proposal: at most 24 hours of data loss and 4 hours to restore service | Owner-approved RPO/RTO; backup frequency and restore procedure that can meet them |
| First app runtime | Node or Java remains open | Memory estimate and image build/deploy method before app rollout |
| Database | SQLite for one low-write app on this VM | Decision below; change only when workload or topology requires it |

This is a single-zone design. A VM or zone outage can interrupt service until a replacement is deployed and data is restored. If the owner needs stronger availability, revise the architecture before creating resources.

## SQLite or MySQL

| Topic | SQLite | MySQL on this VM |
| --- | --- | --- |
| Runtime | Embedded in the application; no separate database server | Separate server/container, credentials, configuration, and patching |
| Memory and small-VM fit | Lower operational overhead | Additional memory and disk activity; size the VM from observed usage |
| Concurrent writes | One writer at a time per database file; WAL allows reads during writes | Better fit for many concurrent writers and multiple application processes |
| Topology | Multiple processes on one host can use the local database file; do not place WAL on a network filesystem | Clients can connect over a network; supports a later split into separate app and database hosts |
| Backup | SQLite online backup API or `.backup`; copy result off the VM | Consistent logical or physical backup plus server-specific restore procedure |
| Portfolio value | Shows pragmatic choice, WAL, transactions, and recovery | Shows client/server SQL administration, connection management, and database operations |

**Recommendation for the first WarrantyPing-sized workload:** start with SQLite on the retained disk. Keep write transactions short, use WAL, and make the reminder job idempotent. Reassess if write contention becomes measurable, the app needs multiple writable hosts, or the data/operations model calls for a managed database. If MySQL is chosen later, plan schema and data migration, new credentials, backup/restore, and a cutover window. Running MySQL in Docker on the same VM has no separate managed-database charge, but may require a larger VM and does not create a second failure domain. Both options need tested backups.

Sources: [SQLite selection guide](https://www.sqlite.org/whentouse.html), [SQLite WAL](https://www.sqlite.org/wal.html), [SQLite backup API](https://www.sqlite.org/backup.html), [MySQL backup policy](https://dev.mysql.com/doc/refman/8.4/en/backup-policy.html).

## Delivery phases

### 1. Reproducible cloud foundation

**Work:** The initial [`infra/` Terraform configuration](../infra/README.md) describes a dedicated network and firewall rules, static IP, VM, boot disk, separate data disk, and backup bucket. Those resources already exist from manual setup in this project. If Terraform management is chosen later, collect the live inventory, reconcile HCL with it, and import selected existing resources into protected remote state. For a separate new environment, enable required APIs and bootstrap a protected state bucket before `terraform init`; enable object versioning and decide a lifecycle rule for old versions. Restrict state access to the operator or deployment identity. Add monitoring resources and the backup job after the host is ready; project/billing bootstrap remains separate.

**Security:** Use OS Login and IAP for SSH. The current VM permits TCP 80/443 only from published Cloudflare IPv4 ranges; `infra/main.tf` still contains an open `0.0.0.0/0` web rule and must be changed before it models this environment. Restrict TCP 22 to IAP. Attach a dedicated VM service account with only the permissions needed for backup upload and selected telemetry. Do not create service-account key files. Review VPC default rules so an inherited public SSH rule does not reopen access. Sources: [OS Login](https://docs.cloud.google.com/compute/docs/connect/ssh-best-practices/login-access), [IAP SSH](https://docs.cloud.google.com/compute/docs/connect/ssh-best-practices/network-access), [VM service accounts](https://docs.cloud.google.com/compute/docs/access/create-enable-service-accounts-for-instances), [Terraform state](https://docs.cloud.google.com/docs/terraform/resource-management/store-state).

**Gate:** For a new environment or future import, the reviewed plan lists every billable resource and proposed change; IAM and firewall rules match the access design. An import plan for the current project must contain no unexplained creation, update, replacement, or destruction. Do not apply until the owner has reviewed the plan and cost impact.

### 2. Host and data disk

**Work:** The Ubuntu VM, data disk, UUID mount, and Docker installation were completed manually. For a separate new environment, verify the exact OS image after creation and the disk attachment's `autoDelete=false` flag before storing data; the Terraform draft does not express that attachment flag. The draft gives the disk `prevent_destroy` and declares VM deletion protection, but these HCL settings do not prove the current manually created resources have the same controls. Record OS updates and Docker upgrades in the runbook. Sources: [disk deletion setting](https://docs.cloud.google.com/compute/docs/disks/modify-persistent-disk), [mount by UUID](https://docs.cloud.google.com/compute/docs/disks/set-persistent-device-name-in-linux-vm), [Docker installation](https://docs.docker.com/engine/install/ubuntu/).

**Boot safety:** Before any app goes live, make Compose startup depend on `/srv/cloud-app-data` being mounted, for example through a systemd unit with `RequiresMountsFor=` plus an explicit mount check. The current bind-mount configuration prevents missing paths from being created automatically, but does not by itself prove the correct disk is mounted.

**Gate:** The disk survives a VM reboot, is mounted at the expected path, and a failed mount cannot redirect app writes to the boot disk. Only operator accounts can administer Docker; no database port is public.

### 3. Gateway and public route

**Work:** Deploy a pinned revision of this repository on the VM. Set a real `APP_DOMAIN` in a root-owned `.env`; leave the local-simulation overrides unset. The current API name uses a [CNAME through Cloudflare](cloudflare-single-subdomain-bg.md), while Cloudflare's fallback origin targets the VM's static IP. Start Caddy, then confirm the public readiness page and both TLS certificate layers. Keep the Caddy `/data` directory on the retained disk. Source: [Caddy automatic HTTPS](https://caddyserver.com/docs/automatic-https).

**Gate:** The public domain serves the expected response over trusted HTTPS, and SSH remains available through the chosen restricted path. Document the deployed Git commit and image digest for rollback.

### 4. Backup and recovery

**Work:** A private Cloud Storage bucket, a daily data-disk snapshot schedule, a boot-disk schedule shown in the console, and a manual SQLite upload/download/restore test already exist. Before storing real application data, implement a periodic online SQLite backup job, set retention/lifecycle rules, and alert on missing or failed backups. The VM backup identity has bucket-level object creation; restoration uses an operator identity. An ordinary disk snapshot is not assumed to be application-consistent. Keep restore instructions in the application repository once its schema exists. Sources: [SQLite online backup](https://www.sqlite.org/backup.html), [snapshot schedules](https://docs.cloud.google.com/compute/docs/disks/scheduled-snapshots), [Cloud Storage lifecycle](https://docs.cloud.google.com/storage/docs/lifecycle).

**Gate:** Restore a backup to a separate database path or replacement VM, run `PRAGMA integrity_check`, and measure elapsed recovery time against the approved RPO/RTO. Verify the disk's `autoDelete=false` setting and record how to reattach it after VM loss.

### 5. Observability and operating handoff

**Work:** The HTTPS uptime check and billing alerts are configured. Add host metrics for disk free space and memory, container restart/log review, and a backup-age alert. The Google Ops Agent can provide VM memory/disk telemetry; set log retention and review ingestion cost. Write a short incident runbook for full disk, failed backup, expired TLS, and VM replacement. Sources: [uptime checks](https://docs.cloud.google.com/monitoring/uptime-checks), [Ops Agent](https://docs.cloud.google.com/monitoring/agent/ops-agent/installation).

**Gate:** A deliberately failed readiness check reaches the operator; a failed backup is visible; resource use and billing are visible in one dashboard. The senior developer hands over project IDs, resource names, the DNS record, backup location, recovery steps, and actual monthly spend after the first billing cycle. Include a Terraform state location only if Terraform is adopted.

## Release sequence and stop conditions

Use the [GCP deployment plan](gcp-deployment-plan.md) for the ordered release steps, evidence to collect, and rollback path.

1. Use the completed [local simulation](local-simulation.md) and [observed cloud inventory](gcp-current-state.md) as the starting evidence.
2. For a separate new environment, record decisions, estimate costs, and obtain owner review before provisioning.
3. In this manually built project, verify access, disk mount, HTTPS, and reboot behavior without applying the draft Terraform configuration.
4. Automate the off-VM backup and repeat a restore drill with the real application schema before storing user data.
5. Add the application in a separate change with its own migration and rollback plan.

Stop rollout if the data disk is not mounted, public SSH or database access is unexpectedly open, HTTPS is untrusted, the backup cannot be restored, or the cost estimate exceeds the owner's approved range. Record the finding and revise the plan before proceeding.
