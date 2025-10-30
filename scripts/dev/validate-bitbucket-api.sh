#!/bin/bash
set -euo pipefail

# Validation script for Bitbucket Deployment Variables API integration
# Note: Located in scripts/dev/ to avoid confusion with pipeline test stage scripts

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0

# Logging functions
log_test() { echo -e "[TEST ] $*"; }
log_pass() { echo -e "${GREEN}[PASS ] $*${NC}"; ((TESTS_PASSED++)); }
log_fail() { echo -e "${RED}[FAIL ] $*${NC}"; ((TESTS_FAILED++)); }
log_skip() { echo -e "${YELLOW}[SKIP ] $*${NC}"; }

# Source the API utilities
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
API_UTILS_PATH="$SCRIPT_DIR/../utils/bitbucket-api.sh"

if [ ! -f "$API_UTILS_PATH" ]; then
    log_fail "API utilities not found at $API_UTILS_PATH"
    exit 1
fi

source "$API_UTILS_PATH"

# Test function definitions exist
test_function_definitions() {
    log_test "Testing function definitions..."
    
    local functions
    functions=("fetch_deployment_variables" "deployment_vars_to_build_args" "get_build_args_with_api" "validate_api_credentials" "test_api_connectivity")
    
    for func in "${functions[@]}"; do
        if command -v "$func" >/dev/null 2>&1; then
            log_pass "Function $func is defined"
        else
            log_fail "Function $func is not defined"
        fi
    done
}

# Test credential validation (matching pr_comment.sh pattern)
test_credential_validation() {
    log_test "Testing credential validation..."
    
    # Save original token
    local orig_token="${BITBUCKET_ACCESS_TOKEN:-}"
    
    # Test with no credentials
    unset BITBUCKET_ACCESS_TOKEN
    if validate_api_credentials 2>/dev/null; then
        log_fail "Should fail with no credentials"
    else
        log_pass "Correctly rejects no credentials"
    fi
    
    # Test with access token
    export BITBUCKET_ACCESS_TOKEN="test"
    if validate_api_credentials 2>/dev/null; then
        log_pass "Accepts access token credentials"
    else
        log_fail "Should accept access token credentials"
    fi
    
    # Restore original token
    [ -n "$orig_token" ] && export BITBUCKET_ACCESS_TOKEN="$orig_token" || unset BITBUCKET_ACCESS_TOKEN
}

# Test deployment vars to build args conversion
test_build_args_conversion() {
    log_test "Testing deployment vars to build args conversion..."
    
    local test_vars="API_URL=https://api.example.com
DATABASE_URL=postgres://db.example.com
EMPTY_VAR=
FEATURE_FLAGS=flag1,flag2"
    
    local result=$(echo "$test_vars" | deployment_vars_to_build_args)
    
    if [[ "$result" == *"--build-arg API_URL=https://api.example.com"* ]]; then
        log_pass "Correctly converts API_URL"
    else
        log_fail "Failed to convert API_URL"
    fi
    
    if [[ "$result" == *"--build-arg DATABASE_URL=postgres://db.example.com"* ]]; then
        log_pass "Correctly converts DATABASE_URL"
    else
        log_fail "Failed to convert DATABASE_URL"
    fi
    
    if [[ "$result" == *"--build-arg EMPTY_VAR="* ]]; then
        log_fail "Should not include empty variables"
    else
        log_pass "Correctly skips empty variables"
    fi
    
    if [[ "$result" == *"--build-arg FEATURE_FLAGS=flag1,flag2"* ]]; then
        log_pass "Correctly converts FEATURE_FLAGS with comma values"
    else
        log_fail "Failed to convert FEATURE_FLAGS"
    fi
}

# Test build args with API (mocked)
test_build_args_with_api_fallback() {
    log_test "Testing build args with API fallback..."
    
    # Save original values
    local orig_use_api="${USE_BITBUCKET_DEPLOYMENT_VARS:-}"
    local orig_workspace="${BITBUCKET_WORKSPACE:-}"
    
    # Test fallback when API is disabled
    export USE_BITBUCKET_DEPLOYMENT_VARS="false"
    export TEST_VAR_dev="test_value"
    
    local result=$(get_build_args_with_api "dev" 2>/dev/null || echo "")
    
    if [[ "$result" == *"--build-arg TEST_VAR=test_value"* ]]; then
        log_pass "Fallback method works correctly"
    else
        log_fail "Fallback method failed: $result"
    fi
    
    # Test with missing workspace (should fallback)
    export USE_BITBUCKET_DEPLOYMENT_VARS="true"
    unset BITBUCKET_WORKSPACE
    
    result=$(get_build_args_with_api "dev" 2>/dev/null || echo "")
    
    if [[ "$result" == *"--build-arg TEST_VAR=test_value"* ]]; then
        log_pass "Falls back when workspace missing"
    else
        log_fail "Should fallback when workspace missing"
    fi
    
    # Cleanup
    unset TEST_VAR_dev
    [ -n "$orig_use_api" ] && export USE_BITBUCKET_DEPLOYMENT_VARS="$orig_use_api" || unset USE_BITBUCKET_DEPLOYMENT_VARS
    [ -n "$orig_workspace" ] && export BITBUCKET_WORKSPACE="$orig_workspace" || unset BITBUCKET_WORKSPACE
}

# Test API connectivity (only if credentials are available)
test_api_connectivity_live() {
    log_test "Testing live API connectivity..."
    
    if ! validate_api_credentials 2>/dev/null; then
        log_skip "No valid credentials available for live API test"
        return
    fi
    
    if [ -z "${BITBUCKET_WORKSPACE:-}" ]; then
        log_skip "BITBUCKET_WORKSPACE not set, skipping live API test"
        return
    fi
    
    if test_api_connectivity 2>/dev/null; then
        log_pass "Live API connectivity test successful"
    else
        log_fail "Live API connectivity test failed"
    fi
}

# Run all tests
main() {
    echo "=== Bitbucket Deployment Variables API Test Suite ==="
    echo ""
    
    test_function_definitions
    echo ""
    
    test_credential_validation
    echo ""
    
    test_build_args_conversion
    echo ""
    
    test_build_args_with_api_fallback
    echo ""
    
    test_api_connectivity_live
    echo ""
    
    # Summary
    echo "=== Test Summary ==="
    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        exit 1
    fi
}

# Run the tests
main "$@"
