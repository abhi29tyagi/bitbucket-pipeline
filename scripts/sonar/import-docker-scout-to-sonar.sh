#!/bin/bash

# Script to import Docker Scout SARIF results to SonarQube
# This script handles the integration between Docker Scout and SonarQube

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

# Check if SARIF file exists
SARIF_FILE="docker-scout-results.sarif"
if [ ! -f "$SARIF_FILE" ]; then
    print_warning "SARIF file $SARIF_FILE not found. Skipping Docker Scout import."
    exit 0
fi

print_status "Preparing Docker Scout results for SonarQube (generic external issues, current format)..."

# Validate SARIF file format
if ! jq empty "$SARIF_FILE" 2>/dev/null; then
    print_error "Invalid JSON format in SARIF file"
    exit 1
fi

# Check if SARIF file has any results
RESULTS_COUNT=$(jq '.runs[0].results | length' "$SARIF_FILE" 2>/dev/null || echo "0")
if [ "$RESULTS_COUNT" -eq 0 ]; then
    print_status "No security findings in SARIF file. Skipping conversion."
    exit 0
fi

print_status "Found $RESULTS_COUNT security findings; generating sonar-issues.json"

# Choose a real file within the project to attach issues to (so Sonar can index them)
TARGET_FILE=""
for f in Dockerfile package.json pyproject.toml requirements.txt README.md; do
  if [ -f "$f" ]; then TARGET_FILE="$f"; break; fi
done
if [ -z "$TARGET_FILE" ]; then
  print_warning "No canonical project file found (Dockerfile/package.json/pyproject.toml/requirements.txt/README.md). External issues will be associated to project root, which some Sonar versions may ignore."
  TARGET_FILE="README.md"
  # Create a placeholder so Sonar has a file to anchor to
  [ -f "$TARGET_FILE" ] || echo "Docker Scout external issues placeholder" > "$TARGET_FILE"
fi

# Convert SARIF to SonarQube Generic External Issues format (current schema)
if ! command -v jq >/dev/null 2>&1; then
    print_error "jq is required to convert SARIF to Sonar format"
    exit 1
fi

jq --arg file "$TARGET_FILE" '{
  issues: [
    (.runs[0].results // [])[] |
    {
      engineId: "docker-scout",
      ruleId: (.ruleId // "docker-scout"),
      severity: ( ( .level // "warning" ) | ascii_downcase |
        if . == "error" then "CRITICAL"
        elif . == "warning" then "MAJOR"
        elif . == "note" then "MINOR"
        else "INFO" end
      ),
      type: "VULNERABILITY",
      primaryLocation: {
        message: (.message.text // "Security issue detected by Docker Scout"),
        filePath: $file
      }
    }
  ]
}' "$SARIF_FILE" > sonar-issues.json

if [ -s sonar-issues.json ]; then
    # Ensure there is at least one issue entry
    COUNT=$(jq -r '.issues | length' sonar-issues.json 2>/dev/null || echo "0")
    if [ "$COUNT" -gt 0 ]; then
        print_status "Wrote sonar-issues.json with $COUNT external issues (attached to $TARGET_FILE)"
    else
        print_warning "sonar-issues.json contains 0 issues; skipping import"
        rm -f sonar-issues.json || true
    fi
else
    print_warning "No issues produced in sonar-issues.json"
fi

print_status "Docker Scout report preparation completed"
