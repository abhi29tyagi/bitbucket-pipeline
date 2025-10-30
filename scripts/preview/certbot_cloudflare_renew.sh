#!/bin/bash
set -euo pipefail

# Renew certificates obtained via certbot_cloudflare.sh.
# Can be scheduled via cron/systemd. Optionally installs its own cron entry.

if [[ "${1:-}" == "--install-cron" ]]; then
  CRON_FILE="/etc/cron.d/certbot-renew"
  # Resolve current script path
  SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
  # Install a stable copy so cron doesn't point to ephemeral runner paths
  INSTALL_DIR="/usr/local/lib/shared-pipelines/scripts/preview"
  STABLE_PATH="$INSTALL_DIR/certbot_cloudflare_renew.sh"
  if command -v sudo >/dev/null 2>&1; then
    sudo mkdir -p "$INSTALL_DIR"
    sudo cp "$SCRIPT_PATH" "$STABLE_PATH"
    sudo chmod +x "$STABLE_PATH"
    sudo ln -sf "$STABLE_PATH" /usr/local/bin/certbot-cloudflare-renew-preview
  else
    mkdir -p "$INSTALL_DIR"
    cp "$SCRIPT_PATH" "$STABLE_PATH"
    chmod +x "$STABLE_PATH"
    ln -sf "$STABLE_PATH" /usr/local/bin/certbot-cloudflare-renew-preview 2>/dev/null || true
  fi
  CRON_LINE="0 3,15 * * * root /usr/bin/bash $STABLE_PATH >> /var/log/certbot-renew.log 2>&1"
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
  echo "Cron installed/updated at $CRON_FILE (runs $STABLE_PATH)"
  exit 0
fi

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
  $CERTBOT_IMAGE renew --non-interactive || {
    echo "ERROR: certbot renew failed"
    exit 1
  }

echo "✅ Certbot renew completed"


