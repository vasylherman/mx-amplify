#!/usr/bin/env bash
set -euxo pipefail

echo "Running build commands..."

eval "$BUILD_PROJECT_CMD"

echo "window.appSettings = {'semver': 'amplify.${AWS_BRANCH}'};" > "./$BUILD_DIR/assets/settings.js"
echo "{\"amplify\":\"true\",\"commit\":\"${AWS_COMMIT_ID}\",\"semver\":\"${AWS_BRANCH}\"}" > "./$BUILD_DIR/assets/settings.json"

mkdir -p "./asset-output/${APP_BASE_PATH:-}"
cp -R "./$BUILD_DIR/index.html" ./asset-output/
cp -R "./$BUILD_DIR/." "./asset-output/${APP_BASE_PATH:-}"