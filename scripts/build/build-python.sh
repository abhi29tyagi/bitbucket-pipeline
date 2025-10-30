#!/bin/bash
set -euo pipefail

# Ensure we're in the workspace root (where consumer repo was cloned)
if [ -d "../.git" ] && [ ! -f "./requirements.txt" ] && [ ! -f "./pyproject.toml" ] && [ -f "../requirements.txt" -o -f "../pyproject.toml" ]; then
  echo "Changing to workspace root..."
  cd ..
fi

PR_ID_FOR_USE="${BITBUCKET_PR_ID:-${PR_ID:-}}"
export PR_ID_FOR_USE=${PR_ID_FOR_USE}

[ -f .env ] && export $(grep -E '^(TAG_SLUG|PREVIEW_SLUG)=' .env | xargs) || true

# Only run for PRs targeting important branches OR direct branch runs
# Direct branch runs: dev/develop/release/*/main/hotfix/* → always run (no BITBUCKET_PR_ID)
# PR runs: Only if targeting develop/dev/main/release/* → run; otherwise skip (hotfix has no PRs)
if [ -n "${BITBUCKET_PR_ID:-}" ] && [ "${BITBUCKET_BRANCH:-}" != "feature/test-ci" ] && [ "${FORCE_BUILD}" != "true" ] && { [ -z "$PR_ID_FOR_USE" ] || { [ -n "${BITBUCKET_PR_ID:-}" ] && [ "${BITBUCKET_PR_DESTINATION_BRANCH:-}" != "develop" ] && [ "${BITBUCKET_PR_DESTINATION_BRANCH:-}" != "dev" ] && [ "${BITBUCKET_PR_DESTINATION_BRANCH:-}" != "main" ] && [[ ! "${BITBUCKET_PR_DESTINATION_BRANCH:-}" =~ ^release/ ]]; }; }; then
  echo "Skipping: PR not targeting dev/develop/main/release/*"
  exit 0
fi

if [ "${SKIP_BUILD:-false}" = "true" ]; then
  echo "Skipping build because SKIP_BUILD=true"
  exit 0
fi

export DOCKER_HOST="unix:///var/run/docker.sock"

echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin || {
  echo "ERROR: Docker login failed"
  exit 1
}

APP_PATH_DIR="${APP_PATH:-.}"
DOCKERFILE_PATH="${DOCKERFILE_PATH:-$APP_PATH_DIR/Dockerfile}"
BUILD_CONTEXT="${BUILD_CONTEXT:-$APP_PATH_DIR}"

[ -f "$DOCKERFILE_PATH" ] || { echo "ERROR: Dockerfile not found at $DOCKERFILE_PATH"; exit 1; }

echo "Building Docker image from $DOCKERFILE_PATH with context $BUILD_CONTEXT..."
docker build -f "$DOCKERFILE_PATH" "$BUILD_CONTEXT" \
  -t "$DOCKERHUB_ORGNAME/$BITBUCKET_REPO_SLUG:$BITBUCKET_COMMIT" || {
  echo "ERROR: Docker build failed"
  exit 1
}

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
  TAGS_TO_PUSH+=("$DEV_TAG")
  echo "Tagged dev image: $DEV_TAG"
else
  echo "Skipping dev tag push (not on develop/dev branch)"
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

# Tag and push feature/branch or PR image via TAG_SLUG (only for non-main/hotfix branches)
if [ -n "$TAG_SLUG" ] && [ "${BITBUCKET_BRANCH:-}" != "develop" ] && [ "${BITBUCKET_BRANCH:-}" != "dev" ] && [[ ! "$BITBUCKET_BRANCH" =~ ^hotfix/ ]]; then
  BR_TAG="$DOCKERHUB_ORGNAME/$BITBUCKET_REPO_SLUG:$TAG_SLUG"
  docker tag "$DOCKERHUB_ORGNAME/$BITBUCKET_REPO_SLUG:$BITBUCKET_COMMIT" "$BR_TAG"
  TAGS_TO_PUSH+=("$BR_TAG")
  echo "Tagged branch/PR image: $BR_TAG"
fi

for TAG in "${TAGS_TO_PUSH[@]}"; do
  echo "Pushing image: $TAG"
  if docker push "$TAG"; then
    echo "✅ Successfully pushed $TAG"
  else
    echo "ERROR: Failed to push $TAG"
    exit 1
  fi
done

# Optionally clean up local image
docker rmi "$DOCKERHUB_ORGNAME/$BITBUCKET_REPO_SLUG:$BITBUCKET_COMMIT" 2>/dev/null || true