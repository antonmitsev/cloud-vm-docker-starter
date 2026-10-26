# Google Cloud VM setup

This is the **manual** setup path for a new environment or a replacement Compute Engine VM running Ubuntu 24.04 LTS. The [existing project was built manually](gcp-current-state.md); use its private resource inventory before replacing anything. The [Terraform draft](../infra/README.md) describes some of the same foundation resources but has not been applied or imported and does not exactly match the deployed Cloudflare firewall. Review the current cloud console and pricing before creating billable resources.

## 1. Choose the VM and network

1. Create or select a Google Cloud project with billing enabled. Set a [billing budget alert](https://docs.cloud.google.com/billing/docs/how-to/budgets); alerts do **not** stop charges. Use the [pricing calculator](https://cloud.google.com/products/calculator) for your region, VM, boot disk, data disk, external IPv4 address, snapshots, storage, and expected egress. For the existing project, use the observed `europe-west1` / `europe-west1-b` location; the `europe-west3` values in `infra/terraform.tfvars.example` are illustrative values for a different environment.
2. Create a custom-mode VPC and a subnet in the chosen region with a nonoverlapping private CIDR. The Terraform draft declares `auto_create_subnetworks = false` and one subnet; its name and CIDR defaults are **not** the existing project's private resource inventory. Place the VM only in that subnet and use a dedicated network tag for its firewall rules.
3. Configure an ingress firewall rule for IAP SSH from `35.235.240.0/20` to TCP 22, scoped to the VM tag. Grant the operator the needed [IAP and OS Login permissions](https://docs.cloud.google.com/compute/docs/connect/ssh-using-iap); those IAM grants are outside the Terraform draft. Keep application and database ports closed. For a new direct-HTTPS bootstrap, web ingress on TCP 80/443 must reach Caddy. The draft's web rule permits `0.0.0.0/0`, while the **deployed** firewall permits only [Cloudflare IPv4 ranges](https://www.cloudflare.com/ips/) after the proxy cutover. Review effective and inherited rules; the current HCL must be revised before it can represent that final policy.
4. Reserve a [regional static external IPv4 address](https://docs.cloud.google.com/compute/docs/ip-addresses/reserve-static-external-ip-address) and select it when creating the VM. The address is billable. Its DNS use depends on the chosen route: a direct HTTPS hostname uses an A record; the [deployed API route](cloudflare-single-subdomain-bg.md) uses a CNAME to Cloudflare, whose fallback origin targets this IPv4 address.
5. Create a dedicated VM service account. The Terraform draft attaches it with `cloud-platform` API access scopes and grants `roles/storage.objectCreator` **only on its backup bucket**; access scopes alone do not grant that bucket permission. For a manual build, grant the same narrow bucket role when off-VM uploads are needed. Keep operator IAP/OS Login IAM separate from the VM identity.
6. Create an Ubuntu 24.04 LTS AMD64 VM in the selected zone with a 20 GiB `pd-balanced` boot disk as a starting point. An `e2-small` is the draft default and the observed current size; allow more memory for a JVM app or multiple services. The draft enables OS Login in instance metadata, selects the custom subnet, reserved IP, VM tag, and dedicated service account, and sets VM deletion protection. Set or verify these individually on a manual build. The draft sets boot-disk auto-delete to true; the **separate data disk** must be retained. Check actual usage before final sizing.

References: [VM creation](https://docs.cloud.google.com/compute/docs/create-linux-vm-instance), [SSH access](https://docs.cloud.google.com/compute/docs/connect/ssh-best-practices/login-access), [Caddy certificate requirements](https://caddyserver.com/docs/automatic-https).

## 2. Attach a separate data disk

Create a `pd-balanced` Persistent Disk in the **same zone** as the VM and attach it. The draft and observed environment both use 20 GiB; size a new disk for its actual workload. Set its deletion rule to **keep disk when VM is deleted** (`autoDelete=false`) and verify the VM's disk attachment after creation. The Terraform draft does not express this attachment flag, so the same check is required after a Terraform-created VM. Retention protects data during VM replacement, but it is not a backup and the retained disk remains billable. See [creating a disk](https://docs.cloud.google.com/compute/docs/disks/add-persistent-disk) and [the auto-delete setting](https://docs.cloud.google.com/compute/docs/disks/modify-persistent-disk).

On the VM, identify the **new blank data disk** before formatting anything:

```sh
lsblk -f
ls -l /dev/disk/by-id/google-*
```

Follow Google's [format and mount guide](https://docs.cloud.google.com/compute/docs/disks/format-mount-disk-linux) for that disk. Formatting erases its contents; never format the boot disk or an existing data disk. Mount it at `/srv/cloud-app-data` and add an `/etc/fstab` entry by filesystem UUID, following Google's [persistent device naming guidance](https://docs.cloud.google.com/compute/docs/disks/set-persistent-device-name-in-linux-vm). A typical entry after obtaining the real UUID is:

```text
UUID=<real-data-disk-uuid> /srv/cloud-app-data ext4 defaults 0 2
```

Confirm the mount points at the attached data disk before creating directories:

```sh
findmnt --mountpoint /srv/cloud-app-data
df -h /srv/cloud-app-data
sudo install -d -m 0750 /srv/cloud-app-data/caddy /srv/cloud-app-data/caddy-config
```

The Compose bind mounts use `create_host_path: false` so missing directories do not get created silently. Still check the exact mount point before starting or updating the stack. Before an application goes live, make automatic Compose startup depend on this mount; see the [boot-safety gate](cloud-infra-plan.md#2-host-and-data-disk). Give each future app's data directory ownership matching its container user; do not use mode `777`.

## 3. Install Docker Engine and Compose

Use Docker's current [Ubuntu installation instructions](https://docs.docker.com/engine/install/ubuntu/) to add its official apt repository and install `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, and `docker-compose-plugin`. The convenience script is intended for development and is not the installation path used here.

Check the installation:

```sh
sudo docker version
sudo docker compose version
sudo systemctl status docker
```

Use `sudo docker ...` for operator commands. Membership in the `docker` group grants root-level privileges, so do not add users to it merely to avoid typing `sudo`. Docker and containerd normally start on boot on Ubuntu; the Compose service also has `restart: unless-stopped`. See Docker's [post-install notes](https://docs.docker.com/engine/install/linux-postinstall/).

## 4. Place this repository on the VM

After the chosen DNS route can reach the VM's static address:

```sh
sudo git clone REPOSITORY_URL /srv/cloud-vm-docker-starter
cd /srv/cloud-vm-docker-starter
sudo cp .env.example .env
sudoedit .env
findmnt --mountpoint /srv/cloud-app-data
sudo docker compose config
sudo docker compose up -d
```

Replace `APP_DOMAIN` with your real domain. The readiness page should then answer at `https://<your-domain>/`, and `https://<your-domain>/health` should return `healthy`. Configure the uptime check to request `/health` and match that response. Caddy needs matching DNS, a reachable origin on TCP 80/443 for its certificate flow, and writable persistent `/data`; with Cloudflare in front, also check the separate edge and origin certificates. See [automatic HTTPS](https://caddyserver.com/docs/automatic-https) and the [Cloudflare certificate guide](cloudflare-single-subdomain-bg.md#сертификати-и-подновяване).

The optional `DATA_ROOT`, `BIND_ADDRESS`, and port overrides in `compose.yaml` exist for local simulation. On the VM, leave them unset so Compose uses `/srv/cloud-app-data`, public TCP 80, and public TCP 443. Do not copy `local.env.example` to the VM.

No application is deployed by this step. See [operations](operations.md) before updating the stack.

## 5. Complete the resources outside the Terraform draft

The current environment also has a private backup bucket with seven-day soft delete, a daily data-disk snapshot schedule, a boot-disk schedule shown in the console, a Cloudflare for SaaS route, and an HTTPS uptime check. The draft creates the bucket and its writer IAM membership, but does **not** configure soft delete explicitly, snapshot schedules, DNS/Cloudflare, monitoring, or a periodic SQLite backup. Follow the [observed inventory](gcp-current-state.md) and [backup plan](sqlite-and-backups.md) for those separate tasks; a probe upload and restore do not mean application backups are automated.
