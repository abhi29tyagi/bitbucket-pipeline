#!/bin/bash
set -euo pipefail

: "${DB_DUMP_FILE:?Missing DB_DUMP_FILE}"
: "${DEV_DB_HOST:?Missing DEV_DB_HOST}"
: "${DEV_DB_PORT:?Missing DEV_DB_PORT}"
: "${DEV_DB_USER:?Missing DEV_DB_USER}"
: "${DEV_DB_PASSWORD:?Missing DEV_DB_PASSWORD}"
: "${DEV_DB_NAME:?Missing DEV_DB_NAME}"

if ! command -v mongodump >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    echo "[INFO] mongodump not found; installing mongodb-database-tools via apt-get"
    sudo apt-get update -y >/dev/null
    sudo apt-get install -y mongodb-database-tools mongodb-mongosh >/dev/null || {
      echo "[ERROR] Failed to install MongoDB database tools via apt-get" >&2
      exit 1
    }
  else
    echo "[ERROR] mongodump not found and apt-get unavailable. Install MongoDB database tools." >&2
    exit 1
  fi
fi

CMD=(
  mongodump
  --host "${DEV_DB_HOST}:${DEV_DB_PORT}"
  --db "${DEV_DB_NAME}"
  --archive="${DB_DUMP_FILE}"
)

if [ -n "${DEV_DB_USER:-}" ]; then
  CMD+=(--username "${DEV_DB_USER}")
fi

if [ -n "${DEV_DB_PASSWORD:-}" ]; then
  CMD+=(--password "${DEV_DB_PASSWORD}" --authenticationDatabase admin)
fi

echo "[INFO] Dumping MongoDB database ${DEV_DB_NAME} from ${DEV_DB_HOST}:${DEV_DB_PORT}"
"${CMD[@]}"

