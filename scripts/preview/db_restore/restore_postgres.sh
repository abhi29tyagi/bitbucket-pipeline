#!/bin/bash
set -euo pipefail

: "${DB_DUMP_FILE:?Missing DB_DUMP_FILE}"
: "${DB_NAME:?Missing DB_NAME}"
: "${DB_SERVICE_NAME:?Missing DB_SERVICE_NAME}"
: "${DB_USER:?Missing DB_USER}"
: "${DB_PASSWORD:-}"

log_info() { echo "[INFO] $*"; }
log_error() { echo "[ERROR] $*" >&2; }

log_info "Dropping and recreating PostgreSQL database ${DB_NAME}"
docker compose exec -T "$DB_SERVICE_NAME" psql -U "$DB_USER" -c "DROP DATABASE IF EXISTS ${DB_NAME};" postgres >/dev/null 2>&1 || true
docker compose exec -T "$DB_SERVICE_NAME" psql -U "$DB_USER" -c "CREATE DATABASE ${DB_NAME};" postgres >/dev/null 2>&1 || {
  log_error "Failed to create database ${DB_NAME}"
  exit 1
}

if file "$DB_DUMP_FILE" | grep -qi "PostgreSQL custom"; then
  log_info "Restoring PostgreSQL custom-format dump"
  docker compose exec -T -e PGPASSWORD="$DB_PASSWORD" "$DB_SERVICE_NAME" pg_restore -U "$DB_USER" -d "$DB_NAME" < "$DB_DUMP_FILE"
else
  log_info "Restoring PostgreSQL SQL dump"
  docker compose exec -T -e PGPASSWORD="$DB_PASSWORD" "$DB_SERVICE_NAME" psql -U "$DB_USER" -d "$DB_NAME" < "$DB_DUMP_FILE"
fi
