#!/usr/bin/env bash
# First start or deliberate redeploy on an already prepared Ubuntu VM.
set -Eeuo pipefail

DEPLOY_DIR=/srv/cloud-vm-docker-starter
DATA_ROOT=/srv/cloud-app-data
SOURCE_REF=${SOURCE_REF:-main}
REPOSITORY=antonmitsev/cloud-vm-docker-starter

if (( EUID != 0 )); then
  echo 'Run with sudo on the VM.' >&2
  exit 1
fi

if [[ ! "$SOURCE_REF" =~ ^(main|[0-9a-fA-F]{40})$ ]]; then
  echo 'SOURCE_REF must be main or a full 40-character commit ID.' >&2
  exit 1
fi

for command in curl tar mountpoint docker; do
  command -v "$command" >/dev/null || { echo "Missing prerequisite: $command" >&2; exit 1; }
done
docker compose version >/dev/null
mountpoint -q "$DATA_ROOT" || { echo "Data disk is not mounted at $DATA_ROOT" >&2; exit 1; }

if [[ ! -f "$DEPLOY_DIR/.env" ]]; then
  if [[ ! "${APP_DOMAIN:-}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ || "${APP_DOMAIN:-}" != *.* ]]; then
    echo 'First start needs APP_DOMAIN=app.example.com (a real DNS name you control).' >&2
    exit 1
  fi
fi

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

if [[ "$SOURCE_REF" == main ]]; then
  archive_url="https://codeload.github.com/$REPOSITORY/tar.gz/refs/heads/main"
else
  archive_url="https://codeload.github.com/$REPOSITORY/tar.gz/$SOURCE_REF"
fi

curl --fail --location --silent --show-error --retry 3 --connect-timeout 10 --max-time 120 "$archive_url" -o "$workdir/source.tar.gz"
mkdir "$workdir/source"
tar -xzf "$workdir/source.tar.gz" -C "$workdir/source" --strip-components=1
test -f "$workdir/source/compose.yaml"
test -f "$workdir/source/Caddyfile"
test -f "$workdir/source/start.sh"

install -d -m 0755 "$DEPLOY_DIR"
shopt -s dotglob nullglob
for entry in "$workdir/source"/*; do
  [[ "$entry" == "$workdir/source/start.sh" ]] && continue
  cp -a "$entry" "$DEPLOY_DIR/"
done
install -m 0755 "$workdir/source/start.sh" "$DEPLOY_DIR/.start.sh.next"
mv -f "$DEPLOY_DIR/.start.sh.next" "$DEPLOY_DIR/start.sh"
if [[ ! -f "$DEPLOY_DIR/.env" ]]; then
  printf 'APP_DOMAIN=%s\n' "$APP_DOMAIN" > "$workdir/.env"
  install -m 0600 "$workdir/.env" "$DEPLOY_DIR/.env"
fi
unset APP_DOMAIN
install -d -m 0750 "$DATA_ROOT/caddy" "$DATA_ROOT/caddy-config"

cd "$DEPLOY_DIR"
docker compose config --quiet
docker compose up -d --force-recreate
docker compose ps
echo "Project: $DEPLOY_DIR"
echo 'Next: check HTTPS /health and the Caddy logs as shown in the checklist.'
