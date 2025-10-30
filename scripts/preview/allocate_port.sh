#!/bin/bash
set -euo pipefail

# shellcheck source=../utils/lib.sh
. "$(dirname "$0")/../utils/lib.sh"

# Configuration (overridable)
PREVIEW_PORT_START=${PREVIEW_PORT_START:-40000}
PREVIEW_PORT_SIZE=${PREVIEW_PORT_SIZE:-25}

require_vars PREVIEW_PORT_START PREVIEW_PORT_SIZE

range_end=$((PREVIEW_PORT_START + PREVIEW_PORT_SIZE - 1))

log_info "Allocating preview port in range ${PREVIEW_PORT_START}-${range_end}"

is_port_in_use() {
  local p=$1
  # Check TCP listeners via ss
  if command -v ss >/dev/null 2>&1; then
    ss -ltn | awk '{print $4}' | grep -E ":${p}$" >/dev/null 2>&1 && return 0
  fi
  # Check docker published ports
  if command -v docker >/dev/null 2>&1; then
    docker ps --format '{{.Ports}}' | tr ',' '\n' | sed 's/^[[:space:]]*//' | grep -E "(^|:)${p}->" >/dev/null 2>&1 && return 0
  fi
  return 1
}

chosen=""
for ((p=PREVIEW_PORT_START; p<=range_end; p++)); do
  if ! is_port_in_use "$p"; then
    chosen=$p
    break
  fi
done

if [ -z "$chosen" ]; then
  log_error "No free port found in range ${PREVIEW_PORT_START}-${range_end}"
  exit 1
fi

log_info "Selected preview port: ${chosen}"
echo "$chosen" | tee preview_port.txt
