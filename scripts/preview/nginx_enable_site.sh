#!/bin/bash
set -euo pipefail

# shellcheck source=../../utils/lib.sh
. "$(dirname "$0")/../../utils/lib.sh"

# Source common Nginx functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/nginx_common.sh"

# Dynamically create per-host preview Nginx config and enable it
require_vars INTERNAL_DNS_ZONE PR_ID_FOR_USE

# Optional overrides; default to common paths
NGINX_SITES_AVAILABLE=${NGINX_SITES_AVAILABLE:-/etc/nginx/sites-available}
NGINX_SITES_ENABLED=${NGINX_SITES_ENABLED:-/etc/nginx/sites-enabled}

# Determine target application port: prefer preview_port.txt, then PORT env, then auto
if [ -f preview_port.txt ]; then
  PORT=$(cat preview_port.txt)
else
  PORT=${PORT:-}
  if [ -z "${PORT}" ]; then
    PORT_BASE=${PREVIEW_PORT_BASE:-40000}
    PORT=$((PORT_BASE + PR_ID_FOR_USE))
  fi
fi

SERVER_NAME="preview-${PR_ID_FOR_USE}-${BITBUCKET_REPO_SLUG}.${INTERNAL_DNS_ZONE}"
CONF_NAME="${SERVER_NAME}.conf"

# Verify Nginx permissions before creating config
if ! verify_nginx_access; then
  log_error "Cannot create Nginx site due to permission issues"
  exit 1
fi

# Validate SSL certificates are available
if ! validate_ssl_certificates; then
  log_error "SSL certificates not available"
  log_error "Run one-time setup: install_or_update_preview_proxy.sh to provision certs first"
  exit 1
fi

# Set SSL file paths
SSL_DIR="/etc/ssl/preview-certs"
CERT_FILE="${SSL_DIR}/wildcard.crt"
KEY_FILE="${SSL_DIR}/wildcard.key"

# Ensure nginx is configured for long domain names (with cleanup)
log_info "Ensuring nginx is configured for long domain names"
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
  
  # Reload nginx to apply the new configuration
  reload_nginx
else
  log_warn "nginx.conf not found at $NGINX_CONF"
fi

log_info "Creating nginx site for ${SERVER_NAME} -> 127.0.0.1:${PORT} (with SSL)"
cat >"${NGINX_SITES_AVAILABLE}/${CONF_NAME}" <<EOF
# HTTP server - redirect to HTTPS
server {
    listen 80;
    server_name ${SERVER_NAME};
    
    # Redirect all HTTP traffic to HTTPS
    return 301 https://\$server_name\$request_uri;
}

# HTTPS server
server {
    listen 443 ssl http2;
    server_name ${SERVER_NAME};
    
    # SSL configuration
    ssl_certificate ${CERT_FILE};
    ssl_certificate_key ${KEY_FILE};
    
    # SSL security settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    location / {
        proxy_pass http://127.0.0.1:${PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port 443;
        
        # Proxy timeouts
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }
}
EOF

ln -sf "${NGINX_SITES_AVAILABLE}/${CONF_NAME}" "${NGINX_SITES_ENABLED}/${CONF_NAME}"

if command -v nginx >/dev/null 2>&1; then
  log_info "Validating nginx configuration"
  sudo nginx -t
fi

log_info "Reloading nginx"
reload_nginx

echo "${SERVER_NAME}"
