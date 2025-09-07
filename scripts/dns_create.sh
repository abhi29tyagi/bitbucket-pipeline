#!/bin/bash
set -euo pipefail

# shellcheck source=ci/lib.sh
. "$(dirname "$0")/ci/lib.sh"

require_vars ENVIRONMENT

log_info "DNS create requested for ENVIRONMENT=${ENVIRONMENT}"

if [ "$ENVIRONMENT" = "production" ] || [ "$ENVIRONMENT" = "prod" ] || [ "$ENVIRONMENT" = "uat" ]; then
  log_info "Dispatching to Cloudflare DNS create"
  ./shared-pipelines/scripts/cloudflare/cf_create_dns.sh
else
  log_info "Dispatching to Internal DNS create"
  ./shared-pipelines/scripts/internal-dns/internal_dns_create.sh
fi
