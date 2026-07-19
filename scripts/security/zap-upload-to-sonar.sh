#!/bin/bash

# Script to upload OWASP ZAP results to SonarQube
# This script uploads ZAP findings to an existing SonarQube project

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if required environment variables are set
if [ -z "$SONAR_HOST_URL" ]; then
    print_error "SONAR_HOST_URL environment variable is not set"
    exit 1
fi

if [ -z "$SONAR_TOKEN" ]; then
    print_error "SONAR_TOKEN environment variable is not set"
    exit 1
fi

# Check if ZAP issues file exists
ZAP_ISSUES_FILE="sonar-issues-zap.json"
if [ ! -f "$ZAP_ISSUES_FILE" ]; then
    print_warning "ZAP issues file $ZAP_ISSUES_FILE not found. Skipping ZAP upload."
    exit 0
fi

# Check if Docker Scout issues file exists (from previous CI stage)
SCOUT_ISSUES_FILE="sonar-issues.json"
EXTERNAL_ISSUES_FILES="$ZAP_ISSUES_FILE"
if [ -f "$SCOUT_ISSUES_FILE" ]; then
    print_status "Found Docker Scout results, will include both ZAP and Scout issues"
    EXTERNAL_ISSUES_FILES="$SCOUT_ISSUES_FILE,$ZAP_ISSUES_FILE"
else
    print_status "No Docker Scout results found, uploading ZAP issues only"
fi

print_status "Preparing OWASP ZAP results for SonarQube upload..."

# Validate JSON format
if ! jq empty "$ZAP_ISSUES_FILE" 2>/dev/null; then
    print_error "Invalid JSON format in ZAP issues file"
    exit 1
fi

# Check if file has any results
ISSUE_COUNT=$(jq -r '.issues | length' "$ZAP_ISSUES_FILE" 2>/dev/null || echo "0")
if [ "$ISSUE_COUNT" -eq 0 ]; then
    print_status "No security findings in ZAP issues file. Skipping upload."
    exit 0
fi

print_status "Found $ISSUE_COUNT ZAP security findings to upload"

# Get project key (required for SonarQube) - use same logic as sonar stage
# ZAP scans only run on release branches, so we only need branch-based project keys
if [ -z "$SONAR_PROJECT_KEY" ]; then
    # For branches, use branch-specific project key
    export SONAR_PROJECT_KEY="${SONAR_PROJECT_KEY:-$BITBUCKET_REPO_SLUG}-${BITBUCKET_BRANCH}"
    print_status "Using branch-based project key: $SONAR_PROJECT_KEY"
    # Replace all '/' with '-' to satisfy Sonar key constraints (e.g., release/v1.0 -> release-v1.0)
    SONAR_PROJECT_KEY="${SONAR_PROJECT_KEY//\//-}"
    print_status "Normalized project key: $SONAR_PROJECT_KEY"
fi

if [ -z "$SONAR_PROJECT_KEY" ]; then
    print_error "SONAR_PROJECT_KEY is required. Set it as environment variable."
    exit 1
fi

# Remove trailing slash from URL
SONAR_HOST_URL="${SONAR_HOST_URL%/}"

# Prepare Docker CLI environment to target the local daemon via a Unix socket
export DOCKER_HOST="unix:///var/run/docker.sock"

# Check Docker permissions and set DOCKER_CMD (use sudo if needed)
if docker info >/dev/null 2>&1; then
    DOCKER_CMD="docker"
elif command -v sudo >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1; then
    DOCKER_CMD="sudo docker"
    print_warning "Using sudo for Docker commands (user not in docker group)"
else
    print_error "Cannot access Docker daemon. Ensure user is in docker group or has sudo permissions."
    exit 1
fi

# Use sonar-scanner to upload external issues (same pattern as SonarQube step)
print_status "Uploading ZAP results to SonarQube project: $SONAR_PROJECT_KEY"

# Use Docker-based sonar-scanner (same as SonarQube step)
SONAR_CMD="$DOCKER_CMD run --rm -v $(pwd):/workspace -v ${HOME}/.sonar/cache:/root/.sonar/cache -w /workspace sonarsource/sonar-scanner-cli:latest sonar-scanner"

# Ensure ZAP-SECURITY-REPORT.md exists (required for external issues to be attached)
ZAP_REPORT_FILE="ZAP-SECURITY-REPORT.md"
if [ ! -f "$ZAP_REPORT_FILE" ]; then
    print_status "Creating $ZAP_REPORT_FILE placeholder file..."
    echo "# OWASP ZAP Security Scan Results" > "$ZAP_REPORT_FILE"
    echo "" >> "$ZAP_REPORT_FILE"
    echo "This file is used to anchor ZAP runtime security findings in SonarQube." >> "$ZAP_REPORT_FILE"
    echo "ZAP issues are runtime security vulnerabilities detected in the deployed application." >> "$ZAP_REPORT_FILE"
fi

# Run minimal scan to upload external issues only (without analyzing source code)
# Use the ZAP report file as the only source to avoid overwriting previous analysis
if $SONAR_CMD \
    -Dsonar.host.url="$SONAR_HOST_URL" \
    -Dsonar.login="$SONAR_TOKEN" \
    -Dsonar.projectKey="$SONAR_PROJECT_KEY" \
    -Dsonar.projectName="$SONAR_PROJECT_KEY" \
    -Dsonar.projectVersion="1.0" \
    -Dsonar.sources="$ZAP_REPORT_FILE" \
    -Dsonar.exclusions="**/*" \
    -Dsonar.inclusions="$ZAP_REPORT_FILE" \
    -Dsonar.externalIssuesReportPaths="$EXTERNAL_ISSUES_FILES" \
    -Dsonar.working.directory=/tmp/sonar-zap 2>&1 | tee /tmp/sonar-zap-upload.log; then
    print_status "✅ Successfully uploaded ZAP results to SonarQube"
    print_status "View results: ${SONAR_HOST_URL}/dashboard?id=${SONAR_PROJECT_KEY}"
else
    print_error "Failed to upload ZAP results to SonarQube. Check logs:"
    tail -n 50 /tmp/sonar-zap-upload.log || true
    exit 1
fi

print_status "OWASP ZAP results upload completed"

