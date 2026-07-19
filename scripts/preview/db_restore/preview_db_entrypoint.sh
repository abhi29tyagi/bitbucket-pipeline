#!/bin/bash
# Restore dev database dump in preview environments
# This script is called after docker-compose up but before the app starts serving traffic

set -euo pipefail

# Source utility functions if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/../../utils/lib.sh" ]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/../../utils/lib.sh"
else
  log_info() { echo "[INFO] $*"; }
  log_error() { echo "[ERROR] $*" >&2; }
  log_warn() { echo "[WARN] $*"; }
fi

# Only run in preview environments
if [ "${TARGET_ENV:-preview}" != "preview" ]; then
  log_info "Skipping database restore: only runs in preview environments (TARGET_ENV=${TARGET_ENV:-<unset>})"
  exit 0
fi

# Require dev dump flag
if [ "${DB_DUMP_FROM_DEV:-false}" != "true" ]; then
  log_info "Skipping database restore: DB_DUMP_FROM_DEV=${DB_DUMP_FROM_DEV:-false}"
  exit 0
fi

# Validate required variables
: "${DB_TYPE:?Missing DB_TYPE (postgres, mysql, mariadb, mongodb)}"
: "${DB_SERVICE_NAME:?Missing DB_SERVICE_NAME (name of database service in docker-compose)}"
: "${DB_NAME:?Missing DB_NAME (database name to restore into)}"
: "${DEV_DB_SOURCE:?Missing DEV_DB_SOURCE (format: dev-db://host:port)}"
: "${DEV_DB_USER:?Missing DEV_DB_USER (dev database username)}"
: "${DEV_DB_PASSWORD:?Missing DEV_DB_PASSWORD (dev database password)}"
: "${DEV_DB_NAME:?Missing DEV_DB_NAME (dev database name)}"

log_info "Starting database restore for preview environment"
log_info "DB_TYPE=${DB_TYPE}, DB_SERVICE_NAME=${DB_SERVICE_NAME}, DB_NAME=${DB_NAME}"

# Set preview DB defaults based on database type
case "${DB_TYPE}" in
  postgres|postgresql)
    DB_USER="${DB_USER:-postgres}"
    DB_PORT="${DB_PORT:-5432}"
    ;;
  mysql|mariadb)
    DB_USER="${DB_USER:-root}"
    DB_PORT="${DB_PORT:-3306}"
    ;;
  mongodb)
    DB_USER="${DB_USER:-admin}"
    DB_PORT="${DB_PORT:-27017}"
    ;;
  *)
    log_error "Unsupported DB_TYPE: ${DB_TYPE}"
    exit 1
    ;;
esac

# Get preview DB password from container env if not provided
DB_PASSWORD="${DB_PASSWORD:-}"
if [ -z "$DB_PASSWORD" ]; then
  DB_PASSWORD=$(docker compose exec -T "$DB_SERVICE_NAME" printenv DB_PASSWORD 2>/dev/null || true)
  if [ -z "$DB_PASSWORD" ]; then
    DB_PASSWORD=$(docker compose exec -T "$DB_SERVICE_NAME" printenv POSTGRES_PASSWORD MYSQL_ROOT_PASSWORD MONGODB_PASSWORD 2>/dev/null | head -n1 || true)
  fi
fi

# Wait for preview DB to be ready
log_info "Waiting for database service '${DB_SERVICE_NAME}' to be healthy..."
MAX_WAIT=60
WAIT_COUNT=0
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
  if docker compose ps "$DB_SERVICE_NAME" | grep -q "Up.*healthy"; then
    case "${DB_TYPE}" in
      postgres|postgresql)
        if docker compose exec -T "$DB_SERVICE_NAME" pg_isready -U "$DB_USER" >/dev/null 2>&1; then
          log_info "Database is ready"
          break
        fi
        ;;
      mysql|mariadb)
        if docker compose exec -T "$DB_SERVICE_NAME" mysqladmin ping -u "$DB_USER" ${DB_PASSWORD:+-p"$DB_PASSWORD"} >/dev/null 2>&1; then
          log_info "Database is ready"
          break
        fi
        ;;
      mongodb)
        if docker compose exec -T "$DB_SERVICE_NAME" mongosh --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
          log_info "Database is ready"
          break
        fi
        ;;
    esac
  fi
  WAIT_COUNT=$((WAIT_COUNT + 1))
  sleep 2
done

if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
  log_error "Database service '${DB_SERVICE_NAME}' did not become healthy within ${MAX_WAIT}s"
  exit 1
fi

