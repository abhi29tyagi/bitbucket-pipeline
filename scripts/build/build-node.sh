#!/bin/bash
set -euo pipefail

echo "=== shared-pipelines build-node.sh: start (version: $(git rev-parse --short HEAD 2>/dev/null || echo local)) ==="

# Ensure we're in the workspace root (where consumer repo was cloned)
if [ -d "../.git" ] && [ ! -f "./package.json" ] && [ -f "../package.json" ]; then
  echo "Changing to workspace root..."
  cd ..
  echo "New directory: $(pwd)"
fi

PR_ID_FOR_USE="${BITBUCKET_PR_ID:-${PR_ID:-}}"
export PR_ID_FOR_USE=${PR_ID_FOR_USE}

[ -f .env ] && export $(grep -E '^(TAG_SLUG|PREVIEW_SLUG)=' .env | xargs) || true

# Only run for PRs targeting important branches OR direct branch runs
# Direct branch runs: dev/develop/release/*/main/hotfix/* → always run (no BITBUCKET_PR_ID)
# PR runs: Only if targeting develop/dev/main/release/* → run; otherwise skip
if [ -n "${BITBUCKET_PR_ID:-}" ] && [ "${BITBUCKET_BRANCH:-}" != "feature/test-ci" ] && { [ -z "$PR_ID_FOR_USE" ] || { [ -n "${BITBUCKET_PR_ID:-}" ] && [ "${BITBUCKET_PR_DESTINATION_BRANCH:-}" != "develop" ] && [ "${BITBUCKET_PR_DESTINATION_BRANCH:-}" != "dev" ] && [ "${BITBUCKET_PR_DESTINATION_BRANCH:-}" != "main" ] && [[ ! "${BITBUCKET_PR_DESTINATION_BRANCH:-}" =~ ^release/ ]]; }; }; then
  echo "Skipping: PR not targeting dev/develop/main/release/*"
  exit 0
fi

if [ "${SKIP_BUILD:-false}" = "true" ]; then
  echo "Skipping build because SKIP_BUILD=true"
  exit 0
fi

if [ -d "shared-pipelines" ]; then
  echo "shared-pipelines directory already exists"
else
  echo "shared-pipelines directory does not exist, cloning..."
  git clone git@bitbucket.org:protocol33/shared-pipelines.git
fi
# Prepare Docker CLI environment to target the local daemon via a Unix socket.
export DOCKER_HOST="unix:///var/run/docker.sock"

# Docker login with error checking
echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin || {
  echo "ERROR: Docker login failed"
  exit 1
}

# Optionally generate package-lock.json if missing (opt-in)
if [ "${GENERATE_LOCK_IN_PIPELINE:-false}" = "true" ] && [ ! -f "package-lock.json" ] && [ -f "package.json" ]; then
  echo "package-lock.json not found, generating it..."
  USER_ID=$(id -u)
  GROUP_ID=$(id -g)
  NODE_VERSION="${NODE_VERSION:-20}"
  docker run --rm --user "${USER_ID}:${GROUP_ID}" \
    -v "$(pwd)":/app -w /app \
    -e HOME=/tmp \
    node:${NODE_VERSION} bash -c '
    export npm_config_cache=/tmp/.npm
    npm install --package-lock-only --cache /tmp/.npm
  ' || {
    echo "ERROR: Failed to generate package-lock.json"
    exit 1
  }
  echo "package-lock.json generated successfully"
fi

# Verify package-lock.json exists before building (unless Dockerfile handles install)
if [ ! -f "package-lock.json" ] && [ -z "${DOCKERFILE_HANDLES_INSTALL:-}" ]; then
  echo "WARNING: package-lock.json not found. It's recommended to commit a lockfile or set DOCKERFILE_HANDLES_INSTALL=true if your Dockerfile runs install."
fi

# Determine target environment for build args
# For hotfix branches, use prod build args (hotfixes are for production)
TARGET_ENV="${TARGET_ENV:-${ENVIRONMENT:-preview}}"
if [[ "$BITBUCKET_BRANCH" =~ ^hotfix/ ]]; then
  TARGET_ENV="prod"
  echo "Hotfix branch detected: using prod build args"
fi

