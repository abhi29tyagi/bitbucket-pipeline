#!/bin/bash
set -euo pipefail

# Required environment variables
: "${INTERNAL_DNS_SERVER:?Missing INTERNAL_DNS_SERVER}"
: "${INTERNAL_DNS_ZONE:?Missing INTERNAL_DNS_ZONE}"
: "${INTERNAL_DNS_TSIG_KEY_NAME:?Missing INTERNAL_DNS_TSIG_KEY_NAME}"
: "${INTERNAL_DNS_TSIG_KEY:?Missing INTERNAL_DNS_TSIG_KEY}"

# Determine if this is a preview deployment or dev deployment
if [ -n "${BITBUCKET_PR_ID:-}" ]; then
    # Preview deployment - use PR ID and default zone
    PREVIEW_SUBDOMAIN="pr-${BITBUCKET_PR_ID}"
    FULL_DOMAIN="${PREVIEW_SUBDOMAIN}.${INTERNAL_DNS_ZONE}"
    echo "Deleting preview A record: ${FULL_DOMAIN}"
else
    # Dev deployment - use environment-specific variables
    : "${DEV_SUBDOMAIN:?Missing DEV_SUBDOMAIN for dev deployment}"
    : "${DEV_ZONE:?Missing DEV_ZONE for dev deployment}"
    
    FULL_DOMAIN="${DEV_SUBDOMAIN}.${DEV_ZONE}"
    echo "Deleting dev A record: ${FULL_DOMAIN}"
fi

# Ensure nsupdate is installed (same logic as create)
if ! command -v nsupdate >/dev/null 2>&1; then
    echo "nsupdate not found, attempting to install..."
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y dnsutils
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y bind-utils
    elif command -v apk >/dev/null 2>&1; then
        sudo apk add bind-tools
    else
        echo "No supported package manager found. Please install nsupdate manually."
        exit 1
    fi
fi

# Create a temporary key file for nsupdate (same format/algorithm as create)
KEYFILE=$(mktemp)
cat > "$KEYFILE" <<EOF
key "${INTERNAL_DNS_TSIG_KEY_NAME}" {
    algorithm hmac-sha256;
    secret "${INTERNAL_DNS_TSIG_KEY}";
};
EOF

# Optionally check existence first (non-fatal if missing)
echo "Checking if DNS record exists before delete: ${FULL_DOMAIN}"
nslookup ${FULL_DOMAIN} ${INTERNAL_DNS_SERVER} >/dev/null 2>&1 || {
    echo "Record not found; proceeding with delete to ensure idempotency"
}

# Create nsupdate commands
NSUPDATE_CMDS=$(cat <<EOF
server ${INTERNAL_DNS_SERVER}
zone ${INTERNAL_DNS_ZONE}
update delete ${FULL_DOMAIN}. A
send
EOF
)

# Execute nsupdate using the key file
echo "${NSUPDATE_CMDS}" | nsupdate -k "$KEYFILE"
NSUPDATE_EXIT=$?

# Clean up the key file
rm -f "$KEYFILE"

if [ $NSUPDATE_EXIT -eq 0 ]; then
    echo "Successfully deleted A record: ${FULL_DOMAIN}"
else
    echo "Failed to delete A record (might not exist)"
    exit 0  # Don't fail pipeline on missing record
fi
