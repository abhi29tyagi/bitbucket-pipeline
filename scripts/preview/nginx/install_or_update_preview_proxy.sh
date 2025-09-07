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