# Get build arguments - Check if Bitbucket Deployment Variables is enabled (opt-in feature)
# Support both USE_DEPLOYMENT_VARS (new) and USE_BITBUCKET_DEPLOYMENT_VARS (backward compatibility)
USE_DEPLOYMENT_VARS="${USE_DEPLOYMENT_VARS:-${USE_BITBUCKET_DEPLOYMENT_VARS:-false}}"
BUILD_ARGS=()  # always treat build args as an array to preserve spaces in values

if [ "${USE_DEPLOYMENT_VARS}" = "true" ]; then
  echo "Bitbucket Deployment Variables enabled, attempting to fetch deployment variables..."
  
  # Source API utilities
  if [ -f "shared-pipelines/scripts/utils/bitbucket-api.sh" ]; then
    source "shared-pipelines/scripts/utils/bitbucket-api.sh"
    # get_build_args_with_api outputs KEY=VALUE lines; convert to --build-arg entries
    if BUILD_ARG_LINES=$(get_build_args_with_api "$TARGET_ENV"); then
      while IFS= read -r kv; do
        [ -z "$kv" ] && continue
        BUILD_ARGS+=("--build-arg" "$kv")
      done <<< "$BUILD_ARG_LINES"
    fi
  else
    echo "WARNING: USE_DEPLOYMENT_VARS=true but API utilities not found, falling back to environment variables"
    USE_DEPLOYMENT_VARS="false"
  fi
fi

# Fallback method (default): Normalize and pass VAR_<TARGET_ENV> as build args e.g. VAR_preview -> VAR
# Supports both lowercase (VAR_dev) and uppercase (VAR_DEV) suffixes
if [ "${USE_DEPLOYMENT_VARS}" != "true" ]; then
  echo "Using environment variable method for build args"
  TARGET_ENV_LOWER="${TARGET_ENV,,}"  # lowercase
  TARGET_ENV_UPPER="${TARGET_ENV^^}"  # uppercase

  while IFS='=' read -r __n __v; do
    case "$__n" in
      *_"$TARGET_ENV_LOWER"|*_"$TARGET_ENV_UPPER")
        __base="${__n%_*}"
        export "$__base=$__v"
        [ -n "$__v" ] && BUILD_ARGS+=("--build-arg" "$__base=$__v")
      ;;
    esac
  done < <(env)
fi

# Also support peer service URL generation in build (like deploy)
# Format: PEER_HOST_URLS="FRONTEND_URL.zenit-claim-app,BACKEND_URL.zenit-claim-api"
# You can append an extra key after the app slug (e.g. `BACKEND_URL.zenit-claim-api.admin`)
# to generate `https://admin-preview-<key>-zenit-claim-api.internal...`.
if [ "$TARGET_ENV" = "preview" ] && [ -n "${PEER_HOST_URLS:-}" ]; then
  # Derive PREVIEW_KEY similarly to deploy logic
  PREVIEW_KEY_DERIVED="${PREVIEW_SLUG#preview-}"
  PREVIEW_KEY_DERIVED="${PREVIEW_KEY_DERIVED%-${BITBUCKET_REPO_SLUG}}"
  PREVIEW_KEY_USE="${PREVIEW_KEY:-$PREVIEW_KEY_DERIVED}"
  IFS=',' read -r -a __pairs <<< "${PEER_HOST_URLS}"
  for __pair in "${__pairs[@]}"; do
    __pair="$(echo "${__pair}" | xargs)"; [ -z "${__pair}" ] && continue
    __var_name="${__pair%%.*}"
    __slug_and_key="${__pair#*.}"
    # For VAR.app.extra format, extract extra key and prepend to host
    # Examples:
    #   MINIO_EXTERNAL_ENDPOINT.homnifi-machine-service.minio → minio-preview-<key>-homnifi-machine-service.internal...
    __app_slug="${__slug_and_key}"
    __extra_key=""
    if [[ "${__slug_and_key}" == *.* ]]; then
      __extra_key="${__slug_and_key##*.}"
      __app_slug="${__slug_and_key%.*}"
    fi
    __host="preview-${PREVIEW_KEY_USE}-${__app_slug}.internal.${PREVIEW_DOMAIN_NAME}"
    if [ -n "${__extra_key}" ] && [ "${__extra_key}" != "${__slug_and_key}" ]; then
      __host="${__extra_key}-${__host}"
    fi
    __url="https://${__host}"
    export "${__var_name}=${__url}"
    BUILD_ARGS="$BUILD_ARGS --build-arg ${__var_name}=${__url}"
  done
