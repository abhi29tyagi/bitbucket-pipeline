#!/bin/bash
set -euo pipefail

# Renew certificates obtained via certbot_cloudflare.sh.
# Can be scheduled via cron/systemd. Reloads Nginx if renewal occurs.

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker is required on this host"
  exit 1
fi

# Ensure Docker CLI targets local daemon via Unix socket
export DOCKER_HOST="unix:///var/run/docker.sock"

LETSENCRYPT_DIR="/etc/letsencrypt"
CERTBOT_IMAGE="certbot/dns-cloudflare:latest"

# Pre-pull image to ensure it's available
docker pull "$CERTBOT_IMAGE" >/dev/null 2>&1 || true

# Renew (non-interactive). certbot returns 0 even if nothing renewed.
docker run --rm \
  -v "$LETSENCRYPT_DIR:/etc/letsencrypt" \
  $CERTBOT_IMAGE renew --non-interactive --deploy-hook "nginx -t && systemctl reload nginx" || {
    echo "ERROR: certbot renew failed"
    exit 1
  }

echo "✅ Certbot renew completed"


