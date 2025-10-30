#!/bin/bash
set -euo pipefail

# Required environment variables
: "${INTERNAL_DNS_SERVER:?Missing INTERNAL_DNS_SERVER}"
: "${INTERNAL_DNS_ZONE:?Missing INTERNAL_DNS_ZONE}"
: "${INTERNAL_DNS_TSIG_KEY_NAME:?Missing INTERNAL_DNS_TSIG_KEY_NAME}"
: "${INTERNAL_DNS_TSIG_KEY:?Missing INTERNAL_DNS_TSIG_KEY}"
: "${SUBDOMAIN:?Missing SUBDOMAIN}"
: "${ZONE:?Missing ZONE}"
: "${TARGET_IP:?Missing TARGET_IP}"

# Create A record using standardized variables
FULL_DOMAIN="${SUBDOMAIN}.${ZONE}"
echo "Creating A record: ${FULL_DOMAIN} -> ${TARGET_IP}"

# Ensure nsupdate is installed
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

# Create a temporary key file for nsupdate
KEYFILE=$(mktemp)
cat > "$KEYFILE" <<EOF
key "${INTERNAL_DNS_TSIG_KEY_NAME}" {
    algorithm hmac-sha256;
    secret "${INTERNAL_DNS_TSIG_KEY}";
};
EOF

# Create nsupdate commands
NSUPDATE_CMDS=$(cat <<EOF
server ${INTERNAL_DNS_SERVER}
zone ${INTERNAL_DNS_ZONE}
update add ${FULL_DOMAIN} 300 A ${TARGET_IP}
send
EOF
)

# Execute nsupdate using the key file
echo "${NSUPDATE_CMDS}" | nsupdate -k "$KEYFILE"
NSUPDATE_EXIT=$?

# Clean up the key file
rm -f "$KEYFILE"

if [ $NSUPDATE_EXIT -eq 0 ]; then
    echo "Successfully created A record: ${FULL_DOMAIN} -> ${TARGET_IP}"
    echo "https://${FULL_DOMAIN}"
else
    echo "Failed to create A record"
    exit 1
fi