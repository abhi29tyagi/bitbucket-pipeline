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
if [ -d "../.git" ] && [ ! -f "./package.json" ] && [ -f "../package.json" ]; then
  echo "Changing to workspace root..."
  cd ..
  echo "New directory: $(pwd)"
fi

# PR filtering and skip logic are handled by the main pipeline step

export APP_PATH="${APP_PATH:-.}"
[ -f "${APP_PATH}/package.json" ] || { echo "Missing ${APP_PATH}/package.json in consumer repo"; exit 1; }

if [ -d "shared-pipelines" ]; then
  echo "shared-pipelines directory already exists"
else
  echo "shared-pipelines directory does not exist, cloning..."
  git clone git@bitbucket.org:protocol33/shared-pipelines.git
fi

# Prepare Docker CLI environment to target the local daemon via a Unix socket.
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
  -e NO_COLOR=1 -e FORCE_COLOR=0 -e npm_config_color=false \
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
  
  # Run tests (prefer coverage script names; fallback to test; skip only if none)
  # Allow override via TEST_SCRIPT_NAME env var, otherwise auto-detect
  if [ -n "${TEST_SCRIPT_NAME:-}" ]; then
    PICK_TEST_SCRIPT="${TEST_SCRIPT_NAME}"
    echo "🔍 Using custom test script: '\''${PICK_TEST_SCRIPT}'\'' (from TEST_SCRIPT_NAME env var)"
  else
    echo "🔍 Auto-detecting test script from package.json..."
    # Create a simple script to detect test script (avoid heredoc quoting pitfalls)
    printf '\''%s\n'\'' \
      "const p = require('\''./package.json'\'');" \
      "const envOrder = (process.env.TEST_SCRIPT_ORDER||'\'\'\'').split('\'','\'').map(s=>s.trim()).filter(Boolean);" \
      "const defaultOrder = ['\''test:ci'\'','\''test:coverage'\'','\''test:cov'\'','\''coverage'\'','\''test'\''];" \
      "const order = envOrder.length ? envOrder : defaultOrder;" \
      "// Print only the selected script to stdout; other info to stderr" \
      "if (!p.scripts) { process.exit(1); }" \
      "for (const k of order) { if (p.scripts[k]) { console.log(k); process.exit(0); } }" \
      "process.exit(1);" \
    > /tmp/check-test.js
    PICK_TEST_SCRIPT=$(node /tmp/check-test.js 2>/dev/null || true)
  fi

  if [ -f yarn.lock ]; then
    echo "📦 Using yarn as package manager"
    if [ -n "$PICK_TEST_SCRIPT" ]; then
      echo "✅ Running test script '\''${PICK_TEST_SCRIPT}'\'' with yarn..."
      yarn $PICK_TEST_SCRIPT 2>&1 | tee /tmp/test-output.txt; TEST_EXIT_CODE=${PIPESTATUS[0]}
    else
      echo "⚠️  No test script found, skipping tests" | tee /tmp/test-output.txt; TEST_EXIT_CODE=0
    fi
  elif [ -f pnpm-lock.yaml ]; then
    echo "📦 Using pnpm as package manager"
    if [ -n "$PICK_TEST_SCRIPT" ]; then
      echo "✅ Running test script '\''${PICK_TEST_SCRIPT}'\'' with pnpm..."
      pnpm run $PICK_TEST_SCRIPT 2>&1 | tee /tmp/test-output.txt; TEST_EXIT_CODE=${PIPESTATUS[0]}
    else
      echo "⚠️  No test script found, skipping tests" | tee /tmp/test-output.txt; TEST_EXIT_CODE=0
    fi
  else
    echo "📦 Using npm as package manager"
    if [ -n "$PICK_TEST_SCRIPT" ]; then
      echo "✅ Running test script '\''${PICK_TEST_SCRIPT}'\'' with npm..."
      npm run $PICK_TEST_SCRIPT 2>&1 | tee /tmp/test-output.txt; TEST_EXIT_CODE=${PIPESTATUS[0]}
    else
      echo "🔍 Auto-fallback: trying npm scripts (test:ci, then test) if present..."
      # Try test:ci first
      npm run test:ci --if-present 2>&1 | tee /tmp/test-output.txt
    TEST_EXIT_CODE=${PIPESTATUS[0]}
      if grep -qE "^> test:ci" /tmp/test-output.txt || grep -qi "jest" /tmp/test-output.txt; then
        echo "✅ Executed npm run test:ci"
  else
        # Try plain test
        npm run test --if-present 2>&1 | tee /tmp/test-output.txt
    TEST_EXIT_CODE=${PIPESTATUS[0]}
        if grep -qE "^> test" /tmp/test-output.txt || grep -qi "jest" /tmp/test-output.txt; then
          echo "✅ Executed npm run test"
        else
          echo "⚠️  No test script present; skipping tests" | tee /tmp/test-output.txt
          TEST_EXIT_CODE=0
        fi
      fi
    fi
  fi
  
  # Sanitize ANSI/color from test output for XML safety
  if [ -s /tmp/test-output.txt ]; then
    sed -r "s/\x1B\[[0-9;]*[A-Za-z]//g" /tmp/test-output.txt | tr -cd "\11\12\15\40-\176" > /tmp/test-output-clean.txt || cp /tmp/test-output.txt /tmp/test-output-clean.txt
  else
    : > /tmp/test-output-clean.txt
  fi

  # Human-readable summary (separate file, not XML)
  echo "=== Test Results ===" > test-summary.txt
  if [ -s /tmp/test-output.txt ]; then
    echo "See detailed output below:" >> test-summary.txt
    tail -n 200 /tmp/test-output.txt >> test-summary.txt || true
  fi

  # Machine-readable JUnit XML (strictly XML)
  echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" > test-results.xml
  echo "<testsuites>" >> test-results.xml
  echo "  <testsuite name=\"test-run\" timestamp=\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\">" >> test-results.xml
  echo "    <testcase name=\"test-execution\" classname=\"test-run\">" >> test-results.xml
  if [ $TEST_EXIT_CODE -eq 0 ]; then
    echo "      <system-out>Tests passed successfully</system-out>" >> test-results.xml
  else
    echo "      <failure message=\"Tests failed with exit code $TEST_EXIT_CODE\">" >> test-results.xml
    echo "        <![CDATA[$(cat /tmp/test-output-clean.txt)]]>" >> test-results.xml
    echo "      </failure>" >> test-results.xml
  fi
  echo "    </testcase>" >> test-results.xml
  echo "  </testsuite>" >> test-results.xml
  echo "</testsuites>" >> test-results.xml
  
  # Ensure a non-empty, well-formed XML exists even if prior commands produced nothing
  if [ ! -s test-results.xml ]; then
    echo "⚠️  test-results.xml was empty; writing minimal report"
    printf '\''%s\n'\'' \
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" \
      "<testsuites>" \
      "  <testsuite name=\"test-run\" tests=\"0\" failures=\"0\" errors=\"0\" skipped=\"0\"/>" \
      "</testsuites>" \
    > test-results.xml
  fi
  
  # Optionally allow test failures without failing the pipeline
  if [ "${TEST_ALLOW_FAILURE:-true}" = "true" ]; then
    echo "TEST_ALLOW_FAILURE=true: continuing despite test exit code $TEST_EXIT_CODE" | tee -a test-summary.txt
    TEST_EXIT_CODE=0
  fi

  # Exit with test result (possibly overridden)
  exit $TEST_EXIT_CODE
'

# If tests are allowed to fail, override docker run exit code
if [ "${TEST_ALLOW_FAILURE:-true}" = "true" ]; then
  echo "TEST_ALLOW_FAILURE=true: not failing step on test failures"
  true
fi

# Optional: print minimal coverage summary if available
cat coverage/lcov.info >/dev/null 2>&1 || true

