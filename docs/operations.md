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

## Recovery boundaries

- Recreating a container retains the bind-mounted data. Deleting the VM retains the separate data disk only when its `autoDelete` setting is disabled.
- If the VM is replaced, attach the retained disk to the new VM, mount it at `/srv/cloud-app-data`, then start Compose. Point DNS or the static IP at the replacement VM as needed.
- Keep independent backups. A retained disk and a disk snapshot do not replace a tested SQLite backup workflow.
- Do not run `docker compose down --volumes` or broad Docker prune commands as routine cleanup. Inspect what they would remove first.

References: [Docker Compose services and bind mounts](https://docs.docker.com/reference/compose-file/services/), [Persistent Disk deletion behavior](https://docs.cloud.google.com/compute/docs/disks/modify-persistent-disk), [SQLite online backup](https://www.sqlite.org/backup.html).
