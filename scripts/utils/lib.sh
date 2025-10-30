#!/bin/bash
set -euo pipefail

# Logging helpers (all output to stderr to not interfere with command substitution)
log_info()  { echo "[INFO ] $(date -u +%Y-%m-%dT%H:%M:%SZ) - $*" >&2; }
log_warn()  { echo "[WARN ] $(date -u +%Y-%m-%dT%H:%M:%SZ) - $*" >&2; }
log_error() { echo "[ERROR] $(date -u +%Y-%m-%dT%H:%M:%SZ) - $*" >&2; }

# Trap errors to show context
trap 'log_error "Command failed: $BASH_COMMAND (exit=$?) at ${BASH_SOURCE[0]}:${LINENO}"' ERR

# Retry helper: retry <retries> <sleep_sec> -- <command> [args...]
retry() {
  local retries=$1; shift
  local sleep_sec=$1; shift
  if [ "$1" != "--" ]; then
    log_error "retry: expected -- before command"; return 2
  fi
  shift
  local attempt=1
  while true; do
    if "$@"; then
      return 0
    fi
    if [ $attempt -ge $retries ]; then
      log_error "retry: command failed after $attempt attempts: $*"
      return 1
    fi
    log_warn "retry: attempt $attempt failed; retrying in ${sleep_sec}s: $*"
    attempt=$((attempt+1))
    sleep "$sleep_sec"
  done
}

require_vars() {
  local missing=0
  for v in "$@"; do
    if [ -z "${!v:-}" ]; then
      log_error "Missing required variable: $v"; missing=1
    fi
  done
  if [ $missing -eq 1 ]; then
    exit 1
  fi
}
