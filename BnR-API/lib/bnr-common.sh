#!/usr/bin/env bash
# Shared helpers for the BnR-API examples. Source this file:  source ../../lib/bnr-common.sh
# Requires: curl, jq

# Abort with a message if any of the named variables is unset or empty.
require_env() {
  local missing=0 v
  for v in "$@"; do
    if [ -z "${!v:-}" ]; then
      echo "ERROR: environment variable ${v} is not set" >&2
      missing=1
    fi
  done
  [ "${missing}" -eq 0 ] || exit 1
}

# Exchange REFRESH_TOKEN for an access token and print it.
# Requires REFRESH_TOKEN (see 00-authentication/). The Auth0 client ID is the same for all customers.
get_access_token() {
  require_env REFRESH_TOKEN
  curl -s -X POST "https://netapp-cloud-account.auth0.com/oauth/token" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg rt "${REFRESH_TOKEN}" --arg cid "Mu0V1ywgYteI6w1MbD15fKfVIUrNXGWC" \
          '{grant_type: "refresh_token", refresh_token: $rt, client_id: $cid}')" \
    | jq -r .access_token
}

# GET a Console API path with the standard headers. Usage: api_get "/path"
api_get() {
  require_env CONSOLE_API ACCESS_TOKEN AGENT_ID
  curl -sS --fail-with-body "${CONSOLE_API}$1" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "x-agent-id: ${AGENT_ID}" \
    -H "Accept: application/json"
}
