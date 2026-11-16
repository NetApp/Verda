#!/usr/bin/env bash
# Create an OCCM service credential and print export statements for OCCM_ID, CLIENT_ID, CLIENT_SECRET.
# Usage:  eval "$(./create-occm-credential.sh <occm_name>)"
#         ./create-occm-credential.sh <occm_name> --dry-run   print the request, create nothing
#         ./create-occm-credential.sh -h | --help             show this help
# Requires: ACCOUNT_ID, AGENT_ID, ACCESS_TOKEN; CONSOLE_API defaults to
# https://cloudmanager.cloud.netapp.com. Aliases: BEARER_TOKEN, ORG_ID, API_HOST.
# Output: export statements for OCCM_ID, CLIENT_ID and CLIENT_SECRET on stdout,
# status messages on stderr. The client secret is shown only once.
set -euo pipefail
# shellcheck source=../../lib/bnr-common.sh
source "$(dirname "$0")/../../lib/bnr-common.sh"
bnr_env_aliases

OCCM_NAME=""; DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    --dry-run) DRY_RUN=true ;;
    -*)        echo "ERROR: unknown option $arg. Usage: $0 <occm_name> [--dry-run] (try --help)" >&2; exit 1 ;;
    *)         [ -z "$OCCM_NAME" ] || { echo "ERROR: only one occm_name is allowed" >&2; exit 1; }
               OCCM_NAME="$arg" ;;
  esac
done
[ -n "$OCCM_NAME" ] || { echo "Usage: $0 <occm_name> [--dry-run] (try --help)" >&2; exit 1; }
require_env CONSOLE_API ACCOUNT_ID AGENT_ID ACCESS_TOKEN

if $DRY_RUN; then
  # Nothing goes to stdout, so an accidental eval exports nothing.
  echo "Dry run. POST ${CONSOLE_API}/account/${ACCOUNT_ID}/providers/cloudmanager_occmauth/api/v0.1/services" >&2
  jq -n --arg name "${OCCM_NAME}" '{name: $name}' >&2
  echo "Dry run. No credential was created." >&2
  exit 0
fi

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
