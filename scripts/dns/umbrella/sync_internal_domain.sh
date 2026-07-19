#!/bin/bash
set -euo pipefail

# Mirrors the BIND/internal DNS A record into Cisco Umbrella's
# "Deployments → Configuration → Domain Management" list so that
# Umbrella forwards the same domain to on-prem resolvers.
#
# Required env vars:
#   UMBRELLA_API_KEY
#   UMBRELLA_API_SECRET
#   UMBRELLA_ORG_ID
#   SUBDOMAIN
#   ZONE
# Optional:
#   UMBRELLA_DESCRIPTION                 (defaults to "Managed by shared-pipelines")
#   UMBRELLA_API_BASE                    (defaults to https://api.umbrella.com)
#   UMBRELLA_STRICT_MODE                 (default: false → warn on API errors; set true to fail)
#   UMBRELLA_INCLUDE_ALL_VAS             (default: true)
#   UMBRELLA_INCLUDE_ALL_MOBILE_DEVICES  (default: true)
#   UMBRELLA_SITE_IDS                    (comma-separated numeric IDs; optional)
#
# The script is intentionally idempotent: it looks for an existing entry
# and updates in place when found, creating a new one otherwise.

: "${SUBDOMAIN:?Missing SUBDOMAIN for Umbrella sync}"
: "${ZONE:?Missing ZONE for Umbrella sync}"

if [ -z "${UMBRELLA_API_KEY:-}" ] || [ -z "${UMBRELLA_API_SECRET:-}" ]; then
  echo "Umbrella credentials not provided; skipping Umbrella sync"
  exit 0
fi

: "${UMBRELLA_ORG_ID:?Missing UMBRELLA_ORG_ID for Umbrella sync}"

FULL_DOMAIN="${SUBDOMAIN}.${ZONE}"
UMBRELLA_API_BASE="${UMBRELLA_API_BASE:-https://api.umbrella.com}"
UMBRELLA_DESCRIPTION="${UMBRELLA_DESCRIPTION:-Managed by shared-pipelines}"

normalize_bool() {
  local value
  value=$(printf '%s' "${1:-true}" | tr '[:upper:]' '[:lower:]')
  case "$value" in
    true|false) echo "$value" ;;
    *) echo "true" ;;
  esac
}

INCLUDE_ALL_VAS=$(normalize_bool "${UMBRELLA_INCLUDE_ALL_VAS:-true}")
INCLUDE_ALL_MOBILE=$(normalize_bool "${UMBRELLA_INCLUDE_ALL_MOBILE_DEVICES:-true}")

SITE_IDS_JSON="[]"
if [ -n "${UMBRELLA_SITE_IDS:-}" ]; then
  SITE_IDS_JSON=$(UMBRELLA_SITE_IDS_RAW="$UMBRELLA_SITE_IDS" python3 - <<'PY'
import os, json
raw = os.environ.get("UMBRELLA_SITE_IDS_RAW", "")
values = []
for chunk in raw.split(","):
    chunk = chunk.strip()
    if not chunk:
        continue
    try:
        values.append(int(chunk))
    except ValueError:
        pass
print(json.dumps(values))
PY
)
fi

# Get OAuth2 token using Basic auth
AUTH_HEADER=$(printf "%s:%s" "$UMBRELLA_API_KEY" "$UMBRELLA_API_SECRET" | base64)
TOKEN_RESPONSE=$(curl -sS -X GET \
  -H "Authorization: Basic ${AUTH_HEADER}" \
  "${UMBRELLA_API_BASE}/auth/v2/token")

# Extract access token from response
ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
  echo "ERROR: Failed to obtain Umbrella access token"
  echo "Token response: $TOKEN_RESPONSE"
  if [ "${UMBRELLA_STRICT_MODE:-false}" = "true" ]; then
    exit 1
  fi
  echo "Continuing despite token failure (UMBRELLA_STRICT_MODE=false)"
  exit 0
fi

API_URL_BASE="${UMBRELLA_API_BASE}/deployments/v2/internaldomains"

function umbrella_api() {
  local method="$1"; shift
  curl -sS -X "$method" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    "$@"
}

echo "Syncing Umbrella internal domain: ${FULL_DOMAIN}"

LIST_RESPONSE=$(umbrella_api GET "${API_URL_BASE}")

# API returns a direct array, not wrapped in .data
EXISTING_ID=$(echo "$LIST_RESPONSE" | jq -r --arg domain "$FULL_DOMAIN" '.[]? | select(.domain == $domain) | .id // empty' | head -n1 || true)

PAYLOAD=$(jq -n \
  --arg domain "$FULL_DOMAIN" \
  --arg description "$UMBRELLA_DESCRIPTION" \
  --argjson includeAllVAs "$INCLUDE_ALL_VAS" \
  --argjson includeAllMobileDevices "$INCLUDE_ALL_MOBILE" \
  --argjson siteIds "$SITE_IDS_JSON" \
  '{
     domain:$domain,
     description:$description,
     includeAllVAs:$includeAllVAs,
     includeAllMobileDevices:$includeAllMobileDevices,
     siteIds:$siteIds
   }')

if [ -n "$EXISTING_ID" ]; then
  echo "Umbrella entry exists (id=${EXISTING_ID}); updating..."
  RESPONSE=$(umbrella_api PUT "${API_URL_BASE}/${EXISTING_ID}" -d "$PAYLOAD")
else
  echo "Creating Umbrella entry for ${FULL_DOMAIN}"
  RESPONSE=$(umbrella_api POST "${API_URL_BASE}" -d "$PAYLOAD")
fi

if echo "$RESPONSE" | jq -e '.id or .domain' >/dev/null 2>&1; then
  echo "Umbrella sync successful for ${FULL_DOMAIN}"
else
  echo "ERROR: Umbrella API call failed"
  echo "$RESPONSE" | jq . >/dev/null 2>&1 || echo "$RESPONSE"
  if [ "${UMBRELLA_STRICT_MODE:-false}" = "true" ]; then
    exit 1
  fi
  echo "Continuing despite Umbrella sync failure (UMBRELLA_STRICT_MODE=false)"
fi

