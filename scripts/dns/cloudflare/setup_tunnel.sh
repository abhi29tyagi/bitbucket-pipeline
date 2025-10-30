#!/bin/bash
set -euo pipefail

# Automate Cloudflare Tunnel setup (Named Tunnel + credentials file approach)
# Requires: CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID, TUNNEL_NAME, TUNNEL_HOSTNAME
# Optional: TUNNEL_SERVICE_URL (defaults to http://127.0.0.1:${APP_PORT}), TUNNEL_SECRET

# Validate required variables
: "${CLOUDFLARE_API_TOKEN:?Missing CLOUDFLARE_API_TOKEN}"
: "${CLOUDFLARE_ACCOUNT_ID:?Missing CLOUDFLARE_ACCOUNT_ID}"
: "${TUNNEL_HOSTNAME:?Missing TUNNEL_HOSTNAME (e.g., be-api.dev.example.com)}"

# Default TUNNEL_NAME to sanitized hostname if not provided
if [ -z "${TUNNEL_NAME:-}" ]; then
  TUNNEL_NAME=$(echo "$TUNNEL_HOSTNAME" | cut -d'.' -f1 | tr '_' '-')
  echo "TUNNEL_NAME not provided, derived from hostname: $TUNNEL_NAME"
fi

# Optional: default TUNNEL_SERVICE_URL to localhost:APP_PORT
if [ -z "${TUNNEL_SERVICE_URL:-}" ]; then
  if [ -z "${APP_PORT:-}" ]; then
    echo "ERROR: APP_PORT is not set. Please set APP_PORT in repository variables or provide TUNNEL_SERVICE_URL directly."
    exit 1
  fi
  TUNNEL_SERVICE_URL="http://127.0.0.1:${APP_PORT}"
  echo "Using APP_PORT=${APP_PORT} → TUNNEL_SERVICE_URL=${TUNNEL_SERVICE_URL}"
fi

TUNNEL_CONTAINER_NAME="${TUNNEL_CONTAINER_NAME:-cloudflared-backend}"
TUNNEL_IMAGE="${TUNNEL_IMAGE:-cloudflare/cloudflared:latest}"
CFG_DIR="/etc/cloudflared"
API_BASE="https://api.cloudflare.com/client/v4"

echo "Setting up Cloudflare Tunnel: $TUNNEL_NAME"

