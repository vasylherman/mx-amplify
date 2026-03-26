#!/usr/bin/env bash
set -euxo pipefail

echo "Running post-build commands..."

ATLASSIAN_URL="${ATLASSIAN_URL:-}"

if [ -n "${AWS_PULL_REQUEST_ID:-}" ]; then
    PREVIEW_URL="https://pr-${AWS_PULL_REQUEST_ID}.${CUSTOM_DOMAIN}/${APP_BASE_PATH}"

    echo "Posting preview URL to GitLab MR #${AWS_PULL_REQUEST_ID}..."
    curl -fsS --location -X POST "https://gitlab.com/api/v4/projects/$PROJECT_ID/merge_requests/$AWS_PULL_REQUEST_ID/notes" \
        -H "PRIVATE-TOKEN: $PRIVATE_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"body\": \"${PREVIEW_URL}\"}"
else
    echo "Warning: AWS_PULL_REQUEST_ID is not set. Skipping GitLab MR comment."
fi

if [ -n "${AWS_PULL_REQUEST_SOURCE_BRANCH:-}" ]; then
    issue_key=$(echo "$AWS_PULL_REQUEST_SOURCE_BRANCH" | grep -oiE "${ISSUE_KEY_PATTERN:-}" || true)

    if [ -n "$issue_key" ]; then
        echo "Posting preview URL to Jira issue ${issue_key}..."
        curl -fsS --location -X POST "${ATLASSIAN_URL}/rest/api/2/issue/${issue_key}/comment" \
            -H "Authorization: Basic $BASE64_AUTH" \
            -H "Content-Type: application/json" \
            -d "{\"body\": \"${PREVIEW_URL}\"}"
    else
        echo "Warning: No issue key found in branch name '${AWS_PULL_REQUEST_SOURCE_BRANCH}' matching pattern '${ISSUE_KEY_PATTERN:-}'. Skipping Jira comment."
    fi
else
    echo "Warning: AWS_PULL_REQUEST_SOURCE_BRANCH is not set. Skipping Jira comment."
fi