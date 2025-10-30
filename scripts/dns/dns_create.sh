#!/bin/bash
set -euo pipefail

# shellcheck source=../utils/lib.sh
. "$(dirname "$0")/../utils/lib.sh"

require_vars ENVIRONMENT

log_info "DNS create requested for ENVIRONMENT=${ENVIRONMENT}"

if [ "$ENVIRONMENT" = "production" ] || [ "$ENVIRONMENT" = "prod" ]; then
  # Prod: admin panel uses internal DNS, regular frontend uses Cloudflare DNS
  if [ "${IS_ADMIN_PANEL}" = "true" ]; then
    log_info "Admin panel in prod: dispatching to Internal DNS create"
    "$(dirname "$0")/internal/internal_dns_create.sh"
  else
    log_info "Dispatching to Cloudflare DNS create"
    "$(dirname "$0")/cloudflare/cf_create_dns.sh"
  fi
else
  log_info "Dispatching to Internal DNS create"
  "$(dirname "$0")/internal/internal_dns_create.sh"
fi
