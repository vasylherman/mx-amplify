#!/usr/bin/env bash
set -euo pipefail

echo "Running post-build commands..."

if [ -n "${AWS_PULL_REQUEST_ID:-}" ]; then
    PREVIEW_URL="https://pr-${AWS_PULL_REQUEST_ID}.${CUSTOM_DOMAIN}/${APP_BASE_PATH:-}"

    echo "Posting custom-domain preview URL to GitHub PR #${AWS_PULL_REQUEST_ID}..."

    # Resolve owner/repo from Amplify's default AWS_CLONE_URL (e.g. git@github.com:owner/repo.git).
    # GITHUB_REPOSITORY overrides it if set; the git remote is a last-resort fallback.
    repo_url="${AWS_CLONE_URL:-}"
    [ -z "$repo_url" ] && repo_url=$(git config --get remote.origin.url || true)
    github_repo="${GITHUB_REPOSITORY:-$(printf '%s' "$repo_url" | sed -E 's#^.*github\.com[:/]+##; s#\.git$##')}"
    if [ -z "$github_repo" ]; then
        echo "Failed to resolve GitHub owner/repo from AWS_CLONE_URL/git remote."; exit 1
    fi

    # --- Authenticate as the RoboDefenseAI GitHub App ---
    GITHUB_APP_ID=4254870

    key_file=$(mktemp)
    trap 'rm -f "$key_file"' EXIT
    printf '%b' "$ORG_ROBODEFENSEAI_PRIVATE_KEY" > "$key_file"

    b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
    now=$(date +%s)
    jwt_header=$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | b64url)
    jwt_payload=$(printf '{"iat":%d,"exp":%d,"iss":%s}' "$((now - 60))" "$((now + 540))" "$GITHUB_APP_ID" | b64url)
    jwt_signature=$(printf '%s' "${jwt_header}.${jwt_payload}" | openssl dgst -sha256 -sign "$key_file" -binary | b64url)
    JWT="${jwt_header}.${jwt_payload}.${jwt_signature}"

    # Resolve the App installation for this repo, then mint a short-lived installation token.
    install_resp=$(curl -fsS -H "Authorization: Bearer $JWT" -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/${github_repo}/installation")
    if [[ "$install_resp" =~ \"id\":[[:space:]]*([0-9]+) ]]; then
        installation_id="${BASH_REMATCH[1]}"
    else
        echo "Failed to resolve GitHub App installation:"; echo "$install_resp"; exit 1
    fi

    token_resp=$(curl -fsS -X POST -H "Authorization: Bearer $JWT" -H "Accept: application/vnd.github+json" \
        "https://api.github.com/app/installations/${installation_id}/access_tokens")
    if [[ "$token_resp" =~ \"token\":[[:space:]]*\"([^\"]+)\" ]]; then
        installation_token="${BASH_REMATCH[1]}"
    else
        echo "Failed to mint installation access token:"; echo "$token_resp"; exit 1
    fi

    # Post the custom-domain preview URL as a PR comment (distinct from Amplify's default amplifyapp.com comment).
    curl -fsS -X POST "https://api.github.com/repos/${github_repo}/issues/${AWS_PULL_REQUEST_ID}/comments" \
        -H "Authorization: Bearer $installation_token" \
        -H "Accept: application/vnd.github+json" \
        -H "Content-Type: application/json" \
        -d "{\"body\": \"✅ Preview (custom domain): ${PREVIEW_URL}\"}"

    rm -f "$key_file"; trap - EXIT
else
    echo "Warning: AWS_PULL_REQUEST_ID is not set. Skipping GitHub PR comment."
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

if [[ "${AWS_BRANCH:-}" == prototype-* ]]; then
    PREVIEW_URL="https://${AWS_BRANCH}.${CUSTOM_DOMAIN}/${APP_BASE_PATH:-}"
    issue_key=$(echo "$AWS_BRANCH" | grep -oiE "${ISSUE_KEY_PATTERN:-}" || true)

    if [ -n "$issue_key" ]; then
        echo "Posting preview URL to Jira issue ${issue_key} for prototype branch ${AWS_BRANCH}..."
        curl -fsS --location -X POST "${ATLASSIAN_URL}/rest/api/2/issue/${issue_key}/comment" \
            -H "Authorization: Basic $BASE64_AUTH" \
            -H "Content-Type: application/json" \
            -d "{\"body\": \"${PREVIEW_URL}\"}"
    else
        echo "Warning: No issue key found in branch name '${AWS_BRANCH}' matching pattern '${ISSUE_KEY_PATTERN:-}'. Skipping Jira comment."
    fi
else
    echo "Warning: AWS_BRANCH is not a prototype branch. Skipping prototype Jira comment."
fi
