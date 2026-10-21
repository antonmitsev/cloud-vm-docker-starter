# SQLite persistence and backups

SQLite is suitable for a small application on a single VM. Keep its database in a directory on the attached Persistent Disk, mounted into the application container. Docker container replacement then leaves the database intact. In WAL mode, the database and its `-wal` and `-shm` files must be on the same host directory; WAL supports concurrent readers but only one writer at a time. Do not put the database on NFS or mount the same database read/write on multiple VMs. See [SQLite WAL](https://www.sqlite.org/wal.html) and [Docker bind mounts](https://docs.docker.com/engine/storage/bind-mounts/).

## Add a future application

Create its directory **after** confirming `/srv/cloud-app-data` is mounted. Set ownership for the UID/GID used by the application image. Add a service like this to `compose.yaml` when the image exists; replace the image name, port, and database path with the application's actual values:

```yaml
services:
  app:
    image: ghcr.io/your-org/your-app:replace-with-version
    restart: unless-stopped
    environment:
      DATABASE_PATH: /app/data/app.sqlite
    volumes:
      - type: bind
        source: /srv/cloud-app-data/app
        target: /app/data
        bind:
          create_host_path: false
```

Do not publish the app's internal port with `ports`. In `Caddyfile`, replace the readiness response with `reverse_proxy app:3000` after confirming the app listens on port 3000 inside the Compose network. The exact port depends on the app. Keep secrets outside the image and Git; restrict access to the VM's `.env` or use a dedicated secret mechanism.

## Make a consistent backup

A disk is persistent storage, not a second copy. For a running SQLite database, use the SQLite [online backup API](https://www.sqlite.org/backup.html), for example the `sqlite3` shell's `.backup` command. Do not copy only `app.sqlite` while the app is writing in WAL mode.

Example on the VM, after installing the `sqlite3` CLI and substituting the actual paths:

```sh
sudo install -d -m 0700 /var/backups/cloud-app
sudo sqlite3 /srv/cloud-app-data/app/app.sqlite ".backup '/var/backups/cloud-app/app-YYYYMMDD.sqlite'"
sudo sqlite3 /var/backups/cloud-app/app-YYYYMMDD.sqlite 'PRAGMA integrity_check;'
```

Replace `YYYYMMDD` with the actual date and confirm `integrity_check` returns `ok`. Store the resulting backup **outside the VM and outside the data disk**: for example, upload it to a private Cloud Storage bucket with narrowly scoped access, or securely copy it to another machine. Apply a retention policy and periodically practice restoring to a separate location. A local `.backup` file alone does not protect against VM or project loss. [Persistent Disk snapshots](https://docs.cloud.google.com/compute/docs/disks/snapshots) can complement the database backup, but the online SQLite backup is the application-consistent copy.

## Restore

1. Stop the application service, while leaving the HTTPS gateway available if desired: `sudo docker compose stop app`.
2. Confirm the data disk is mounted with `findmnt /srv/cloud-app-data`.
3. Save the current database and any WAL files for investigation. Copy the chosen standalone backup to the application's database path; set its ownership to the application container's UID/GID. Do not mix old `-wal` or `-shm` files with the restored database.
4. Check the restored file with `sqlite3 /srv/cloud-app-data/app/app.sqlite 'PRAGMA integrity_check;'`, then start the app with `sudo docker compose up -d app`.

The exact restore commands depend on the application's database filename, user ID, and recovery requirements; document them in the application repository before handling real user data.
