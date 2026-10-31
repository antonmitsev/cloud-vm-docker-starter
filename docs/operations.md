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

### Check Caddy's origin certificate renewal

Run these commands **on the VM**, after connecting through IAP. Use the actual API hostname in place of `api.example.com`; the public TLS handshake shows Cloudflare's edge certificate, not Caddy's certificate.

```sh
openssl s_client -connect 127.0.0.1:443 -servername api.example.com </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates
openssl s_client -connect 127.0.0.1:443 -servername api.example.com </dev/null 2>/dev/null | openssl x509 -noout -checkend 1209600
cd /srv/cloud-vm-docker-starter
sudo docker compose logs gateway 2>&1 | grep -Ei 'acme|certificate|challenge|renew|error' | tail -80
```

The second command exits nonzero if the certificate expires within 14 days or the certificate cannot be read. Record the current `notAfter` date and repeat the check at least weekly, then daily once the certificate enters its renewal window. [Caddy normally starts trying to renew](https://caddyserver.com/docs/caddyfile/directives/tls) with about one third of the certificate's lifetime left, though the CA may specify a different window. After renewal, confirm that the **origin** `notAfter` date has moved forward and that the logs show successful issuance without unresolved challenge errors. An unchanged date before the renewal window is expected; an unchanged date near expiry needs investigation. Keep the 14-day check as an alert threshold when VM-side monitoring is added. The existing public uptime check detects an expired origin certificate only after [Cloudflare starts rejecting it](https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/full-strict/), so it is not an advance-expiry alert.

If renewal fails, inspect the Caddy logs and confirm that Cloudflare passes `/.well-known/acme-challenge/` requests to Caddy on port 80 without a [WAF challenge, Worker interception, or redirect rule](https://developers.cloudflare.com/ssl/edge-certificates/changing-dcv-method/troubleshooting/). [Caddy can fall back](https://caddyserver.com/docs/automatic-https#acme-challenges) from TLS-ALPN-01 to HTTP-01, but a normal request for a nonexistent challenge token is not proof that a real ACME validation succeeded. Do not remove the stored certificate or repeatedly request production certificates just to test the path; use an [ACME staging endpoint](https://caddyserver.com/docs/automatic-https#testing) for a controlled issuance test.

To remove Cloudflare from the request path, [follow the direct-HTTPS rollback](cloudflare-single-subdomain-bg.md#връщане-към-директен-https-без-cloudflare): verify Caddy's certificate, reopen public TCP 80/443 in GCP, test the origin directly with the API hostname and SNI, then replace only the API CNAME with an A record at the primary DNS provider. No new certificate setup is needed while Caddy's existing certificate remains valid.

## Recovery boundaries

- Recreating a container retains the bind-mounted data. Deleting the VM retains the separate data disk only when its `autoDelete` setting is disabled.
- If the VM is replaced, attach the retained disk to the new VM, mount it at `/srv/cloud-app-data`, then start Compose. Update the proxied fallback-origin DNS record or its static IP target as needed; the public API CNAME at the original DNS provider normally stays unchanged. Recheck Cloudflare health and direct-IP blocking.
- Keep independent backups. A retained disk and a disk snapshot do not replace a tested SQLite backup workflow.
- Do not run `docker compose down --volumes` or broad Docker prune commands as routine cleanup. Inspect what they would remove first.

References: [Docker Compose services and bind mounts](https://docs.docker.com/reference/compose-file/services/), [Persistent Disk deletion behavior](https://docs.cloud.google.com/compute/docs/disks/modify-persistent-disk), [SQLite online backup](https://www.sqlite.org/backup.html).
