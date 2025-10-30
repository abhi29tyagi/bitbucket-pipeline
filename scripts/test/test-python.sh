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

export DOCKER_HOST="unix:///var/run/docker.sock"
USER_ID=$(id -u)
GROUP_ID=$(id -g)
PYTHON_VERSION="${PYTHON_VERSION:-3.11}"
PY_IMAGE="${PY_IMAGE:-python:${PYTHON_VERSION}-slim}"

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
    # Install test deps
    pip install pytest pytest-cov junit-xml >/dev/null 2>&1 || true
    if [ -f requirements.txt ]; then pip install -r requirements.txt || true; fi
    if [ -f requirements-dev.txt ]; then pip install -r requirements-dev.txt || true; fi
    # Avoid installing the project itself during tests to prevent wheel builds unless explicitly requested
    if [ "${INSTALL_PROJECT_FOR_TESTS}" = "true" ] && [ -f pyproject.toml ]; then pip install . || true; fi

    # If no tests are collected, skip coverage run and write minimal JUnit
    if pytest --collect-only -q >/tmp/pytest-collect.txt 2>/dev/null; then
      if [ ! -s /tmp/pytest-collect.txt ]; then
        echo "No tests collected; writing minimal JUnit XML and skipping coverage"
        printf '\''%s\n'\'' \
          "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" \
          "<testsuites>" \
          "  <testsuite name=\"pytest\" tests=\"0\" failures=\"0\" errors=\"0\" skipped=\"0\"/>" \
          "</testsuites>" \
        > test-results-py.xml
        exit 0
      fi
    fi

    # Run pytest with JUnit + coverage
    set +e
    pytest -q --maxfail=1 --disable-warnings \
      --junitxml=test-results-py.xml \
      --cov=. --cov-report=xml:coverage.xml --cov-report=term-missing 2>&1 | tee test-output-py.txt
    EXIT=${PIPESTATUS[0]}
    # Treat PyTest exit code 5 (no tests collected) as success
    if [ "$EXIT" -eq 5 ]; then
      echo "No tests collected (pytest exit 5); treating as success"
      EXIT=0
    fi
    # Ensure a non-empty, well-formed XML exists even if pytest produced nothing
    if [ ! -s test-results-py.xml ]; then
      echo "test-results-py.xml was empty; writing minimal report"
      printf '\''%s\n'\'' \
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" \
        "<testsuites>" \
        "  <testsuite name=\"pytest\" tests=\"0\" failures=\"0\" errors=\"0\" skipped=\"0\"/>" \
        "</testsuites>" \
      > test-results-py.xml
    fi
    set -e
    exit $EXIT
  '

TEST_EXIT_CODE=$?
# Basic human summary
echo "=== Python Test Summary ===" > test-summary-py.txt
tail -n 200 ${APP_PATH}/test-output-py.txt >> test-summary-py.txt 2>/dev/null || true

if [ "${TEST_ALLOW_FAILURE:-true}" = "true" ]; then
  echo "TEST_ALLOW_FAILURE=true: continuing despite test exit code $TEST_EXIT_CODE" | tee -a test-summary-py.txt
  TEST_EXIT_CODE=0
fi
exit $TEST_EXIT_CODE