# Check if tunnel exists
TUNNEL_ID=$(curl -sS -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" \
  "${API_BASE}/accounts/${CLOUDFLARE_ACCOUNT_ID}/cfd_tunnel?name=${TUNNEL_NAME}&is_deleted=false" | \
  jq -r '.result[0].id // empty')

if [ -z "$TUNNEL_ID" ]; then
  echo "Creating new tunnel: $TUNNEL_NAME"
  # Generate tunnel secret (32 random bytes, base64)
  TUNNEL_SECRET="${TUNNEL_SECRET:-$(openssl rand -base64 32 | tr -d '\n')}"
  CREATE_RESP=$(curl -sS -X POST -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" \
    "${API_BASE}/accounts/${CLOUDFLARE_ACCOUNT_ID}/cfd_tunnel" \
    --data "{\"name\":\"${TUNNEL_NAME}\",\"tunnel_secret\":\"${TUNNEL_SECRET}\"}")
  TUNNEL_ID=$(echo "$CREATE_RESP" | jq -r '.result.id // empty')
  if [ -z "$TUNNEL_ID" ]; then
    echo "ERROR: Failed to create tunnel. Response: $CREATE_RESP"
    exit 1
  fi
  echo "Created tunnel ID: $TUNNEL_ID"
else
  echo "Tunnel already exists: $TUNNEL_ID"
  # For existing tunnels, we need the secret from storage or regenerate (not exposed by API)
  # Assume credentials file exists or user provides TUNNEL_SECRET
  if [ -z "${TUNNEL_SECRET:-}" ]; then
    echo "WARNING: TUNNEL_SECRET not provided for existing tunnel; assuming credentials file exists at $CFG_DIR/${TUNNEL_ID}.json"
  fi
fi

# Write credentials file
if [ -n "${TUNNEL_SECRET:-}" ]; then
  echo "Writing tunnel credentials to $CFG_DIR/${TUNNEL_ID}.json"
  if command -v sudo >/dev/null 2>&1; then
    sudo mkdir -p "$CFG_DIR"
    printf '%s\n' \
      "{" \
      "  \"AccountTag\": \"${CLOUDFLARE_ACCOUNT_ID}\"," \
      "  \"TunnelID\": \"${TUNNEL_ID}\"," \
      "  \"TunnelSecret\": \"${TUNNEL_SECRET}\"" \
      "}" \
      | sudo tee "$CFG_DIR/${TUNNEL_ID}.json" >/dev/null
    sudo chmod 600 "$CFG_DIR/${TUNNEL_ID}.json"
  else
    mkdir -p "$CFG_DIR"
    printf '%s\n' \
      "{" \
      "  \"AccountTag\": \"${CLOUDFLARE_ACCOUNT_ID}\"," \
      "  \"TunnelID\": \"${TUNNEL_ID}\"," \
      "  \"TunnelSecret\": \"${TUNNEL_SECRET}\"" \
      "}" \
      > "$CFG_DIR/${TUNNEL_ID}.json"
    chmod 600 "$CFG_DIR/${TUNNEL_ID}.json"
  fi
fi

# Write config.yml with ingress mapping
echo "Writing tunnel config to $CFG_DIR/config.yml"
if command -v sudo >/dev/null 2>&1; then
  printf '%s\n' \
    "tunnel: ${TUNNEL_ID}" \
    "credentials-file: ${CFG_DIR}/${TUNNEL_ID}.json" \
    "ingress:" \
    "  - hostname: ${TUNNEL_HOSTNAME}" \
    "    service: ${TUNNEL_SERVICE_URL}" \
    "  - service: http_status:404" \
    | sudo tee "$CFG_DIR/config.yml" >/dev/null
else
  printf '%s\n' \
    "tunnel: ${TUNNEL_ID}" \
    "credentials-file: ${CFG_DIR}/${TUNNEL_ID}.json" \
    "ingress:" \
    "  - hostname: ${TUNNEL_HOSTNAME}" \
    "    service: ${TUNNEL_SERVICE_URL}" \
    "  - service: http_status:404" \
    > "$CFG_DIR/config.yml"
fi

# Create/update DNS CNAME
echo "Ensuring Cloudflare DNS CNAME: ${TUNNEL_HOSTNAME} -> ${TUNNEL_ID}.cfargotunnel.com"
APEX_DOMAIN=$(awk -F. '{if(NF>=2) print $(NF-1)"."$NF; else print $0}' <<< "${TUNNEL_HOSTNAME}")
ZONE_ID=$(curl -sS -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" \
  "${API_BASE}/zones?name=${APEX_DOMAIN}" | jq -r '.result[0].id // empty')
if [ -z "$ZONE_ID" ]; then
  echo "ERROR: Could not resolve Cloudflare zone for ${APEX_DOMAIN}"
  exit 1
fi

REC_ID=$(curl -sS -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" \
  "${API_BASE}/zones/${ZONE_ID}/dns_records?type=CNAME&name=${TUNNEL_HOSTNAME}" | jq -r '.result[0].id // empty')
if [ -n "$REC_ID" ]; then
  echo "Updating existing CNAME ${TUNNEL_HOSTNAME}"
  curl -sS -X PUT -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" \
    "${API_BASE}/zones/${ZONE_ID}/dns_records/${REC_ID}" \
    --data "{\"type\":\"CNAME\",\"name\":\"${TUNNEL_HOSTNAME}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"proxied\":true}" >/dev/null
else
  echo "Creating new CNAME ${TUNNEL_HOSTNAME}"
  curl -sS -X POST -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" \
    "${API_BASE}/zones/${ZONE_ID}/dns_records" \
    --data "{\"type\":\"CNAME\",\"name\":\"${TUNNEL_HOSTNAME}\",\"content\":\"${TUNNEL_ID}.cfargotunnel.com\",\"proxied\":true}" >/dev/null
fi

# Route traffic through the tunnel
echo "Routing traffic to tunnel"
curl -sS -X PUT -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" \
  "${API_BASE}/accounts/${CLOUDFLARE_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations" \
  --data "{\"config\":{\"ingress\":[{\"hostname\":\"${TUNNEL_HOSTNAME}\",\"service\":\"${TUNNEL_SERVICE_URL}\"},{\"service\":\"http_status:404\"}]}}" >/dev/null || echo "WARNING: Failed to set tunnel routes via API (may not be required if using local config)"

# Ensure Docker available
export DOCKER_HOST="unix:///var/run/docker.sock"

# Remove any existing container
docker rm -f "$TUNNEL_CONTAINER_NAME" 2>/dev/null || true

# Run cloudflared with config
echo "Starting cloudflared container: $TUNNEL_CONTAINER_NAME"
docker run -d \
  --name "$TUNNEL_CONTAINER_NAME" \
  --restart unless-stopped \
  -v /etc/cloudflared:/etc/cloudflared:ro \
  "$TUNNEL_IMAGE" \
  tunnel --no-autoupdate run --config /etc/cloudflared/config.yml

echo "✅ Cloudflare Tunnel started (container: $TUNNEL_CONTAINER_NAME)"
echo "   Tunnel ID: $TUNNEL_ID"
echo "   Hostname: $TUNNEL_HOSTNAME -> $TUNNEL_SERVICE_URL"

