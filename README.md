# Cloud VM Docker Starter

A small, application-independent starting point for one Google Cloud Compute Engine VM running Docker Compose. The VM, DNS, Cloudflare-proxied HTTPS entry point, persistent data disk, and monitoring check were set up manually; see the [actual Google Cloud setup](docs/gcp-current-state.md). No application or production database has been deployed. The Terraform files have not been applied to this project.

## Layout

- [`HANDOFF.md`](HANDOFF.md): current project state and the next session's priorities.
- [`docs/google-cloud-vm.md`](docs/google-cloud-vm.md): create the VM, restrict network access, attach and mount a data disk, and install Docker.
- [`compose.yaml`](compose.yaml) and [`Caddyfile`](Caddyfile): a minimal HTTPS readiness page at `/` and a dedicated `/health` endpoint. Route application traffic and health checks to the app when it exists.
- [`docs/sqlite-and-backups.md`](docs/sqlite-and-backups.md): mount a future SQLite database directory, take consistent backups, and restore it.
- [`docs/operations.md`](docs/operations.md): start, update, inspect, and recover the Compose stack.
- [`docs/local-simulation.md`](docs/local-simulation.md): exercise the same gateway configuration and a disposable SQLite database locally before renting a VM.
- [`docs/cloud-infra-plan.md`](docs/cloud-infra-plan.md): delivery plan, decisions, review gates, and acceptance criteria for a senior developer setting up the real cloud environment.
- [`docs/gcp-deployment-plan.md`](docs/gcp-deployment-plan.md): ordered release plan from a reviewed GCP project to a public HTTPS readiness page, followed by an application deployment later.
- [`docs/gcp-current-state.md`](docs/gcp-current-state.md): record of the manually created GCP resources, observed checks, access commands, and remaining work.
- [`docs/gcp-journey-bg.md`](docs/gcp-journey-bg.md): Bulgarian walkthrough of the manual setup, from project and budget through DNS, HTTPS, backups, and monitoring.
- [`docs/cloudflare-single-subdomain-bg.md`](docs/cloudflare-single-subdomain-bg.md): Bulgarian guide to proxying one subdomain on Cloudflare Free while keeping the primary domain's DNS provider, then restricting direct origin access.
- [`infra/`](infra/README.md): unapplied Terraform draft, differences from the manually built environment, and a future import path.

## Setup order for a new environment

1. Review the [VM setup guide](docs/google-cloud-vm.md) and choose a region and machine size using the [Google Cloud pricing calculator](https://cloud.google.com/products/calculator). Create a billing budget alert; an alert is not a spending cap.
2. For a new environment, use the [manual VM guide](docs/google-cloud-vm.md) or adapt and review the [Terraform draft](infra/README.md) for the chosen firewall and DNS route before applying it. Confirm the separate data disk survives VM deletion, then mount it at `/srv/cloud-app-data` before starting Compose.
3. Install Docker Engine and the Compose plugin from Docker's official Ubuntu repository.
4. Choose a direct DNS A record or the [documented Cloudflare route](docs/cloudflare-single-subdomain-bg.md) to the VM, then copy `.env.example` to `.env` and set `APP_DOMAIN`.
5. Create `/srv/cloud-app-data/caddy` and `/srv/cloud-app-data/caddy-config` on the mounted disk; run `sudo docker compose up -d` from this repository on the VM.
6. Check `https://<your-domain>/` for the readiness response and `https://<your-domain>/health` for `healthy`. Point the uptime check at `/health`. Add the application only after the VM, HTTPS, disk, and backup workflow are understood.

The Compose file intentionally has no application service and no database container. A future app can use SQLite on the mounted data disk; MariaDB can be added if actual requirements call for it. The VM, disks, external IP, snapshots, and traffic are billed separately. This repository contains no credentials; keep real `.env` files and backup archives outside Git.

The gateway VM does not need a host-installed Node.js runtime. If a Node application is added later, build it with a supported, patched Node.js container image, audit its npm dependencies separately, and publish a new image after runtime security releases. See the [future application release plan](docs/gcp-deployment-plan.md).

To try the setup without cloud resources, follow the [local simulation](docs/local-simulation.md). It runs the same Caddyfile and base Compose service with local-only ports and disposable bind mounts. The SQLite probe lives in a separate Compose file and is never part of the VM setup.

## Scope

This starter assumes one Ubuntu 24.04 LTS VM with one locally mounted Persistent Disk, one public domain, and one Compose project. It is not a high-availability setup. Do not share the SQLite file across VMs or put it on NFS.

## Sources

- [Compute Engine VM creation](https://docs.cloud.google.com/compute/docs/create-linux-vm-instance)
- [Docker Engine installation on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [Caddy automatic HTTPS](https://caddyserver.com/docs/automatic-https)
- [SQLite WAL](https://www.sqlite.org/wal.html)
