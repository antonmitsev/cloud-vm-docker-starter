#!/usr/bin/env bash
# Apply the gateway configuration for the GCP VM and the example applications.
set -Eeuo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

if (( EUID != 0 )); then
  echo 'Run with sudo on the VM.' >&2
  exit 1
fi

DATA_ROOT=${DATA_ROOT:-/srv/cloud-app-data}
mountpoint -q "$DATA_ROOT" || { echo "Data disk is not mounted at $DATA_ROOT" >&2; exit 1; }
docker network inspect app-edge >/dev/null

compose=(docker compose -f compose.yaml -f compose.apps.yaml -f compose.gcp-logging.yaml)
"${compose[@]}" config --quiet
"${compose[@]}" up -d --force-recreate gateway
"${compose[@]}" ps gateway
echo 'Check the public /health, /gaz/health and /mas/health endpoints.'
