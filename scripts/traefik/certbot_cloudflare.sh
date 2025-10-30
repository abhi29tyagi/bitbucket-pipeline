#!/bin/bash
set -euo pipefail

# Obtain/renew a wildcard certificate for *.internal.DOMAIN_NAME (or custom subdomain)
# using Certbot with the Cloudflare DNS plugin (via dockerized certbot).

# Required:
# - CLOUDFLARE_API_TOKEN: Cloudflare API token with DNS:Edit for the zone
# - DOMAIN_NAME: Base domain (e.g., example.com)
# Optional:
# - INTERNAL_SUBDOMAIN: Subdomain to use (default: internal) → *.internal.DOMAIN_NAME
# - CERTBOT_EMAIL: Email for Let's Encrypt registration (default: admin@DOMAIN_NAME)
# - CERTBOT_STAGING: If set to "1", uses Let's Encrypt staging environment

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker is required on this host to run certbot container"
  exit 1
fi

# Ensure Docker CLI targets local daemon via Unix socket
export DOCKER_HOST="unix:///var/run/docker.sock"

if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
  echo "ERROR: CLOUDFLARE_API_TOKEN is required"
  exit 1
fi

if [ -z "${DOMAIN_NAME:-}" ]; then
  echo "ERROR: DOMAIN_NAME is required (e.g., example.com)"
  exit 1
fi

# Use INTERNAL_DNS_ZONE directly from pipeline (e.g., internal.homnifi.com) for preview 
# otherwise use FQDN from pipeline (e.g., xyz.com)
FQDN="${FQDN:-${INTERNAL_DNS_ZONE}}"
EMAIL="${CERTBOT_EMAIL:-admin@${DOMAIN_NAME}}"

echo "Requesting wildcard certificate for *.${FQDN} and ${FQDN}"

# Prepare directories with proper permissions
LETSENCRYPT_DIR="/etc/letsencrypt"
CLOUDFLARE_DIR="/etc/letsencrypt/cloudflare"

echo "🔧 Creating Let's Encrypt directories..."
if command -v sudo >/dev/null 2>&1; then
  sudo mkdir -p "$LETSENCRYPT_DIR" "$CLOUDFLARE_DIR"
  sudo chmod 755 "$LETSENCRYPT_DIR"
  sudo chmod 700 "$CLOUDFLARE_DIR"
else
  mkdir -p "$LETSENCRYPT_DIR" "$CLOUDFLARE_DIR"
  chmod 755 "$LETSENCRYPT_DIR"
  chmod 700 "$CLOUDFLARE_DIR"
fi

# Write Cloudflare credentials file (permissions 600)
CREDS_FILE="$CLOUDFLARE_DIR/credentials.ini"
if command -v sudo >/dev/null 2>&1; then
  sudo bash -c "cat > '$CREDS_FILE' <<EOF
dns_cloudflare_api_token = $CLOUDFLARE_API_TOKEN
EOF"
  sudo chmod 600 "$CREDS_FILE"
else
  bash -c "cat > '$CREDS_FILE' <<EOF
dns_cloudflare_api_token = $CLOUDFLARE_API_TOKEN
EOF"
  chmod 600 "$CREDS_FILE"
fi

# Build certbot command
CERTBOT_IMAGE="certbot/dns-cloudflare:latest"
# Pre-pull image for faster and reliable runs
docker pull "$CERTBOT_IMAGE" >/dev/null 2>&1 || true
STAGING_ARGS=""
# If CERTBOT_FORCE_PROD=1 is set, force production certificates and ignore CERTBOT_STAGING
if [ "${CERTBOT_FORCE_PROD:-0}" = "1" ]; then
  echo "Forcing Let's Encrypt PRODUCTION certificates (CERTBOT_FORCE_PROD=1)"
  export CERTBOT_STAGING=0
else
  if [ "${CERTBOT_STAGING:-0}" = "1" ]; then
    STAGING_ARGS="--staging"
    echo "Using Let's Encrypt STAGING environment"
  else
    echo "Using Let's Encrypt PRODUCTION environment"
  fi
