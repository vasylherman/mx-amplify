#!/usr/bin/env bash
set -euo pipefail

echo "Running pre-build commands..."

NVM_NODE_VERSION="${NVM_NODE_VERSION:-v22}"

nvm install "$NVM_NODE_VERSION"
nvm use "$NVM_NODE_VERSION"

# Configure npm to pull private @maxi-ui packages from AWS CodeArtifact using a short-lived
# token minted via the Amplify build role.
echo "Configuring npm for CodeArtifact (@maxi-ui)..."
CA_DOMAIN=underdefense
CA_OWNER=855501706185
CA_REGION=eu-west-1
CA_REPO=maxi
CA_HOST="${CA_DOMAIN}-${CA_OWNER}.d.codeartifact.${CA_REGION}.amazonaws.com"
CODEARTIFACT_AUTH_TOKEN=$(aws codeartifact get-authorization-token \
  --domain "$CA_DOMAIN" --domain-owner "$CA_OWNER" --region "$CA_REGION" \
  --query authorizationToken --output text)
{
  printf '@maxi-ui:registry=https://%s/npm/%s/\n' "$CA_HOST" "$CA_REPO"
  printf '//%s/npm/%s/:_authToken=%s\n' "$CA_HOST" "$CA_REPO" "$CODEARTIFACT_AUTH_TOKEN"
} > "$HOME/.npmrc"