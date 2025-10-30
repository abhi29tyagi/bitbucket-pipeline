#!/bin/bash
set -euo pipefail

# shellcheck source=../utils/lib.sh
. "$(dirname "$0")/../utils/lib.sh"

require_vars ENVIRONMENT

log_info "DNS delete requested for ENVIRONMENT=${ENVIRONMENT}"

if [ "$ENVIRONMENT" = "production" ] || [ "$ENVIRONMENT" = "prod" ] || [ "$ENVIRONMENT" = "uat" ]; then
  log_info "Dispatching to Cloudflare DNS delete"
  "$(dirname "$0")/cloudflare/cf_delete_dns.sh"
else
  log_info "Dispatching to Internal DNS delete"
  "$(dirname "$0")/internal/internal_dns_delete.sh"
fi
