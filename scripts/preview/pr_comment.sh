#!/bin/bash
set -euo pipefail

# Required: BITBUCKET_ACCESS_TOKEN, BITBUCKET_WORKSPACE, BITBUCKET_REPO_SLUG, PR_ID_FOR_USE, PREVIEW_URL
: "${BITBUCKET_ACCESS_TOKEN:?Missing BITBUCKET_ACCESS_TOKEN}"
: "${BITBUCKET_WORKSPACE:?Missing BITBUCKET_WORKSPACE}"
: "${BITBUCKET_REPO_SLUG:?Missing BITBUCKET_REPO_SLUG}"
: "${PR_ID_FOR_USE:?Missing PR_ID_FOR_USE}"
: "${PREVIEW_URL:?Missing PREVIEW_URL}"

# Configure git for bot operations (only if in a git repo)
if [ -d ".git" ]; then
  git config user.email "dkcwolta3hc6t4sp4db7ez9pbdhr37@bots.bitbucket.org" 2>/dev/null || true
fi

BODY=$(jq -n --arg text "Preview environment: ${PREVIEW_URL}" '{content:{raw:$text}}')

# Post comment and capture HTTP status to ensure reliable confirmation
HTTP_CODE=$(curl -sS -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer ${BITBUCKET_ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -X POST \
  -d "$BODY" \
  "https://api.bitbucket.org/2.0/repositories/${BITBUCKET_WORKSPACE}/${BITBUCKET_REPO_SLUG}/pullrequests/${PR_ID_FOR_USE}/comments")

if [ "$HTTP_CODE" = "201" ]; then
  echo "comment-posted:${PREVIEW_URL}"
else
  echo "comment-failed:${HTTP_CODE}" >&2
fi
