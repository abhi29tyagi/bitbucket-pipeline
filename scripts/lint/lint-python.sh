#!/bin/bash
set -euo pipefail

# Debug: Show where we are and what files exist
echo "=== DEBUG: Script Execution Context ==="
echo "Current directory: $(pwd)"
echo "Directory contents:"
ls -lrth
echo "Parent directory (..):"
ls -lrth .. 2>/dev/null || echo "Cannot access parent directory"
echo "Looking for Python project files:"
echo "  ./requirements.txt exists? $([ -f ./requirements.txt ] && echo 'YES' || echo 'NO')"
echo "  ./pyproject.toml exists? $([ -f ./pyproject.toml ] && echo 'YES' || echo 'NO')"
echo "  ../requirements.txt exists? $([ -f ../requirements.txt ] && echo 'YES' || echo 'NO')"
echo "  ../pyproject.toml exists? $([ -f ../pyproject.toml ] && echo 'YES' || echo 'NO')"
echo "=== END DEBUG ==="
echo ""

# Ensure we're in the workspace root (where consumer repo was cloned)
if [ -d "../.git" ] && [ ! -f "./requirements.txt" ] && [ ! -f "./pyproject.toml" ] && [ -f "../requirements.txt" -o -f "../pyproject.toml" ]; then
  echo "Changing to workspace root..."
  cd ..
  echo "New directory: $(pwd)"
fi

# PR filtering and skip logic are handled by the main pipeline step

export APP_PATH="${APP_PATH:-.}"
[ -d "${APP_PATH}" ] || { echo "Missing ${APP_PATH} directory in consumer repo"; exit 1; }

# Prepare Docker CLI environment to target the local daemon via a Unix socket.
export DOCKER_HOST="unix:///var/run/docker.sock"

USER_ID=$(id -u)
GROUP_ID=$(id -g)
PYTHON_VERSION="${PYTHON_VERSION:-3.11}"
PY_IMAGE="${PY_IMAGE:-python:${PYTHON_VERSION}-slim}"
PY_LINT_TOOL="${PY_LINT_TOOL:-auto}"

docker run --rm --user "${USER_ID}:${GROUP_ID}" \
  -v "$(pwd)/${APP_PATH}":/app \
  -w /app \
  -e HOME=/tmp \
  -e PIP_CACHE_DIR=/tmp/.pip \
  -e CI=true \
  ${PY_IMAGE} bash -lc '
    set -e
    python -V
    python -m pip install -U pip >/dev/null 2>&1 || true
    export PYTHONUSERBASE=/tmp/.local
    export PATH="$PATH:/tmp/.local/bin"
    # Install project deps (best-effort across common setups)
    if [ -f requirements.txt ]; then
      pip install -r requirements.txt || true
    fi
    if [ -f requirements-dev.txt ]; then
      pip install -r requirements-dev.txt || true
    fi
    # Avoid installing the project itself during lint to prevent wheel builds
    # Ensure linters present
    if [ "${PY_LINT_TOOL}" = "ruff" ]; then
      pip install ruff
    elif [ "${PY_LINT_TOOL}" = "flake8" ]; then
      pip install flake8
    else
      pip install ruff flake8 >/dev/null 2>&1 || true
    fi

    # Choose tool
    TOOL=""
    if [ "${PY_LINT_TOOL}" = "ruff" ] || command -v ruff >/dev/null 2>&1; then TOOL=ruff; fi
    if [ -z "$TOOL" ] && ( [ "${PY_LINT_TOOL}" = "flake8" ] || command -v flake8 >/dev/null 2>&1 ); then TOOL=flake8; fi
    if [ -z "$TOOL" ]; then echo "No Python linter available (ruff/flake8)."; exit 1; fi

    echo "Using linter: $TOOL"
    if [ "$TOOL" = ruff ]; then
      ruff --version
      ruff check . --output-format json | tee python-lint-report.json
      EXIT=$?
      # Also produce human summary
      ruff check . 2>&1 | tee lint-py-results.txt
      exit $EXIT
    else
      flake8 --version
      # Produce text output and a minimal JSON placeholder to avoid quoting issues
      flake8 . 2>&1 | tee lint-py-results.txt
      EXIT=${PIPESTATUS[0]}
      echo "{\"results\":[]}" > python-lint-report.json
      exit $EXIT
    fi
  '

LINT_EXIT_CODE=$?
if [ "${LINT_ALLOW_FAILURE:-true}" = "true" ]; then
  echo "LINT_ALLOW_FAILURE=true: continuing despite lint exit code $LINT_EXIT_CODE" | tee -a lint-py-results.txt
  LINT_EXIT_CODE=0
fi
exit $LINT_EXIT_CODE

