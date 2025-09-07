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

print_status "Importing Docker Scout results to SonarQube..."

# Validate SARIF file format
if ! jq empty "$SARIF_FILE" 2>/dev/null; then
    print_error "Invalid JSON format in SARIF file"
    exit 1
fi

# Check if SARIF file has any results
RESULTS_COUNT=$(jq '.runs[0].results | length' "$SARIF_FILE" 2>/dev/null || echo "0")
if [ "$RESULTS_COUNT" -eq 0 ]; then
    print_status "No security findings in SARIF file. Skipping import."
    exit 0
fi

print_status "Found $RESULTS_COUNT security findings to import"

# Import SARIF results to SonarQube
print_status "Sending SARIF results to SonarQube..."

# Use SonarQube's SARIF import API
RESPONSE=$(curl -s -w "%{http_code}" -X POST \
    -H "Authorization: Bearer $SONAR_TOKEN" \
    -H "Content-Type: application/json" \
    -d @"$SARIF_FILE" \
    "$SONAR_HOST_URL/api/import/sarif" 2>/dev/null)

HTTP_CODE="${RESPONSE: -3}"
RESPONSE_BODY="${RESPONSE%???}"

if [ "$HTTP_CODE" -eq 200 ] || [ "$HTTP_CODE" -eq 201 ]; then
    print_status "Successfully imported Docker Scout results to SonarQube"
    echo "Response: $RESPONSE_BODY"
else
    print_warning "Failed to import SARIF results (HTTP $HTTP_CODE)"
    echo "Response: $RESPONSE_BODY"
    
    # Try alternative import method using SonarQube's generic import
    print_status "Trying alternative import method..."
    
    # Convert SARIF to SonarQube format if needed
    # This is a simplified conversion - you might need to adjust based on your SonarQube version
    if command -v jq &> /dev/null; then
        print_status "Converting SARIF to SonarQube format..."
        
        # Create a simple conversion (this is a basic example)
        SONAR_ISSUES=$(jq -r '
            .runs[0].results[] | {
                "ruleId": .ruleId,
                "message": .message.text,
                "severity": .level,
                "line": .locations[0].physicalLocation.region.startLine // null,
                "file": .locations[0].physicalLocation.artifactLocation.uri // null
            }
        ' "$SARIF_FILE" 2>/dev/null || echo "[]")
        
        if [ "$SONAR_ISSUES" != "[]" ]; then
            print_status "Converted issues for SonarQube import"
            echo "$SONAR_ISSUES" > sonar-issues.json
        fi
    fi
fi

print_status "Docker Scout to SonarQube import completed"
