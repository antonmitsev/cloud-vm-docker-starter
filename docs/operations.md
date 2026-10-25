# Operations

Run these commands from `/srv/cloud-vm-docker-starter` on the VM. Before any start or update, confirm the data disk is mounted:

```sh
findmnt /srv/cloud-app-data
sudo docker compose ps
sudo docker compose logs --tail=100 gateway
```

`findmnt` must show `/srv/cloud-app-data` as its own mount point. If it does not, fix the disk mount before starting containers. The Compose file refuses to create missing bind source directories, but an unexpected host directory can still hide a failed disk mount.

## Start and update

```sh
sudo docker compose up -d
sudo docker compose pull
sudo docker compose up -d
```

The first command starts the current configuration. The next two pull and apply updated images when an update is intended. Review release notes and keep a backup before changing images or application database schema. `caddy:2` follows current Caddy 2 releases when pulled; record the deployed image digest if exact rollback is required.

For configuration changes, update the repository checkout, then run `sudo docker compose up -d`. Check `sudo docker compose ps`, the gateway logs, and the HTTPS URL. Application-specific deploy and migration steps belong to the application repository.

## Cloudflare and origin access

The deployed API hostname uses Cloudflare for SaaS through a separate Free-plan domain; the primary domain's authoritative DNS stays with its existing provider. The GCP web firewall rule permits TCP 80/443 only from the [current Cloudflare IPv4 ranges](https://www.cloudflare.com/ips/). The former `0.0.0.0/0` web rule is disabled; IAP SSH remains separate. See the [single-subdomain setup and verification guide](cloudflare-single-subdomain-bg.md) and [observed project state](gcp-current-state.md).

After an origin IP, DNS, certificate, or firewall change, check the public `/health` response for `200 healthy` and `cf-ray`, then test a fresh direct connection to the VM's public IP on ports 80 and 443. A direct connection should time out from a non-Cloudflare source. Keep the old broad web rule disabled after a successful check. If Cloudflare changes its published address ranges, update the allowlist before removing old ranges. An IP allowlist does not authenticate this specific Cloudflare account and does not cap spend from requests that Cloudflare forwards to the VM.

Cloudflare renews the visitor-facing custom-hostname certificate; Caddy renews the separate origin certificate. Check Cloudflare's certificate status and Caddy's ACME renewal logs and expiry independently. Caddy's HTTP-01 challenge needs a working port-80 path through Cloudflare; a public `200` from the edge alone does not prove the origin certificate will renew. See [certificate renewal details](cloudflare-single-subdomain-bg.md#сертификати-и-подновяване).

## Recovery boundaries

- Recreating a container retains the bind-mounted data. Deleting the VM retains the separate data disk only when its `autoDelete` setting is disabled.
- If the VM is replaced, attach the retained disk to the new VM, mount it at `/srv/cloud-app-data`, then start Compose. Update the proxied fallback-origin DNS record or its static IP target as needed; the public API CNAME at the original DNS provider normally stays unchanged. Recheck Cloudflare health and direct-IP blocking.
- Keep independent backups. A retained disk and a disk snapshot do not replace a tested SQLite backup workflow.
- Do not run `docker compose down --volumes` or broad Docker prune commands as routine cleanup. Inspect what they would remove first.

References: [Docker Compose services and bind mounts](https://docs.docker.com/reference/compose-file/services/), [Persistent Disk deletion behavior](https://docs.cloud.google.com/compute/docs/disks/modify-persistent-disk), [SQLite online backup](https://www.sqlite.org/backup.html).