# Prepare dump file path
DUMP_FILE="/tmp/preview-db-restore.${DB_TYPE}.dump"
DUMP_COMPRESSION="${DB_DUMP_COMPRESSION:-auto}"

# Parse dev DB source
if [[ "${DEV_DB_SOURCE}" != dev-db://* ]]; then
  log_error "DEV_DB_SOURCE must use format dev-db://host:port"
  exit 1
fi
DEV_DB_HOST_PORT="${DEV_DB_SOURCE#dev-db://}"
DEV_DB_HOST="${DEV_DB_HOST_PORT%%:*}"
DEV_DB_PORT_VALUE="${DEV_DB_HOST_PORT##*:}"
if [ "$DEV_DB_PORT_VALUE" = "$DEV_DB_HOST_PORT" ]; then
  DEV_DB_PORT_VALUE=""
fi
DEV_DB_PORT="${DEV_DB_PORT_VALUE:-${DB_PORT}}"

log_info "Dumping from dev database: ${DEV_DB_HOST}:${DEV_DB_PORT}/${DEV_DB_NAME}"

# Select helper scripts
case "${DB_TYPE}" in
  postgres|postgresql)
    DUMP_SCRIPT="${SCRIPT_DIR}/dump_postgres.sh"
    RESTORE_SCRIPT="${SCRIPT_DIR}/restore_postgres.sh"
    ;;
  mongodb)
    DUMP_SCRIPT="${SCRIPT_DIR}/dump_mongodb.sh"
    RESTORE_SCRIPT="${SCRIPT_DIR}/restore_mongodb.sh"
    ;;
  *)
    log_error "Unsupported DB_TYPE for helper scripts: ${DB_TYPE} (supported: postgres, mongodb)"
    exit 1
    ;;
esac

for helper in "$DUMP_SCRIPT" "$RESTORE_SCRIPT"; do
  if [ ! -x "$helper" ]; then
    log_error "Helper script not found or not executable: ${helper}"
    exit 1
  fi
done

log_info "Running dump script: ${DUMP_SCRIPT}"
DB_DUMP_FILE="$DUMP_FILE" \
  DEV_DB_HOST="$DEV_DB_HOST" \
  DEV_DB_PORT="$DEV_DB_PORT" \
  DEV_DB_USER="$DEV_DB_USER" \
  DEV_DB_PASSWORD="$DEV_DB_PASSWORD" \
  DEV_DB_NAME="$DEV_DB_NAME" \
  bash "$DUMP_SCRIPT"

log_info "✅ Dump completed from dev database"

# Detect compression
if [ "$DUMP_COMPRESSION" = "auto" ]; then
  if file "$DUMP_FILE" | grep -qi "gzip"; then
    DUMP_COMPRESSION="gzip"
  elif file "$DUMP_FILE" | grep -qi "bzip2"; then
    DUMP_COMPRESSION="bzip2"
  elif file "$DUMP_FILE" | grep -qi "xz"; then
    DUMP_COMPRESSION="xz"
  else
    DUMP_COMPRESSION="none"
  fi
  log_info "Detected compression: ${DUMP_COMPRESSION}"
fi

if [ "$DUMP_COMPRESSION" != "none" ]; then
  log_info "Decompressing dump (${DUMP_COMPRESSION})..."
  case "$DUMP_COMPRESSION" in
    gzip)
      gunzip -c "$DUMP_FILE" > "${DUMP_FILE}.decompressed"
      ;;
    bzip2)
      bunzip2 -c "$DUMP_FILE" > "${DUMP_FILE}.decompressed"
      ;;
    xz)
      xzcat "$DUMP_FILE" > "${DUMP_FILE}.decompressed"
      ;;
    *)
      log_error "Unsupported compression type: ${DUMP_COMPRESSION}"
      exit 1
      ;;
  esac
  mv "${DUMP_FILE}.decompressed" "$DUMP_FILE"
fi

# Restore database via helper script
log_info "Restoring database '${DB_NAME}' into service '${DB_SERVICE_NAME}' using ${RESTORE_SCRIPT}..."
DB_DUMP_FILE="$DUMP_FILE" \
  DB_NAME="$DB_NAME" \
  DB_SERVICE_NAME="$DB_SERVICE_NAME" \
  DB_USER="$DB_USER" \
  DB_PASSWORD="$DB_PASSWORD" \
  bash "$RESTORE_SCRIPT"

# Cleanup dump artifacts
rm -f "$DUMP_FILE" "${DUMP_FILE}.decompressed" 2>/dev/null || true

log_info "✅ Database restore completed successfully"
