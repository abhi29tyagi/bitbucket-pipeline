#!/bin/bash
set -euo pipefail

# Required env vars: CLOUDFLARE_API_TOKEN, CLOUDFLARE_ZONE_ID, CLOUDFLARE_DOMAIN, PREVIEW_SUBDOMAIN
: "${CLOUDFLARE_API_TOKEN:?Missing CLOUDFLARE_API_TOKEN}"
: "${CLOUDFLARE_ZONE_ID:?Missing CLOUDFLARE_ZONE_ID}"
: "${CLOUDFLARE_DOMAIN:?Missing CLOUDFLARE_DOMAIN}"
: "${PREVIEW_SUBDOMAIN:?Missing PREVIEW_SUBDOMAIN}"
: "${PREVIEW_TARGET_IP:?Missing PREVIEW_TARGET_IP}"

NAME="${PREVIEW_SUBDOMAIN}.${CLOUDFLARE_DOMAIN}"

BODY=$(jq -n --arg type A --arg name "$NAME" --arg value "$PREVIEW_TARGET_IP" '{type:$type,name:$name,content:$value,ttl:120,proxied:false}')

curl -sS -X POST \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data "$BODY" \
  "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" | jq -e '.success == true' >/dev/null

echo "$NAME"
