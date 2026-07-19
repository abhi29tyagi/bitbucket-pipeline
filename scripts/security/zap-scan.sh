#!/bin/bash

# OWASP ZAP Security Scan Script
# Performs dynamic application security testing (DAST) on deployed applications
# Supports both frontend and backend applications

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Prepare Docker CLI environment to target the local daemon via a Unix socket
# This ensures we connect to the local Docker daemon instead of remote TCP
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

# Configuration
ZAP_CONTAINER_NAME="${ZAP_CONTAINER_NAME:-zap-scan-$(date +%s)}"
ZAP_IMAGE="${ZAP_IMAGE:-ghcr.io/zaproxy/zaproxy:stable}"
ZAP_PORT="${ZAP_PORT:-8080}"
ZAP_TIMEOUT="${ZAP_TIMEOUT:-300}"  # 5 minutes default
ZAP_ALERT_LEVEL="${ZAP_ALERT_LEVEL:-Medium}"  # High, Medium, Low, Informational
ZAP_CONTEXT_NAME="${ZAP_CONTEXT_NAME:-Application}"
ZAP_API_KEY="${ZAP_API_KEY:-$(openssl rand -hex 16)}"

# Target URL (required)
TARGET_URL="${TARGET_URL:-}"
if [ -z "$TARGET_URL" ]; then
    print_error "TARGET_URL is required (e.g., TARGET_URL=https://api.example.com)"
    exit 1
fi

