#!/bin/bash
set -euo pipefail

# Required env vars: CLOUDFLARE_API_TOKEN, CLOUDFLARE_ZONE_ID, CLOUDFLARE_DOMAIN, PREVIEW_SUBDOMAIN
: "${CLOUDFLARE_API_TOKEN:?Missing CLOUDFLARE_API_TOKEN}"
: "${CLOUDFLARE_ZONE_ID:?Missing CLOUDFLARE_ZONE_ID}"
: "${CLOUDFLARE_DOMAIN:?Missing CLOUDFLARE_DOMAIN}"
: "${PREVIEW_SUBDOMAIN:?Missing PREVIEW_SUBDOMAIN}"

NAME="${PREVIEW_SUBDOMAIN}.${CLOUDFLARE_DOMAIN}"

REC_ID=$(curl -sS -X GET \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  -H "Content-Type: application/json" \
  "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records?type=A&name=${NAME}" | jq -r '.result[0].id // empty')

if [ -n "$REC_ID" ]; then
  curl -sS -X DELETE \
    -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${REC_ID}" | jq -e '.success == true' >/dev/null
fi

echo "deleted:${NAME}"
