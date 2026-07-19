#!/bin/bash
set -euo pipefail

# Required env vars: CLOUDFLARE_API_TOKEN, CLOUDFLARE_DOMAIN, SUBDOMAIN, TARGET_IP
: "${CLOUDFLARE_API_TOKEN:?Missing CLOUDFLARE_API_TOKEN}"
: "${CLOUDFLARE_DOMAIN:?Missing CLOUDFLARE_DOMAIN}"
: "${SUBDOMAIN:?Missing SUBDOMAIN}"
: "${TARGET_IP:?Missing TARGET_IP}"

# Optional: control Cloudflare proxying (default: true)
# Set CLOUDFLARE_PROXIED=false to disable orange-cloud proxy
CLOUDFLARE_PROXIED="${CLOUDFLARE_PROXIED:-true}"
case "${CLOUDFLARE_PROXIED,,}" in
  true|1|yes) PROXIED_JSON=true ;;
  *)          PROXIED_JSON=false ;;
esac

# Auto-lookup zone ID if not provided
if [ -z "${CLOUDFLARE_ZONE_ID:-}" ]; then
  echo "CLOUDFLARE_ZONE_ID not provided, looking up zone for domain: ${CLOUDFLARE_DOMAIN}"
  CLOUDFLARE_ZONE_ID=$(curl -sS -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    "https://api.cloudflare.com/client/v4/zones?name=${CLOUDFLARE_DOMAIN}" | \
    jq -r '.result[0].id // empty')
  
  if [ -z "$CLOUDFLARE_ZONE_ID" ]; then
    echo "ERROR: Could not find Cloudflare zone for domain: ${CLOUDFLARE_DOMAIN}" >&2
    exit 1
  fi
  echo "Found zone ID: ${CLOUDFLARE_ZONE_ID}"
fi
NAME="${SUBDOMAIN}.${CLOUDFLARE_DOMAIN}"

BODY=$(jq -n \
  --arg type A \
  --arg name "$NAME" \
  --arg value "$TARGET_IP" \
  --argjson proxied "$PROXIED_JSON" \
  '{type:$type,name:$name,content:$value,ttl:120,proxied:$proxied}')

RESPONSE=$(curl -sS -X POST \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data "$BODY" \
  "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records")

if echo "$RESPONSE" | jq -e '.success == true' >/dev/null; then
  echo "$NAME"
  exit 0
fi

# If record already exists (code 81057), treat as success
if echo "$RESPONSE" | jq -e '.errors[]? | select(.code == 81057)' >/dev/null; then
  echo "INFO: DNS record ${NAME} already exists; treating as success"
  exit 0
fi

echo "ERROR: Cloudflare DNS create failed for ${NAME}"
echo "$RESPONSE" | jq '.'
exit 1