# Validate URL format
if [[ ! "$TARGET_URL" =~ ^https?:// ]]; then
    print_error "TARGET_URL must start with http:// or https:// (got: $TARGET_URL)"
    exit 1
fi

print_status "Starting OWASP ZAP security scan for: $TARGET_URL"
print_status "ZAP Image: $ZAP_IMAGE"
print_status "Alert Level: $ZAP_ALERT_LEVEL"
print_status "Timeout: ${ZAP_TIMEOUT}s"

# Cleanup function
cleanup() {
    print_step "Cleaning up ZAP container..."
    $DOCKER_CMD rm -f "$ZAP_CONTAINER_NAME" 2>/dev/null || true
}
trap cleanup EXIT

# Start ZAP in daemon mode
# Use host networking so that ZAP shares the host's DNS and routing configuration.
# This ensures URLs like uat-app.nodelink.now resolve exactly as they do on the runner host.
print_step "Starting ZAP daemon..."
$DOCKER_CMD run -d \
    --network host \
    --name "$ZAP_CONTAINER_NAME" \
    -e API_KEY="$ZAP_API_KEY" \
    "$ZAP_IMAGE" \
    zap.sh -daemon -host 0.0.0.0 -port "$ZAP_PORT" \
    -config api.key="$ZAP_API_KEY" \
    -config api.addrs.addr.name=.* \
    -config api.addrs.addr.regex=true

# Wait for ZAP to be ready
print_step "Waiting for ZAP to be ready..."
MAX_WAIT=60
WAIT_COUNT=0
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    if curl -s "http://localhost:${ZAP_PORT}/JSON/core/view/version/?apikey=${ZAP_API_KEY}" >/dev/null 2>&1; then
        print_status "ZAP is ready!"
        break
    fi
    sleep 2
    WAIT_COUNT=$((WAIT_COUNT + 2))
done

if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
    print_error "ZAP failed to start within ${MAX_WAIT}s"
    $DOCKER_CMD logs "$ZAP_CONTAINER_NAME" || true
    exit 1
fi

# Get ZAP version
ZAP_VERSION=$(curl -s "http://localhost:${ZAP_PORT}/JSON/core/view/version/?apikey=${ZAP_API_KEY}" | jq -r '.version' 2>/dev/null || echo "unknown")
print_status "ZAP Version: $ZAP_VERSION"

# Create context (optional - helps ZAP understand the application scope)
print_step "Creating ZAP context..."
CONTEXT_ID=$(curl -s "http://localhost:${ZAP_PORT}/JSON/context/action/newContext/?apikey=${ZAP_API_KEY}&contextName=${ZAP_CONTEXT_NAME}" | jq -r '.contextId' 2>/dev/null || echo "")

if [ -n "$CONTEXT_ID" ] && [ "$CONTEXT_ID" != "null" ]; then
    # Add URL to context
    curl -s "http://localhost:${ZAP_PORT}/JSON/context/action/includeInContext/?apikey=${ZAP_API_KEY}&contextName=${ZAP_CONTEXT_NAME}&regex=${TARGET_URL}.*" >/dev/null || true
    print_status "Created context: $ZAP_CONTEXT_NAME (ID: $CONTEXT_ID)"

    # Configure authentication if provided
    # Option 1: API Key authentication (for REST APIs) - via header
    if [ -n "${ZAP_API_KEY_HEADER:-}" ] && [ -n "${ZAP_API_KEY_VALUE:-}" ]; then
        print_status "Configuring API key authentication (Header: ${ZAP_API_KEY_HEADER})"
        # Add authentication header via ZAP's replacer addon
        curl -s "http://localhost:${ZAP_PORT}/JSON/replacer/action/addRule/?apikey=${ZAP_API_KEY}&description=API%20Key%20Auth&enabled=true&matchType=REQ_HEADER_STR&matchString=${ZAP_API_KEY_HEADER}&matchRegex=false&replacement=${ZAP_API_KEY_VALUE}" >/dev/null || true
    fi

    # Option 2: Basic Authentication (for APIs or web apps)
    if [ -n "${ZAP_BASIC_AUTH_USER:-}" ] && [ -n "${ZAP_BASIC_AUTH_PASS:-}" ]; then
        print_status "Configuring Basic authentication for user: ${ZAP_BASIC_AUTH_USER}"
        # Configure basic auth in ZAP context
        AUTH_METHOD_ID=$(curl -s "http://localhost:${ZAP_PORT}/JSON/authentication/action/setAuthenticationMethod/?apikey=${ZAP_API_KEY}&contextId=${CONTEXT_ID}&authMethodName=basicAuthentication&authMethodConfigParams=hostname=${TARGET_URL}" | jq -r '.authMethodId' 2>/dev/null || echo "")
        if [ -n "$AUTH_METHOD_ID" ] && [ "$AUTH_METHOD_ID" != "null" ]; then
            # Create authenticated user
            USER_ID=$(curl -s "http://localhost:${ZAP_PORT}/JSON/users/action/newUser/?apikey=${ZAP_API_KEY}&contextId=${CONTEXT_ID}&name=zap-user" | jq -r '.id' 2>/dev/null || echo "")
            if [ -n "$USER_ID" ] && [ "$USER_ID" != "null" ]; then
                # Set basic auth credentials
                curl -s "http://localhost:${ZAP_PORT}/JSON/authentication/action/setAuthenticationCredentials/?apikey=${ZAP_API_KEY}&contextId=${CONTEXT_ID}&authMethodConfigParams=username=${ZAP_BASIC_AUTH_USER}&password=${ZAP_BASIC_AUTH_PASS}" >/dev/null || true
                print_status "Basic authentication configured"
            fi
        fi
    fi

    # Option 3: Form-based authentication (for web apps with login forms)
    if [ -n "${ZAP_FORM_LOGIN_URL:-}" ] && [ -n "${ZAP_FORM_USERNAME:-}" ] && [ -n "${ZAP_FORM_PASSWORD:-}" ]; then
        print_status "Configuring Form-based authentication for user: ${ZAP_FORM_USERNAME}"
        # Configure form-based auth
        AUTH_METHOD_ID=$(curl -s "http://localhost:${ZAP_PORT}/JSON/authentication/action/setAuthenticationMethod/?apikey=${ZAP_API_KEY}&contextId=${CONTEXT_ID}&authMethodName=formBasedAuthentication&authMethodConfigParams=loginUrl=${ZAP_FORM_LOGIN_URL}&loginRequestData=username%3D%7B%25username%25%7D%26password%3D%7B%25password%25%7D" | jq -r '.authMethodId' 2>/dev/null || echo "")
        if [ -n "$AUTH_METHOD_ID" ] && [ "$AUTH_METHOD_ID" != "null" ]; then
            # Create authenticated user
            USER_ID=$(curl -s "http://localhost:${ZAP_PORT}/JSON/users/action/newUser/?apikey=${ZAP_API_KEY}&contextId=${CONTEXT_ID}&name=zap-user" | jq -r '.id' 2>/dev/null || echo "")
            if [ -n "$USER_ID" ] && [ "$USER_ID" != "null" ]; then
                # Set form credentials
                curl -s "http://localhost:${ZAP_PORT}/JSON/users/action/setAuthenticationCredentials/?apikey=${ZAP_API_KEY}&contextId=${CONTEXT_ID}&userId=${USER_ID}&authCredentialsConfigParams=username=${ZAP_FORM_USERNAME}&password=${ZAP_FORM_PASSWORD}" >/dev/null || true
                # Enable forced user mode (use this user for all requests)
                curl -s "http://localhost:${ZAP_PORT}/JSON/forcedUser/action/setForcedUser/?apikey=${ZAP_API_KEY}&contextId=${CONTEXT_ID}&userId=${USER_ID}" >/dev/null || true
                curl -s "http://localhost:${ZAP_PORT}/JSON/forcedUser/action/setForcedUserModeEnabled/?apikey=${ZAP_API_KEY}&boolean=true" >/dev/null || true
                print_status "Form-based authentication configured"
            fi
        fi
    fi
fi

# Spider scan (crawl the application)
print_step "Starting spider scan (crawling application)..."
SPIDER_SCAN_ID=$(curl -s "http://localhost:${ZAP_PORT}/JSON/spider/action/scan/?apikey=${ZAP_API_KEY}&url=${TARGET_URL}&contextName=${ZAP_CONTEXT_NAME}" | jq -r '.scan' 2>/dev/null || echo "")

if [ -n "$SPIDER_SCAN_ID" ] && [ "$SPIDER_SCAN_ID" != "null" ]; then
    print_status "Spider scan started (ID: $SPIDER_SCAN_ID)"
    
    # Wait for spider to complete
    SPIDER_STATUS="0"
    while [ "$SPIDER_STATUS" -lt 100 ]; do
        sleep 5
        SPIDER_STATUS=$(curl -s "http://localhost:${ZAP_PORT}/JSON/spider/view/status/?apikey=${ZAP_API_KEY}&scanId=${SPIDER_SCAN_ID}" | jq -r '.status' 2>/dev/null || echo "100")
        print_status "Spider progress: ${SPIDER_STATUS}%"
    done
    print_status "Spider scan completed"
else
    print_warning "Spider scan failed to start, continuing with active scan..."
fi

# Active scan (attack the application)
print_step "Starting active scan (security testing)..."
ACTIVE_SCAN_ID=$(curl -s "http://localhost:${ZAP_PORT}/JSON/ascan/action/scan/?apikey=${ZAP_API_KEY}&url=${TARGET_URL}&contextName=${ZAP_CONTEXT_NAME}&recurse=true" | jq -r '.scan' 2>/dev/null || echo "")

if [ -n "$ACTIVE_SCAN_ID" ] && [ "$ACTIVE_SCAN_ID" != "null" ]; then
    print_status "Active scan started (ID: $ACTIVE_SCAN_ID)"
    
    # Wait for active scan to complete (with timeout and stuck detection)
    ACTIVE_STATUS="0"
    ELAPSED=0
    STUCK_THRESHOLD=120  # Consider stuck if no progress for 2 minutes
    LAST_STATUS_TIME=0
    LAST_STATUS_VALUE="0"
    
    while [ "$ACTIVE_STATUS" -lt 100 ] && [ $ELAPSED -lt $ZAP_TIMEOUT ]; do
        sleep 10
        ELAPSED=$((ELAPSED + 10))
        ACTIVE_STATUS=$(curl -s "http://localhost:${ZAP_PORT}/JSON/ascan/view/status/?apikey=${ZAP_API_KEY}&scanId=${ACTIVE_SCAN_ID}" | jq -r '.status' 2>/dev/null || echo "100")
        print_status "Active scan progress: ${ACTIVE_STATUS}% (elapsed: ${ELAPSED}s)"
        
        # Detect if scan is stuck (status hasn't changed for a while)
        if [ "$ACTIVE_STATUS" = "$LAST_STATUS_VALUE" ] && [ "$ACTIVE_STATUS" != "100" ]; then
            STUCK_DURATION=$((ELAPSED - LAST_STATUS_TIME))
            if [ $STUCK_DURATION -ge $STUCK_THRESHOLD ]; then
                print_warning "Active scan appears stuck at ${ACTIVE_STATUS}% for ${STUCK_DURATION}s, stopping scan..."
                curl -s "http://localhost:${ZAP_PORT}/JSON/ascan/action/stop/?apikey=${ZAP_API_KEY}&scanId=${ACTIVE_SCAN_ID}" >/dev/null || true
                break
            fi
        else
            # Status changed, reset stuck detection
            LAST_STATUS_VALUE="$ACTIVE_STATUS"
            LAST_STATUS_TIME=$ELAPSED
        fi
    done
    
    if [ $ELAPSED -ge $ZAP_TIMEOUT ]; then
        print_warning "Active scan timed out after ${ZAP_TIMEOUT}s, stopping scan..."
        curl -s "http://localhost:${ZAP_PORT}/JSON/ascan/action/stop/?apikey=${ZAP_API_KEY}&scanId=${ACTIVE_SCAN_ID}" >/dev/null || true
    elif [ "$ACTIVE_STATUS" = "100" ]; then
        print_status "Active scan completed"
    else
        print_warning "Active scan stopped early (status: ${ACTIVE_STATUS}%)"
    fi
else
    print_warning "Active scan failed to start"
fi

# Generate reports
print_step "Generating security reports..."

# HTML Report
print_status "Generating HTML report..."
curl -s "http://localhost:${ZAP_PORT}/OTHER/core/other/htmlreport/?apikey=${ZAP_API_KEY}" > zap-report.html || {
    print_warning "Failed to generate HTML report"
}

# JSON Report (detailed)
print_status "Generating JSON report..."
curl -s "http://localhost:${ZAP_PORT}/JSON/core/view/alerts/?apikey=${ZAP_API_KEY}&baseurl=" > zap-report.json || {
    print_warning "Failed to generate JSON report"
    echo '{"alerts": []}' > zap-report.json
}

# XML Report (for compatibility)
print_status "Generating XML report..."
curl -s "http://localhost:${ZAP_PORT}/OTHER/core/other/xmlreport/?apikey=${ZAP_API_KEY}" > zap-report.xml || {
    print_warning "Failed to generate XML report"
}

# SARIF Report (for SonarQube)
print_status "Generating SARIF report for SonarQube..."
if [ -f "zap-report.json" ] && command -v jq >/dev/null 2>&1; then
    # Convert ZAP JSON to SARIF format
    jq '{
        "$schema": "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",
        "version": "2.1.0",
        "runs": [{
            "tool": {
                "driver": {
                    "name": "OWASP ZAP",
                    "version": "'"${ZAP_VERSION}"'",
                    "informationUri": "https://www.zaproxy.org/"
                }
            },
            "results": [
                (.alerts[]? | {
                    "ruleId": (.pluginid // "unknown" | tostring),
                    "level": (
                        if .risk == "High" then "error"
                        elif .risk == "Medium" then "warning"
                        elif .risk == "Low" then "note"
                        else "none"
                    end
                    ),
                    "message": {
                        "text": (.name // "Security issue detected")
                    },
                    "locations": [{
                        "physicalLocation": {
                            "artifactLocation": {
                                "uri": (.url // "'"${TARGET_URL}"'")
                            },
                            "region": {
                                "startLine": 1
                            }
                        }
                    }],
                    "properties": {
                        "risk": (.risk // "Unknown"),
                        "confidence": (.confidence // "Unknown"),
                        "cweid": (.cweid // ""),
                        "wascid": (.wascid // ""),
                        "description": (.description // ""),
                        "solution": (.solution // ""),
                        "reference": (.reference // "")
                    }
                })
            ]
        }]
    }' zap-report.json > zap-report.sarif 2>/dev/null || {
        print_warning "Failed to convert JSON to SARIF format"
        # Create minimal SARIF if conversion fails
        echo '{"$schema":"https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json","version":"2.1.0","runs":[{"results":[]}]}' > zap-report.sarif
    }
    print_status "SARIF report generated: zap-report.sarif"
else
    print_warning "jq not available or JSON report missing, skipping SARIF conversion"
    echo '{"$schema":"https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json","version":"2.1.0","runs":[{"results":[]}]}' > zap-report.sarif
fi

# Analyze results
print_step "Analyzing scan results..."
if [ -f "zap-report.json" ]; then
    HIGH_COUNT=$(jq -r '[.alerts[]? | select(.risk == "High")] | length' zap-report.json 2>/dev/null || echo "0")
    MEDIUM_COUNT=$(jq -r '[.alerts[]? | select(.risk == "Medium")] | length' zap-report.json 2>/dev/null || echo "0")
    LOW_COUNT=$(jq -r '[.alerts[]? | select(.risk == "Low")] | length' zap-report.json 2>/dev/null || echo "0")
    INFO_COUNT=$(jq -r '[.alerts[]? | select(.risk == "Informational")] | length' zap-report.json 2>/dev/null || echo "0")
    
    print_status "Scan Results Summary:"
    print_status "  High: $HIGH_COUNT"
    print_status "  Medium: $MEDIUM_COUNT"
    print_status "  Low: $LOW_COUNT"
    print_status "  Informational: $INFO_COUNT"
    
    # Check if we should fail based on alert level
    if [ "$ZAP_ALERT_LEVEL" = "High" ] && [ "$HIGH_COUNT" -gt 0 ]; then
        print_error "High severity issues found. Failing build."
        exit 1
    elif [ "$ZAP_ALERT_LEVEL" = "Medium" ] && [ "$MEDIUM_COUNT" -gt 0 ];  then
        print_warning "Medium severity issues found, but continuing build."
    elif [ "$ZAP_ALERT_LEVEL" = "Low" ] && [ "$LOW_COUNT" -gt 0 ]; then
        print_warning "Only low severity issues found, so continuing build."
    else 
        print_status "No issues found."
    fi
else
    print_warning "Could not analyze results (JSON report missing)"
fi

print_status "ZAP security scan completed successfully"
print_status "Reports generated:"
print_status "  - zap-report.html (human-readable)"
print_status "  - zap-report.json (detailed JSON)"
print_status "  - zap-report.xml (XML format)"
print_status "  - zap-report.sarif (SonarQube format)"

