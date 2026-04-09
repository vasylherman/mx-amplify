#!/usr/bin/env bash
set -euo pipefail

echo "Running pre-build commands..."

NVM_NODE_VERSION="${NVM_NODE_VERSION:-v22}"

nvm install "$NVM_NODE_VERSION"
nvm use "$NVM_NODE_VERSION"
envsubst < .npmrc-example > "$HOME/.npmrc"