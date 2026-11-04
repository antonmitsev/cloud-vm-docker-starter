# Cloud VM Docker Starter

A small, application-independent starting point for one Google Cloud Compute Engine VM running Docker Compose. The VM, DNS, Cloudflare-proxied HTTPS entry point, persistent data disk, and monitoring check were set up manually; see the [actual Google Cloud setup](docs/gcp-current-state.md). No application or production database has been deployed. The Terraform files have not been applied to this project.

**Starting from nothing?** Follow the [Bulgarian step-by-step checklist](docs/from-zero-bg.md). It starts before project creation and billing, and gives each console location, action, and pass check. The public [project story](docs/gcp-journey-bg.md) records what happened in the existing environment; the checklist is the repeatable procedure.

## Layout

- [`HANDOFF.md`](HANDOFF.md): current project state and the next session's priorities.
- [`start.sh`](start.sh): first start on a prepared VM; fetches the repository archive without `.git` and starts Compose.
- [`docs/from-zero-bg.md`](docs/from-zero-bg.md): from Google account and billing to disk, Docker, HTTPS, backup checks, uptime alerts, and Cloudflare.
- [`docs/node-apps-bg.md`](docs/node-apps-bg.md): planned separate Node.js project, one container per module, and Caddy path routing through a shared Docker network.
- [`docs/docker-disk-guard-bg.md`](docs/docker-disk-guard-bg.md): install and test the Docker data-disk guard on the VM.
- [`example-applications/`](example-applications/README.md): runnable `gaz` and `mas` Node.js examples; edit one server file and restart only its container.
- [`compose.apps.yaml`](compose.apps.yaml) and [`Caddyfile.apps`](Caddyfile.apps): optional gateway configuration for routing `/gaz` and `/mas` to separate application containers.
- [`compose.gcp-logging.yaml`](compose.gcp-logging.yaml) and [`start-gateway.sh`](start-gateway.sh): GCP logging overlay and gateway restart for the VM using those application routes. See the [example application instructions](example-applications/README.md#cloud-logging-на-настоящата-gcp-vm) before applying.
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

## First start on a prepared VM

After the [checklist](docs/from-zero-bg.md) has prepared the VM, mounted `/srv/cloud-app-data`, installed Docker Compose, opened TCP 80/443, and pointed your chosen DNS name at the VM, run **on the VM**:

```sh
curl -fsSL https://raw.githubusercontent.com/antonmitsev/cloud-vm-docker-starter/main/start.sh -o /tmp/cloud-vm-start.sh
sudo install -m 0755 /tmp/cloud-vm-start.sh /usr/local/sbin/cloud-vm-start
sudo APP_DOMAIN=api.example.com /usr/local/sbin/cloud-vm-start
```

Replace `api.example.com` with your own DNS name. The script fetches the repository archive without Git, writes `/srv/cloud-vm-docker-starter/.env` on first start, checks that the data disk is mounted, then runs `docker compose up -d --force-recreate`. On later runs it keeps the existing `.env`; run `sudo /usr/local/sbin/cloud-vm-start` to deliberately apply the current `main` version. For a fixed source revision use `sudo SOURCE_REF=<full-40-character-commit-id> /usr/local/sbin/cloud-vm-start`. Review updates before running this against a live application. Docker's restart policy handles ordinary VM boots; `start.sh` is for first setup and deliberate redeploys.

Check `https://<your-domain>/health` for `200 healthy` before moving to backup, alerts, and Cloudflare. This repository contains no application or production database.

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
