# Local infrastructure simulation

This is a no-cloud integration exercise for Docker Compose, Caddy HTTPS, bind-mounted persistence, and SQLite backup/restore. It uses the production `compose.yaml` and `Caddyfile` with local environment values. `compose.local.yaml` adds a disposable SQLite probe; it is not part of the VM deployment. No application code is needed.

The exercise does **not** reproduce a Compute Engine VM, IAM, cloud firewall, public DNS, external TLS certificate issuance, Persistent Disk attachment, disk snapshots, Cloud Storage, billing, or behavior after physical host failure. Those require a real cloud environment. A full local guest-OS VM would require separate virtualization software such as QEMU/KVM; this exercise only requires Docker.

## Prepare local-only data

From the repository root:

```sh
cp local.env.example local.env
mkdir -p /tmp/cloud-vm-docker-sim/caddy \
  /tmp/cloud-vm-docker-sim/caddy-config \
  /tmp/cloud-vm-docker-sim/sqlite-probe \
  /tmp/cloud-vm-docker-sim/backups
```

If port 8088 or 8443 is occupied, edit `local.env` and change `HTTP_HOST_PORT`, `HTTPS_HOST_PORT`, and the port in `APP_DOMAIN` together. If you change `DATA_ROOT`, create the same four directories there. The local environment binds only to `127.0.0.1` and never uses `/srv/cloud-app-data`.

The commands below use `docker` directly. Prefix the Docker commands with `sudo` if your local account has no access to the Docker daemon; the `curl` commands do not need `sudo`.

## Exercise HTTPS and container recreation

```sh
docker compose --env-file local.env up -d gateway
curl -sSI http://localhost:8088/
curl -kfsS https://localhost:8443/
curl -kfsS https://localhost:8443/health
docker compose --env-file local.env up -d --force-recreate gateway
curl -kfsS https://localhost:8443/
curl -kfsS https://localhost:8443/health
```

The HTTP response should redirect to `https://localhost:8443/`. The root HTTPS response should be `Cloud VM ready`; `/health` should return `healthy` before and after recreation. Other paths return 404, so monitoring can detect a wrong path. Caddy issues a local certificate that the host does not trust by default, which is why this disposable exercise uses `curl -k`. Public certificate issuance is only checked after real DNS and a cloud VM are available. The bind-mounted Caddy data survives recreation. You may also inspect `docker compose --env-file local.env logs gateway`.

## Exercise SQLite persistence and recovery

Each command starts a fresh one-off container. The database and backup files remain in the local bind-mounted directories:

```sh
docker compose --env-file local.env -f compose.yaml -f compose.local.yaml run --rm sqlite_probe write
docker compose --env-file local.env -f compose.yaml -f compose.local.yaml run --rm sqlite_probe read
docker compose --env-file local.env -f compose.yaml -f compose.local.yaml run --rm sqlite_probe backup
docker compose --env-file local.env -f compose.yaml -f compose.local.yaml run --rm sqlite_probe restore-check
```

The `read` count should match `write`; `restore-check` should report the same count and `integrity_check=ok`. The probe uses SQLite WAL and the online backup API. Its backup is deliberately local, so it exercises recovery mechanics but is **not** an off-VM backup. The production [backup guide](sqlite-and-backups.md) still applies.

## Finish

```sh
docker compose --env-file local.env down
```

`down` stops and removes the local gateway container; it does not delete the bind-mounted files. Keep `/tmp/cloud-vm-docker-sim` if you want to inspect persistence again. Remove that **known disposable directory** manually only when you no longer need the simulation data.

References: [Docker Compose environment variables](https://docs.docker.com/compose/how-tos/environment-variables/variable-interpolation/), [Caddy automatic HTTPS](https://caddyserver.com/docs/automatic-https), [SQLite online backup](https://www.sqlite.org/backup.html).
