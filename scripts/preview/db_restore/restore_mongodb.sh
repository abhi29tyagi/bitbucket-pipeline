#!/bin/bash
set -euo pipefail

: "${DB_DUMP_FILE:?Missing DB_DUMP_FILE}"
: "${DB_NAME:?Missing DB_NAME}"
: "${DB_SERVICE_NAME:?Missing DB_SERVICE_NAME}"
: "${DB_USER:?Missing DB_USER}"
: "${DB_PASSWORD:-}"

log_info() { echo "[INFO] $*"; }
log_error() { echo "[ERROR] $*" >&2; }

log_info "Dropping existing MongoDB database ${DB_NAME}"
if [ -n "$DB_PASSWORD" ]; then
  docker compose exec -T "$DB_SERVICE_NAME" mongosh "$DB_NAME" --username "$DB_USER" --password "$DB_PASSWORD" --authenticationDatabase admin --eval "db.dropDatabase()" >/dev/null 2>&1 || true
else
  docker compose exec -T "$DB_SERVICE_NAME" mongosh "$DB_NAME" --eval "db.dropDatabase()" >/dev/null 2>&1 || true
fi

log_info "Copying dump archive into MongoDB container"
CONTAINER_TMP="/tmp/mongodb-restore.archive"
CONTAINER_NAME=$(docker compose ps -q "$DB_SERVICE_NAME" | head -n1)
if [ -z "$CONTAINER_NAME" ]; then
  log_error "MongoDB container not found for service: ${DB_SERVICE_NAME}"
  exit 1
fi
docker cp "$DB_DUMP_FILE" "${CONTAINER_NAME}:${CONTAINER_TMP}"

log_info "Restoring MongoDB archive"
if [ -n "$DB_PASSWORD" ]; then
  docker compose exec -T "$DB_SERVICE_NAME" mongorestore --archive="${CONTAINER_TMP}" --username "$DB_USER" --password "$DB_PASSWORD" --authenticationDatabase admin --db="$DB_NAME"
else
  docker compose exec -T "$DB_SERVICE_NAME" mongorestore --archive="${CONTAINER_TMP}" --db="$DB_NAME"
fi

docker compose exec -T "$DB_SERVICE_NAME" rm -f "${CONTAINER_TMP}" >/dev/null 2>&1 || true
