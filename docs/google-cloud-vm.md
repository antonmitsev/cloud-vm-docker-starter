# Google Cloud VM setup

This guide assumes one Compute Engine VM running Ubuntu 24.04 LTS. It is a manual setup checklist, so review the current cloud console and pricing before creating billable resources. The repository does not provision anything automatically.

## 1. Choose the VM and network

1. Create or select a Google Cloud project with billing enabled. Set a [billing budget alert](https://docs.cloud.google.com/billing/docs/how-to/budgets); alerts do **not** stop charges. Use the [pricing calculator](https://cloud.google.com/products/calculator) for your region, VM, boot disk, data disk, external IPv4 address, snapshots, and expected egress.
2. Create an Ubuntu 24.04 LTS Compute Engine VM. An `e2-small` is an initial size to evaluate for a light Node app; allow more memory for a JVM app or multiple services. A 20 GiB boot disk is a reasonable initial allocation for the OS, Docker images, and logs. Adjust after checking actual usage.
3. Use [OS Login](https://docs.cloud.google.com/compute/docs/connect/ssh-best-practices/login-access) for SSH access, with only the IAM roles needed by the operator. Prefer an SSH firewall rule limited to your current IP or use IAP. Leave application and database ports closed to the internet. Allow inbound TCP 80 and 443 for the HTTPS gateway. Review the effective firewall rules, including rules inherited from the VPC.
4. If the application will use a domain, reserve and attach a [regional static external IPv4 address](https://docs.cloud.google.com/compute/docs/ip-addresses/reserve-static-external-ip-address). Point the domain's A record at it before starting Caddy. A static address avoids changing DNS when the VM is restarted or replaced; external IPv4 is billable.
5. Give the VM service account only the permissions it needs. No Cloud Storage permission is required until off-VM backups are configured.

References: [VM creation](https://docs.cloud.google.com/compute/docs/create-linux-vm-instance), [SSH access](https://docs.cloud.google.com/compute/docs/connect/ssh-best-practices/login-access), [Caddy certificate requirements](https://caddyserver.com/docs/automatic-https).

## 2. Attach a separate data disk

Create a Persistent Disk in the **same zone** as the VM and attach it. Start with a size appropriate for your app, for example 20 GiB. Set its deletion rule to **keep disk when VM is deleted** (`autoDelete=false`). This protects the data during VM replacement, but it is not a backup and the retained disk remains billable. See [creating a disk](https://docs.cloud.google.com/compute/docs/disks/add-persistent-disk) and [the auto-delete setting](https://docs.cloud.google.com/compute/docs/disks/modify-persistent-disk).

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
findmnt /srv/cloud-app-data
df -h /srv/cloud-app-data
sudo install -d -m 0750 /srv/cloud-app-data/caddy /srv/cloud-app-data/caddy-config
```

The Compose bind mounts use `create_host_path: false` so missing directories do not get created silently. Still check `findmnt` before starting or updating the stack. Give each future app's data directory ownership matching its container user; do not use mode `777`.

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

After the DNS A record resolves to the VM:

```sh
sudo git clone https://github.com/example-user/cloud-vm-docker-starter.git /srv/cloud-vm-docker-starter
cd /srv/cloud-vm-docker-starter
sudo cp .env.example .env
sudoedit .env
findmnt /srv/cloud-app-data
sudo docker compose up -d
```

Replace `APP_DOMAIN` with your real domain. The readiness page should then answer at `https://<your-domain>/`, and `https://<your-domain>/health` should return `healthy`. Configure the uptime check to request `/health` and match that response. Caddy needs public TCP 80 and 443, matching DNS, and writable persistent `/data` to issue and renew certificates. See [automatic HTTPS](https://caddyserver.com/docs/automatic-https).

The optional `DATA_ROOT`, `BIND_ADDRESS`, and port overrides in `compose.yaml` exist for local simulation. On the VM, leave them unset so Compose uses `/srv/cloud-app-data`, public TCP 80, and public TCP 443. Do not copy `local.env.example` to the VM.

No application is deployed by this step. See [operations](operations.md) before updating the stack.
