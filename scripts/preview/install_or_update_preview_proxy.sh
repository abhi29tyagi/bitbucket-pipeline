#!/bin/bash
set -euo pipefail

# shellcheck source=../../utils/lib.sh
. "$(dirname "$0")/../../utils/lib.sh"

# Source common Nginx functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/nginx_common.sh"

require_vars INTERNAL_DNS_ZONE

# Fix Nginx permissions before proceeding
if ! verify_nginx_access; then
  log_error "Cannot configure Nginx due to permission issues"
  exit 1
fi

NGINX_SITES_AVAILABLE=${NGINX_SITES_AVAILABLE:-/etc/nginx/sites-available}
NGINX_SITES_ENABLED=${NGINX_SITES_ENABLED:-/etc/nginx/sites-enabled}

if ! command -v nginx >/dev/null 2>&1; then
  if command -v apt >/dev/null 2>&1; then
    log_info "Installing nginx via apt"
    retry 3 3 -- sudo apt update
    retry 3 3 -- sudo apt install -y nginx
  elif command -v yum >/dev/null 2>&1; then
    log_info "Installing nginx via yum"
    retry 3 3 -- sudo yum install -y nginx
  elif command -v dnf >/dev/null 2>&1; then
    log_info "Installing nginx via dnf"
    retry 3 3 -- sudo dnf install -y nginx
  else
    log_error "Unable to install nginx automatically. Please install it manually."
    exit 1
  fi
fi

# Ensure nginx service is enabled and running
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl enable nginx >/dev/null 2>&1 || true
  sudo systemctl start nginx >/dev/null 2>&1 || true
else
  sudo service nginx start >/dev/null 2>&1 || true
fi

# Configure nginx for long domain names (with cleanup)
log_info "Configuring nginx for long domain names"
NGINX_CONF="/etc/nginx/nginx.conf"
if [ -f "$NGINX_CONF" ]; then
  # One-time cleanup: remove any existing server_names_hash_bucket_size directives
  if grep -q "server_names_hash_bucket_size" "$NGINX_CONF"; then
    log_info "Cleaning up existing server_names_hash_bucket_size directives"
    sudo sed -i '/server_names_hash_bucket_size/d' "$NGINX_CONF"
  fi
  
  # Add server_names_hash_bucket_size directive to the http block
  # Try multiple patterns to find the http block
  if sudo sed -i '/^http {/a\    server_names_hash_bucket_size 128;' "$NGINX_CONF" 2>/dev/null; then
    log_info "Added server_names_hash_bucket_size 128 to nginx.conf (pattern: ^http {)"
  elif sudo sed -i '/^http{/a\    server_names_hash_bucket_size 128;' "$NGINX_CONF" 2>/dev/null; then
    log_info "Added server_names_hash_bucket_size 128 to nginx.conf (pattern: ^http{)"
  elif sudo sed -i '/http {/a\    server_names_hash_bucket_size 128;' "$NGINX_CONF" 2>/dev/null; then
    log_info "Added server_names_hash_bucket_size 128 to nginx.conf (pattern: http {)"
  else
    # Fallback: add at the beginning of the file
    echo "    server_names_hash_bucket_size 128;" | sudo tee -a "$NGINX_CONF" >/dev/null
    log_info "Added server_names_hash_bucket_size 128 to nginx.conf (fallback)"
  fi
  
  # Clean up old preview site configurations (only if this is initial setup)
  # Don't remove existing preview sites during peer triggers
  if [ -z "${PR_ID:-}" ] && [ -z "${BITBUCKET_PR_ID:-}" ]; then
    log_info "Cleaning up old preview site configurations (initial setup only)"
    sudo rm -f /etc/nginx/sites-enabled/preview-*.conf
    sudo rm -f /etc/nginx/sites-available/preview-*.conf
    log_info "Old preview site configurations removed"
  else
    log_info "Skipping preview site cleanup (peer trigger detected)"
  fi
else
  log_warn "nginx.conf not found at $NGINX_CONF"
fi

# SSL certificates: Let's Encrypt via Cloudflare (required)
if [ -n "${CLOUDFLARE_API_TOKEN:-}" ] && { [ -n "${FQDN:-}" ] || [ -n "${DOMAIN_NAME:-}" ]; }; then
  log_info "Issuing Let's Encrypt certificate via certbot (Cloudflare DNS)"
  bash "${SCRIPT_DIR}/certbot_cloudflare.sh" || {
    log_error "Certbot issuance failed - Let's Encrypt certificate is required"
    exit 1
  }
  log_info "✅ Let's Encrypt certificate issued and linked for Nginx"
else
  log_error "CLOUDFLARE_API_TOKEN and DOMAIN_NAME (or FQDN) are required for SSL certificate setup"
  log_error "Please set these environment variables and run the setup again"
  exit 1
fi

tmpfile=$(mktemp)
sed "s/__INTERNAL_DNS_ZONE__/${INTERNAL_DNS_ZONE//\./\\.}/g" "$(dirname "$0")/preview-proxy.conf" > "$tmpfile"

sudo mkdir -p "$NGINX_SITES_AVAILABLE" "$NGINX_SITES_ENABLED"
sudo mv "$tmpfile" "$NGINX_SITES_AVAILABLE/preview-proxy"
sudo ln -sf "$NGINX_SITES_AVAILABLE/preview-proxy" "$NGINX_SITES_ENABLED/preview-proxy"

if command -v nginx >/dev/null 2>&1; then
  log_info "Validating nginx configuration"
  sudo nginx -t
fi

log_info "Reloading nginx"
reload_nginx

# Ensure renewal cron is configured (idempotent)
RENEW_SCRIPT_PATH="${SCRIPT_DIR}/certbot_cloudflare_renew.sh"
if [ -f "$RENEW_SCRIPT_PATH" ]; then
  CRON_FILE="/etc/cron.d/certbot-renew"
  CRON_LINE="0 3,15 * * * root /usr/bin/bash $RENEW_SCRIPT_PATH >> /var/log/certbot-renew.log 2>&1"
  if command -v sudo >/dev/null 2>&1; then
    echo "$CRON_LINE" | sudo tee "$CRON_FILE" >/dev/null
  else
    echo "$CRON_LINE" > "$CRON_FILE"
  fi
  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl restart cron 2>/dev/null || sudo systemctl restart crond 2>/dev/null || true
  else
    sudo service cron restart 2>/dev/null || sudo service crond restart 2>/dev/null || true
  fi
  log_info "Certbot renew cron installed/updated at $CRON_FILE"
else
  log_warn "Renew script not found at $RENEW_SCRIPT_PATH; skipping cron setup"
fi
