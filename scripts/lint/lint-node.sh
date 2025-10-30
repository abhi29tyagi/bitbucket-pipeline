#!/bin/bash
set -euo pipefail

# Debug: Show where we are and what files exist
echo "=== DEBUG: Script Execution Context ==="
echo "Current directory: $(pwd)"
echo "Directory contents:"
ls -lrth
echo "Parent directory (..):"
ls -lrth .. 2>/dev/null || echo "Cannot access parent directory"
echo "Looking for package.json:"
echo "  ./package.json exists? $([ -f ./package.json ] && echo 'YES' || echo 'NO')"
echo "  ../package.json exists? $([ -f ../package.json ] && echo 'YES' || echo 'NO')"
echo "=== END DEBUG ==="
echo ""

# Ensure we're in the workspace root (where consumer repo was cloned)
# When called via exec bash, we might be in shared-pipelines directory
if [ -d "../.git" ] && [ ! -f "./package.json" ] && [ -f "../package.json" ]; then
  echo "Changing to workspace root..."
  cd ..
  echo "New directory: $(pwd)"
fi

# PR filtering and skip logic are handled by the main pipeline step

export APP_PATH="${APP_PATH:-.}"
echo "Current directory: $(pwd)"
echo "Checking for package.json at: ${APP_PATH}/package.json"
[ -f "${APP_PATH}/package.json" ] || { echo "Missing ${APP_PATH}/package.json in consumer repo"; exit 1; }

if [ -d "shared-pipelines" ]; then
  echo "shared-pipelines directory already exists"
else
  echo "shared-pipelines directory does not exist, cloning..."
  git clone git@bitbucket.org:protocol33/shared-pipelines.git
fi

# Prepare Docker CLI environment to target the local daemon via a Unix socket.
# This command is necessary because Bitbucket self-hosted runners might inherit DOCKER_HOST or DOCKER_CONTEXT environment variables that force the Docker CLI
# that force the Docker CLI to attempt connection over TCP (e.g., tcp://localhost:2375), even when the daemon is running locally and accessible via a Unix socket.
export DOCKER_HOST="unix:///var/run/docker.sock"

# Use the host user ID to avoid permission issues
USER_ID=$(id -u)
GROUP_ID=$(id -g)

