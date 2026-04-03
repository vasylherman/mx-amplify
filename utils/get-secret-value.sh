#!/usr/bin/env bash
set -euo pipefail

# Extracts a single key value from an AWS Secrets Manager JSON secret.
#
# Requires:
#   - SECRET_ARN env var (set by AWS Amplify)
#   - aws cli, jq
#
# Usage:
#   ./get-secret-value.sh <KEY_NAME>
#
#   # or via curl:
#   export GL_TOKEN=$(curl -fsSL -H "Authorization: Bearer $TOKEN" \
#     https://raw.githubusercontent.com/vasylherman/mx-amplify/main/common/get-secret-value.sh \
#     | bash -s GL_TOKEN)

KEY_NAME="${1:?Usage: get-secret-value.sh <KEY_NAME>}"

VALUE=$(
  aws secretsmanager get-secret-value \
    --secret-id "$SECRET_ARN" \
    --region "${AWS_REGION:-us-east-1}" \
    --query 'SecretString' \
    --output text | jq -re --arg key "$KEY_NAME" '.[$key]'
) || { echo "ERROR: Key '$KEY_NAME' not found in secret" >&2; exit 1; }

echo "$VALUE"