fi

# Use a stable cert-name matching the FQDN for simpler pathing
CERT_NAME="$FQDN"

# If forcing production, remove any existing lineage for this FQDN to avoid serving staging certs
if [ "${CERTBOT_FORCE_PROD:-0}" = "1" ]; then
  echo "Cleaning existing certificate lineage for $CERT_NAME (if present)"
  if command -v sudo >/dev/null 2>&1; then
    sudo rm -rf \
      "/etc/letsencrypt/live/$CERT_NAME" \
      "/etc/letsencrypt/archive/$CERT_NAME" \
      "/etc/letsencrypt/renewal/$CERT_NAME.conf" 2>/dev/null || true
  else
    rm -rf \
      "/etc/letsencrypt/live/$CERT_NAME" \
      "/etc/letsencrypt/archive/$CERT_NAME" \
      "/etc/letsencrypt/renewal/$CERT_NAME.conf" 2>/dev/null || true
  fi
fi

echo "🐳 Running certbot with Docker volume mounts..."

docker run --rm \
  -v "$LETSENCRYPT_DIR:/etc/letsencrypt" \
  -v "$CLOUDFLARE_DIR:/cloudflare" \
  $CERTBOT_IMAGE certonly \
  --non-interactive --agree-tos $STAGING_ARGS \
  --email "$EMAIL" \
  --dns-cloudflare --dns-cloudflare-credentials /cloudflare/credentials.ini \
  -d "*.${FQDN}" -d "${FQDN}" \
  --cert-name "$CERT_NAME" || {
    echo "ERROR: certbot failed"
    exit 1
  }

echo "🔍 Verifying certificate files on host filesystem..."

FULLCHAIN="$LETSENCRYPT_DIR/live/$CERT_NAME/fullchain.pem"
PRIVKEY="$LETSENCRYPT_DIR/live/$CERT_NAME/privkey.pem"

echo "📜 Certificate files:"
echo "   - $FULLCHAIN"
echo "   - $PRIVKEY"

# Verify files exist on host (use sudo if needed for permission-restricted directories)
if command -v sudo >/dev/null 2>&1; then
  if ! sudo test -f "$FULLCHAIN" || ! sudo test -f "$PRIVKEY"; then
    echo "❌ Certificate files not found on host filesystem"
    echo "   Expected: $FULLCHAIN and $PRIVKEY"
    exit 1
  fi
else
  if [ ! -f "$FULLCHAIN" ] || [ ! -f "$PRIVKEY" ]; then
    echo "❌ Certificate files not found on host filesystem"
    echo "   Expected: $FULLCHAIN and $PRIVKEY"
    exit 1
  fi
fi

echo "✅ Certificate files verified on host filesystem"

# Create compatibility symlinks for Traefik
echo "🔗 Creating Traefik compatibility symlinks..."
SSL_DIR="${CERTS_DIR:-/etc/ssl/traefik-certs}"

if command -v sudo >/dev/null 2>&1; then
  sudo mkdir -p "$SSL_DIR"
  sudo ln -sf "$FULLCHAIN" "$SSL_DIR/wildcard.crt"
  sudo ln -sf "$PRIVKEY" "$SSL_DIR/wildcard.key"
else
  mkdir -p "$SSL_DIR"
  ln -sf "$FULLCHAIN" "$SSL_DIR/wildcard.crt"
  ln -sf "$PRIVKEY" "$SSL_DIR/wildcard.key"
fi

# Verify symlinks were created successfully
if [ -L "$SSL_DIR/wildcard.crt" ] && [ -L "$SSL_DIR/wildcard.key" ]; then
  echo "✅ Symlinks created and verified: $SSL_DIR/wildcard.{crt,key}"
else
  echo "❌ Symlink creation failed"
  exit 1
fi

echo "✅ Certbot + Cloudflare DNS certificate setup completed for *.${FQDN}"


