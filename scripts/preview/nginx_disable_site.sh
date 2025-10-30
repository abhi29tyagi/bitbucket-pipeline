#!/bin/bash
set -euo pipefail

# shellcheck source=../../utils/lib.sh
. "$(dirname "$0")/../../utils/lib.sh"

# Source common Nginx functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/nginx_common.sh"

# Disable and remove per-host preview Nginx config and reload
require_vars INTERNAL_DNS_ZONE PR_ID_FOR_USE

NGINX_SITES_AVAILABLE=${NGINX_SITES_AVAILABLE:-/etc/nginx/sites-available}
NGINX_SITES_ENABLED=${NGINX_SITES_ENABLED:-/etc/nginx/sites-enabled}

SERVER_NAME="preview-${PR_ID_FOR_USE}-${BITBUCKET_REPO_SLUG}.${INTERNAL_DNS_ZONE}"
CONF_NAME="${SERVER_NAME}.conf"

# Verify Nginx permissions before removing config
if ! verify_nginx_access; then
  log_error "Cannot remove Nginx site due to permission issues"
  exit 1
fi

log_info "Removing nginx site for ${SERVER_NAME}"
rm -f "${NGINX_SITES_ENABLED}/${CONF_NAME}" || true
rm -f "${NGINX_SITES_AVAILABLE}/${CONF_NAME}" || true

# Note: SSL certificates are not removed as they are shared wildcard certificates
# used by all preview environments. They will be cleaned up separately if needed.

if command -v nginx >/dev/null 2>&1; then
  log_info "Validating nginx configuration"
  sudo nginx -t || log_warn "nginx -t failed; proceeding with reload"
fi

log_info "Reloading nginx"
reload_nginx

echo "disabled:${SERVER_NAME}"
