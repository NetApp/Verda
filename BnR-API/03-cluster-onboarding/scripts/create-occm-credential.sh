#!/usr/bin/env bash
# Create an OCCM service credential and print export statements for OCCM_ID, CLIENT_ID, CLIENT_SECRET.
# Usage:  eval "$(./create-occm-credential.sh <occm_name>)"
# Requires: CONSOLE_API, ACCOUNT_ID, AGENT_ID, ACCESS_TOKEN
set -euo pipefail
# shellcheck source=../../lib/bnr-common.sh
source "$(dirname "$0")/../../lib/bnr-common.sh"
require_env CONSOLE_API ACCOUNT_ID AGENT_ID ACCESS_TOKEN

OCCM_NAME="${1:?Usage: $0 <occm_name>}"

RESPONSE=$(curl --no-progress-meter --fail-with-body -X POST \
  "${CONSOLE_API}/account/${ACCOUNT_ID}/providers/cloudmanager_occmauth/api/v0.1/services" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "X-Account-Id: ${ACCOUNT_ID}" \
  -H "x-agent-id: ${AGENT_ID}" \
  -d "$(jq -n --arg name "${OCCM_NAME}" '{name: $name}')") || {
  echo "Request failed: ${RESPONSE:-no response}" >&2
  exit 1
}

# Export statements go to stdout (for eval); status goes to stderr so the secret is not echoed.
jq -r '"export OCCM_ID=\(.id|@sh)\nexport CLIENT_ID=\(.clientId|@sh)\nexport CLIENT_SECRET=\(.clientSecret|@sh)"' <<<"${RESPONSE}"
echo "OCCM credential '${OCCM_NAME}' created. Store CLIENT_SECRET securely; it cannot be retrieved again." >&2
