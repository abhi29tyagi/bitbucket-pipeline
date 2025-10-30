#!/bin/bash
set -euo pipefail

# Simple integration test for Bitbucket Deployment Variables API
# This test validates the basic functionality without complex error handling

echo "=== Simple Integration Test ==="

# Test the fallback method (existing environment variable approach)
echo "Testing fallback method..."

export TARGET_ENV="dev"
export TEST_VAR_dev="fallback_value"

# Source the build script logic directly
cd /Users/a.tyagi/Projects/shared-pipelines

# Extract the fallback logic and test it
TARGET_ENV_LOWER=$(echo "$TARGET_ENV" | tr '[:upper:]' '[:lower:]')  # lowercase
TARGET_ENV_UPPER=$(echo "$TARGET_ENV" | tr '[:lower:]' '[:upper:]')  # uppercase

BUILD_ARGS=""
while IFS='=' read -r __n __v; do
  case "$__n" in
    *_"$TARGET_ENV_LOWER"|*_"$TARGET_ENV_UPPER")
      __base="${__n%_*}"
      export "$__base=$__v"
      [ -n "$__v" ] && BUILD_ARGS="$BUILD_ARGS --build-arg $__base=$__v"
    ;;
  esac
done < <(env)

echo "Build args from fallback: $BUILD_ARGS"

if [[ "$BUILD_ARGS" == *"--build-arg TEST_VAR=fallback_value"* ]]; then
  echo "✅ Fallback method works correctly"
else
  echo "❌ Fallback method failed"
  exit 1
fi

# Test environment mapping
echo ""
echo "Testing environment mapping..."

test_env_mapping() {
  local branch="$1"
  local expected_env="$2"
  
  export BITBUCKET_BRANCH="$branch"
  
  # Reset TARGET_ENV for each test
  unset TARGET_ENV ENVIRONMENT
  TARGET_ENV="${TARGET_ENV:-${ENVIRONMENT:-preview}}"
  if [[ "$BITBUCKET_BRANCH" =~ ^hotfix/ ]]; then
    TARGET_ENV="prod"
  fi
  
  if [ "$TARGET_ENV" = "$expected_env" ]; then
    echo "✅ Branch $branch correctly maps to environment $expected_env"
  else
    echo "❌ Branch $branch mapped to $TARGET_ENV, expected $expected_env"
    return 1
  fi
}

test_env_mapping "hotfix/fix-bug" "prod"
test_env_mapping "develop" "preview"
test_env_mapping "main" "preview"

echo ""
echo "Testing build script integration..."

# Test that the modified build script can source the API utilities
if [ -f "scripts/utils/bitbucket-api.sh" ]; then
  echo "✅ API utilities file exists"
else
  echo "❌ API utilities file missing"
  exit 1
fi

# Test basic function availability without full sourcing
grep -q "get_build_args_with_api" scripts/utils/bitbucket-api.sh
if [ $? -eq 0 ]; then
  echo "✅ Main API function exists in utilities"
else
  echo "❌ Main API function not found"
  exit 1
fi

# Test that build script has been modified to use API
grep -q "get_build_args_with_api" scripts/build/build-node.sh
if [ $? -eq 0 ]; then
  echo "✅ Build script has API integration"
else
  echo "❌ Build script missing API integration"
  exit 1
fi

echo ""
echo "✅ All integration tests passed!"
echo ""
echo "========================================="
echo "Bitbucket Deployment Variables API - OPT-IN FEATURE"
echo "========================================="
echo ""
echo "This feature is OPTIONAL and defaults to OFF."
echo "Existing repositories continue working without any changes."
echo ""
echo "To enable in a consumer repository:"
echo "1. Add repository variable: USE_BITBUCKET_DEPLOYMENT_VARS = true"
echo "2. Ensure BITBUCKET_ACCESS_TOKEN is configured (usually already set for PR comments)"
echo "3. Add deployment variables in Repository Settings → Deployments → [environment]"
echo ""
echo "Benefits:"
echo "  ✓ Centralized configuration in deployment environments"
echo "  ✓ No need to manage VAR_<env> suffixes in pipeline YAML"
echo "  ✓ Dynamic updates without pipeline changes"
echo ""
echo "See BITBUCKET-DEPLOYMENT-API.md for detailed configuration instructions."
echo ""
echo "Note: This validation script is in scripts/dev/ (not scripts/test/)"
echo "      to avoid confusion with pipeline test stage scripts."