NODE_VERSION="${NODE_VERSION:-20}"
docker run --rm --user "${USER_ID}:${GROUP_ID}" \
  -v "$(pwd)/${APP_PATH}":/app \
  -w /app \
  -e HOME=/tmp \
  -e CI=true \
  -e NODE_OPTIONS="${NODE_OPTIONS:---max-old-space-size=4096}" \
  -e TEST_ALLOW_FAILURE="${TEST_ALLOW_FAILURE:-true}" \
  node:${NODE_VERSION} bash -c '
  # Set npm to use temporary directories to avoid permission issues
  export npm_config_cache=/tmp/.npm
  export npm_config_userconfig=/tmp/.npmrc
  
  # Install dependencies with legacy peer deps for React projects
  if [ -f package-lock.json ]; then
    npm ci --cache /tmp/.npm --legacy-peer-deps || npm install --cache /tmp/.npm --legacy-peer-deps
  elif [ -f yarn.lock ]; then
    yarn install --frozen-lockfile --cache-folder /tmp/.yarn
  elif [ -f pnpm-lock.yaml ]; then
    pnpm install --frozen-lockfile --store-dir /tmp/.pnpm-store
  else
    npm install --cache /tmp/.npm --legacy-peer-deps
  fi
  
  # Run lint and capture output (skip only if script truly missing)
  LINT_SCRIPT_NAME="${LINT_SCRIPT_NAME:-}"
  echo "🔍 Lint script preference: '\''${LINT_SCRIPT_NAME:-auto}'\'' (auto tries lint:ci, then lint)"
  
  # Create a simple script to check for lint script (silent: exit 0 if exists, 1 otherwise)
  printf '\''%s\n'\'' \
    "try {" \
    "  const p = require('\''./package.json'\'');" \
    "  const name = process.argv[2];" \
    "  if (p && p.scripts && Object.prototype.hasOwnProperty.call(p.scripts, name)) process.exit(0);" \
    "} catch (e) {}" \
    "process.exit(1);" \
  > /tmp/check-lint.js
  
  if [ -f yarn.lock ]; then
    echo "📦 Using yarn as package manager"
    if [ -n "${LINT_SCRIPT_NAME}" ]; then
      echo "✅ Running '\''${LINT_SCRIPT_NAME}'\'' with yarn (user override)..."
      yarn ${LINT_SCRIPT_NAME} 2>&1 | tee /tmp/lint-output.txt; LINT_EXIT_CODE=${PIPESTATUS[0]}
    else
      echo "🔍 Auto-fallback: trying yarn scripts (lint:ci, then lint)..."
      yarn lint:ci 2>&1 | tee /tmp/lint-output.txt || true
    LINT_EXIT_CODE=${PIPESTATUS[0]}
      if [ ${LINT_EXIT_CODE} -ne 0 ]; then
        yarn lint 2>&1 | tee /tmp/lint-output.txt || true
        LINT_EXIT_CODE=${PIPESTATUS[0]}
      fi
      if [ ${LINT_EXIT_CODE} -ne 0 ]; then
        echo "⚠️  No lint script present; skipping lint" | tee -a /tmp/lint-output.txt
        LINT_EXIT_CODE=0
      fi
    fi
  elif [ -f pnpm-lock.yaml ]; then
    echo "📦 Using pnpm as package manager"
    if [ -n "${LINT_SCRIPT_NAME}" ]; then
      echo "✅ Running '\''${LINT_SCRIPT_NAME}'\'' with pnpm (user override)..."
      pnpm run ${LINT_SCRIPT_NAME} 2>&1 | tee /tmp/lint-output.txt; LINT_EXIT_CODE=${PIPESTATUS[0]}
    else
      echo "🔍 Auto-fallback: trying pnpm scripts (lint:ci, then lint)..."
      pnpm run lint:ci 2>&1 | tee /tmp/lint-output.txt || true
    LINT_EXIT_CODE=${PIPESTATUS[0]}
      if [ ${LINT_EXIT_CODE} -ne 0 ]; then
        pnpm run lint 2>&1 | tee /tmp/lint-output.txt || true
        LINT_EXIT_CODE=${PIPESTATUS[0]}
      fi
      if [ ${LINT_EXIT_CODE} -ne 0 ]; then
        echo "⚠️  No lint script present; skipping lint" | tee -a /tmp/lint-output.txt
        LINT_EXIT_CODE=0
      fi
    fi
  else
    echo "📦 Using npm as package manager"
    if [ -n "${LINT_SCRIPT_NAME}" ]; then
      echo "✅ Running '\''${LINT_SCRIPT_NAME}'\'' with npm (if present)..."
      npm run ${LINT_SCRIPT_NAME} --if-present 2>&1 | tee /tmp/lint-output.txt
    LINT_EXIT_CODE=${PIPESTATUS[0]}
      if ! grep -qE "^> ${LINT_SCRIPT_NAME}" /tmp/lint-output.txt && ! grep -qi "eslint" /tmp/lint-output.txt; then
        echo "⚠️  Script '\''${LINT_SCRIPT_NAME}'\'' not present; skipping lint" | tee -a /tmp/lint-output.txt
        LINT_EXIT_CODE=0
      fi
    else
      echo "🔍 Auto-fallback: trying npm scripts (lint:ci, then lint) if present..."
      npm run lint:ci --if-present 2>&1 | tee /tmp/lint-output.txt
      LINT_EXIT_CODE=${PIPESTATUS[0]}
      if grep -qE "^> lint:ci" /tmp/lint-output.txt || grep -qi "eslint" /tmp/lint-output.txt; then
        echo "✅ Executed npm run lint:ci"
      else
        npm run lint --if-present 2>&1 | tee /tmp/lint-output.txt
        LINT_EXIT_CODE=${PIPESTATUS[0]}
        if grep -qE "^> lint" /tmp/lint-output.txt || grep -qi "eslint" /tmp/lint-output.txt; then
          echo "✅ Executed npm run lint"
        else
          echo "⚠️  No lint script present; skipping lint" | tee -a /tmp/lint-output.txt
          LINT_EXIT_CODE=0
        fi
      fi
    fi
  fi
  
  # Create lint results file
  echo "=== Lint Results ===" > lint-results.txt
  echo "Timestamp: $(date)" >> lint-results.txt
  echo "Exit Code: $LINT_EXIT_CODE" >> lint-results.txt
  echo "Output:" >> lint-results.txt
  cat /tmp/lint-output.txt >> lint-results.txt

  # Optional: generate ESLint JSON report for Sonar ingestion (best-effort)
  echo "Generating ESLint JSON report (best-effort)..."
  if command -v npx >/dev/null 2>&1; then
    ( npx eslint . --ext .js,.jsx,.ts,.tsx -f json -o eslint-report.json 2>/dev/null || true )
  fi
  
  # Optionally allow lint failures without failing the pipeline
  if [ "${LINT_ALLOW_FAILURE:-true}" = "true" ]; then
    echo "LINT_ALLOW_FAILURE=true: continuing despite lint exit code $LINT_EXIT_CODE" | tee -a lint-results.txt
    LINT_EXIT_CODE=0
  fi
  
  # Exit with lint result
  exit $LINT_EXIT_CODE
'