fi
if ((${#BUILD_ARGS[@]} > 0)); then
  # Log build args safely without affecting how they're passed to docker
  printf -v BUILD_ARGS_LOG '%q ' "${BUILD_ARGS[@]}"
  echo "Build args (static): $BUILD_ARGS_LOG"
  echo "Build args length: ${#BUILD_ARGS_LOG} characters"
  # Each build arg is stored as pair: --build-arg, KEY=VALUE
  echo "Number of build args: $((${#BUILD_ARGS[@]} / 2))"
fi

# Run pre-build command if provided (e.g., for monorepo shared directories)
# NOTE: Docker's build context does NOT follow symlinks outside the build context.
# Use 'cp -r' to copy directories instead of 'ln -s' for symlinks.
# Example: cp -r /path/to/shared ./shared && rm -rf ./shared/node_modules ./shared/.git
if [ -n "${PRE_BUILD_COMMAND:-}" ]; then
  echo "=== Pre-build command debug ==="
  echo "Running pre-build command: $PRE_BUILD_COMMAND"
  eval "$PRE_BUILD_COMMAND" || {
    echo "ERROR: Pre-build command failed"
    exit 1
  }
  echo "current directory: $(pwd)"
  echo "directory contents:"
  ls -la
  echo "================================="
fi

echo "Building Docker image..."
# Classic docker build (avoid buildx CLI quirks with long arg lists)
# Prefer classic docker build (avoid buildx CLI quirks with long arg lists)
unset DOCKER_BUILDKIT || true

# Build docker command safely without eval to avoid issues with special characters (&, ?, # etc.)
# Use 'docker image build' to bypass any buildx aliasing of 'docker build'
BUILD_CMD=(docker image build)
if ((${#BUILD_ARGS[@]} > 0)); then
  BUILD_CMD+=("${BUILD_ARGS[@]}")
fi
BUILD_CMD+=(-t "$DOCKERHUB_ORGNAME/$BITBUCKET_REPO_SLUG:$BITBUCKET_COMMIT" ".")
"${BUILD_CMD[@]}" || {
  echo "ERROR: Docker build failed"
  exit 1
}

# Tag images as needed
TAGS_TO_PUSH=()

# Tag and push dev image only for develop/dev branch
if [ "$BITBUCKET_BRANCH" = "develop" ] || [ "$BITBUCKET_BRANCH" = "dev" ]; then
  # Use DEV_TAG from setup-env if available, otherwise calculate
  if [ -z "${DEV_TAG:-}" ]; then
    SHORT_COMMIT="${BITBUCKET_COMMIT:0:8}"
    DEV_TAG="$DOCKERHUB_ORGNAME/$BITBUCKET_REPO_SLUG:dev-$SHORT_COMMIT"
    echo "Calculated DEV_TAG: $DEV_TAG"
  else
    echo "Using DEV_TAG from setup-env: $DEV_TAG"
  fi
  docker tag "$DOCKERHUB_ORGNAME/$BITBUCKET_REPO_SLUG:$BITBUCKET_COMMIT" "$DEV_TAG"
  export DEV_TAG
  TAGS_TO_PUSH+=("$DEV_TAG")
  echo "Tagged dev image: $DEV_TAG"
else
  echo "Skipping dev tag push (not on develop/dev branch)"
fi

# Tag and push UAT image for release/* branches
if [[ "$BITBUCKET_BRANCH" =~ ^release/ ]]; then
  # Use UAT_TAG from setup-env if available, otherwise calculate
  if [ -z "${UAT_TAG:-}" ]; then
    RELEASE_TAG="release-$(echo $BITBUCKET_BRANCH | sed 's/release\///')"
    UAT_TAG="$DOCKERHUB_ORGNAME/$BITBUCKET_REPO_SLUG:$RELEASE_TAG"
    echo "Calculated UAT_TAG: $UAT_TAG"
  else
    echo "Using UAT_TAG from setup-env: $UAT_TAG"
  fi
  docker tag "$DOCKERHUB_ORGNAME/$BITBUCKET_REPO_SLUG:$BITBUCKET_COMMIT" "$UAT_TAG"
  export UAT_TAG
  TAGS_TO_PUSH+=("$UAT_TAG")
  echo "Tagged UAT image: $UAT_TAG"
fi

# Tag and push prod image for main branch
if [ "$BITBUCKET_BRANCH" = "main" ]; then
  # Use PROD_TAG from setup-env if available, otherwise calculate
  if [ -z "${PROD_TAG:-}" ]; then
    VERSION="${VERSION:-}"
    if [ -z "$VERSION" ] && [ -n "$BITBUCKET_TAG" ]; then
      VERSION="$(echo "$BITBUCKET_TAG" | sed -E 's/^(v|release-)//')"
    fi
    if [ -z "$VERSION" ]; then
      echo "WARNING: VERSION not provided for main branch, using commit hash"
      VERSION="prod-$BITBUCKET_COMMIT"
    fi
    PROD_TAG="$DOCKERHUB_ORGNAME/$BITBUCKET_REPO_SLUG:$VERSION"
    echo "Calculated PROD_TAG: $PROD_TAG"
  else
    echo "Using PROD_TAG from setup-env: $PROD_TAG"
  fi
  docker tag "$DOCKERHUB_ORGNAME/$BITBUCKET_REPO_SLUG:$BITBUCKET_COMMIT" "$PROD_TAG"
  export PROD_TAG
  TAGS_TO_PUSH+=("$PROD_TAG")
  echo "Tagged prod image: $PROD_TAG"
fi

# Tag and push hotfix image for hotfix/* branches
if [[ "$BITBUCKET_BRANCH" =~ ^hotfix/ ]]; then
  # Use HOTFIX_TAG from setup-env if available, otherwise calculate
  if [ -z "${HOTFIX_TAG:-}" ]; then
    HOTFIX_VERSION="hotfix-$(echo $BITBUCKET_BRANCH | sed 's/hotfix\///')"
    HOTFIX_TAG="$DOCKERHUB_ORGNAME/$BITBUCKET_REPO_SLUG:$HOTFIX_VERSION"
    echo "Calculated HOTFIX_TAG: $HOTFIX_TAG"
  else
    echo "Using HOTFIX_TAG from setup-env: $HOTFIX_TAG"
  fi
  docker tag "$DOCKERHUB_ORGNAME/$BITBUCKET_REPO_SLUG:$BITBUCKET_COMMIT" "$HOTFIX_TAG"
  export HOTFIX_TAG
  TAGS_TO_PUSH+=("$HOTFIX_TAG")
  echo "Tagged hotfix image: $HOTFIX_TAG"
fi

# Tag and push feature/branch or PR image via TAG_SLUG (only for non-main/release/hotfix branches)
if [ -n "$TAG_SLUG" ] && [ "${BITBUCKET_BRANCH:-}" != "develop" ] && [ "${BITBUCKET_BRANCH:-}" != "dev" ] && [ "${BITBUCKET_BRANCH:-}" != "main" ] && [[ ! "$BITBUCKET_BRANCH" =~ ^release/ ]] && [[ ! "$BITBUCKET_BRANCH" =~ ^hotfix/ ]]; then
  BR_TAG="$DOCKERHUB_ORGNAME/$BITBUCKET_REPO_SLUG:$TAG_SLUG"
  docker tag "$DOCKERHUB_ORGNAME/$BITBUCKET_REPO_SLUG:$BITBUCKET_COMMIT" "$BR_TAG"
  TAGS_TO_PUSH+=("$BR_TAG")
  echo "Tagged branch/PR image: $BR_TAG"
fi

# Push all tags with error checking
for TAG in "${TAGS_TO_PUSH[@]}"; do
  echo "Pushing image: $TAG"
  if docker push "$TAG"; then
    echo "✅ Successfully pushed $TAG"
  else
    echo "ERROR: Failed to push $TAG"
    exit 1
fi
done

# Cleanup
docker rmi "$DOCKERHUB_ORGNAME/$BITBUCKET_REPO_SLUG:$BITBUCKET_COMMIT" 2>/dev/null || true
echo "Cleanup done"