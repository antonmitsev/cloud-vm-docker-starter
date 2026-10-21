# Cloud VM Docker Starter

A small, application-independent starting point for one Google Cloud Compute Engine VM running Docker Compose. It provides a public HTTPS entry point and a persistent data directory for a future Node or Java application. No VM, DNS record, database, or application is created by this repository.

## Layout

- [`docs/google-cloud-vm.md`](docs/google-cloud-vm.md): create the VM, restrict network access, attach and mount a data disk, and install Docker.
- [`compose.yaml`](compose.yaml) and [`Caddyfile`](Caddyfile): a minimal HTTPS readiness page. Replace the Caddy response with a reverse proxy when an application exists.
- [`docs/sqlite-and-backups.md`](docs/sqlite-and-backups.md): mount a future SQLite database directory, take consistent backups, and restore it.
- [`docs/operations.md`](docs/operations.md): start, update, inspect, and recover the Compose stack.
- [`docs/local-simulation.md`](docs/local-simulation.md): exercise the same gateway configuration and a disposable SQLite database locally before renting a VM.
- [`docs/cloud-infra-plan.md`](docs/cloud-infra-plan.md): delivery plan, decisions, review gates, and acceptance criteria for a senior developer setting up the real cloud environment.

## Order of work

1. Review the [VM setup guide](docs/google-cloud-vm.md) and choose a region and machine size using the [Google Cloud pricing calculator](https://cloud.google.com/products/calculator). Create a billing budget alert; an alert is not a spending cap.
2. Provision the VM and its separate data disk. Mount the disk at `/srv/cloud-app-data` before starting Compose.
3. Install Docker Engine and the Compose plugin from Docker's official Ubuntu repository.
4. Point an owned DNS name to the VM, then copy `.env.example` to `.env` and set `APP_DOMAIN`.
5. Create `/srv/cloud-app-data/caddy` and `/srv/cloud-app-data/caddy-config` on the mounted disk; run `sudo docker compose up -d` from this repository on the VM.
6. Check `https://<your-domain>/` for the readiness response. Add the application only after the VM, HTTPS, disk, and backup workflow are understood.

The Compose file intentionally has no application service and no database container. A future app can use SQLite on the mounted data disk; MariaDB can be added if actual requirements call for it. The VM, disks, external IP, snapshots, and traffic are billed separately. This repository contains no credentials; keep real `.env` files and backup archives outside Git.

To try the setup without cloud resources, follow the [local simulation](docs/local-simulation.md). It runs the same Caddyfile and base Compose service with local-only ports and disposable bind mounts. The SQLite probe lives in a separate Compose file and is never part of the VM setup.

## Scope

This starter assumes one Ubuntu 24.04 LTS VM with one locally mounted Persistent Disk, one public domain, and one Compose project. It is not a high-availability setup. Do not share the SQLite file across VMs or put it on NFS.

## Sources

- [Compute Engine VM creation](https://docs.cloud.google.com/compute/docs/create-linux-vm-instance)
- [Docker Engine installation on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [Caddy automatic HTTPS](https://caddyserver.com/docs/automatic-https)
- [SQLite WAL](https://www.sqlite.org/wal.html)
