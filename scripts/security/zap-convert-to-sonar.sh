#!/bin/bash

# Script to convert ZAP SARIF report to SonarQube Generic External Issues format
# This is separate from docker-scout-convert.sh to keep CI (Docker Scout) and CD (ZAP) logic separate
# Usage: zap-convert-to-sonar.sh <input-sarif-file> <output-json-file>

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parse arguments
SARIF_FILE="${1:-zap-report.sarif}"
OUTPUT_FILE="${2:-sonar-issues-zap.json}"

if [ ! -f "$SARIF_FILE" ]; then
    print_error "ZAP SARIF file not found: $SARIF_FILE"
    exit 1
fi

print_status "Converting ZAP SARIF report to SonarQube format..."

# Validate SARIF file format
if ! jq empty "$SARIF_FILE" 2>/dev/null; then
    print_error "Invalid JSON format in SARIF file: $SARIF_FILE"
    exit 1
fi

# Check if SARIF file has any results
RESULTS_COUNT=$(jq '.runs[0].results | length' "$SARIF_FILE" 2>/dev/null || echo "0")
if [ "$RESULTS_COUNT" -eq 0 ]; then
    print_status "No security findings in ZAP SARIF file. Skipping conversion."
    echo '{"issues": []}' > "$OUTPUT_FILE"
    exit 0
fi

print_status "Found $RESULTS_COUNT ZAP security findings; generating $OUTPUT_FILE"

# ZAP issues are runtime security findings from deployed applications
# Use a simple placeholder file that doesn't require source code
TARGET_FILE="ZAP-SECURITY-REPORT.md"

# Create a minimal placeholder file if it doesn't exist
if [ ! -f "$TARGET_FILE" ]; then
    echo "# OWASP ZAP Security Scan Results" > "$TARGET_FILE"
    echo "" >> "$TARGET_FILE"
    echo "This file is used to anchor ZAP runtime security findings in SonarQube." >> "$TARGET_FILE"
    echo "ZAP issues are runtime security vulnerabilities detected in the deployed application." >> "$TARGET_FILE"
fi

print_status "ZAP runtime security findings will be attached to: $TARGET_FILE"

# Convert SARIF to SonarQube Generic External Issues format
if ! command -v jq >/dev/null 2>&1; then
    print_error "jq is required to convert SARIF to Sonar format"
    exit 1
fi

# ZAP-specific transformation with enhanced actionable messages
jq --arg file "$TARGET_FILE" --arg engine "zap" '{
  issues: [
    (.runs[0].results // [])[] |
    {
      engineId: $engine,
      ruleId: (.ruleId // ($engine + "-" + (.properties.risk // "unknown"))),
      severity: (
        (.level // "warning" | ascii_downcase) |
        if . == "error" then "CRITICAL"
        elif . == "warning" then "MAJOR"
        elif . == "note" then "MINOR"
        else "INFO" end
      ),
      type: "VULNERABILITY",
      primaryLocation: {
        message: (
          # Build comprehensive message with actionable information
          (.message.text // "Security issue detected by OWASP ZAP") as $title |
          (.properties.description // "") as $desc |
          (.properties.solution // "") as $solution |
          (.locations[0].physicalLocation.artifactLocation.uri // "") as $url |
          (.properties.reference // "") as $ref |
          (.properties.cweid // "") as $cwe |
          (.properties.wascid // "") as $wasc |
          (.properties.risk // "Unknown") as $risk |
          (.properties.confidence // "Unknown") as $confidence |

          # Construct formatted message
          $title +
          (if $desc != "" then "\n\nDescription:\n" + $desc else "" end) +
          (if $solution != "" then "\n\nSolution:\n" + $solution else "" end) +
          (if $url != "" then "\n\nAffected URL: " + $url else "" end) +
          (if $cwe != "" then "\nCWE ID: " + $cwe else "" end) +
          (if $wasc != "" then "\nWASC ID: " + $wasc else "" end) +
          (if $risk != "Unknown" then "\nRisk: " + $risk else "" end) +
          (if $confidence != "Unknown" then "\nConfidence: " + $confidence else "" end) +
          (if $ref != "" then "\n\nReference: " + $ref else "" end)
        ),
        filePath: $file,
        textRange: (.locations[0].physicalLocation.region // {})
      },
      secondaryLocations: [],
      effortMinutes: (
        (.properties.risk // "low" | ascii_downcase) |
        if . == "high" then 60
        elif . == "medium" then 30
        elif . == "low" then 15
        else 5 end
      )
    }
  ]
}' "$SARIF_FILE" > "$OUTPUT_FILE"

if [ -s "$OUTPUT_FILE" ]; then
    # Ensure there is at least one issue entry
    COUNT=$(jq -r '.issues | length' "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$COUNT" -gt 0 ]; then
        print_status "Wrote $OUTPUT_FILE with $COUNT external issues (attached to $TARGET_FILE)"
    else
        print_warning "$OUTPUT_FILE contains 0 issues; skipping import"
        rm -f "$OUTPUT_FILE" || true
    fi
else
    print_warning "No issues produced in $OUTPUT_FILE"
fi

print_status "ZAP report conversion completed"

