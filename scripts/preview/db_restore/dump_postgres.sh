#!/bin/bash
set -euo pipefail

: "${DB_DUMP_FILE:?Missing DB_DUMP_FILE}"
: "${DEV_DB_HOST:?Missing DEV_DB_HOST}"
: "${DEV_DB_PORT:?Missing DEV_DB_PORT}"
: "${DEV_DB_USER:?Missing DEV_DB_USER}"
: "${DEV_DB_PASSWORD:?Missing DEV_DB_PASSWORD}"
: "${DEV_DB_NAME:?Missing DEV_DB_NAME}"

if ! command -v pg_dump >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    echo "[INFO] pg_dump not found; installing postgresql-client via apt-get"
    sudo apt-get update -y >/dev/null
    sudo apt-get install -y postgresql-client >/dev/null
  else
    echo "[ERROR] pg_dump not found and apt-get unavailable. Install PostgreSQL client tools." >&2
    exit 1
  fi
fi

echo "[INFO] Dumping PostgreSQL database ${DEV_DB_NAME} from ${DEV_DB_HOST}:${DEV_DB_PORT}"
PGPASSWORD="$DEV_DB_PASSWORD" pg_dump \
  -h "$DEV_DB_HOST" \
  -p "$DEV_DB_PORT" \
  -U "$DEV_DB_USER" \
  -d "$DEV_DB_NAME" \
  -F c \
  -f "$DB_DUMP_FILE"

