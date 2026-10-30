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

# Poll the Backup and Recovery object-storage list until a bucket name appears.
# Usage: wait_for_object_store "<query>" "<bucket name>" [timeout seconds]
#   query example: "provider=ONTAP_S3&credential-id=<id>" or "provider=AWS"
# Requires ACCOUNT_ID plus what api_get needs. Returns 0 when the bucket is
# listed, 1 on timeout. No job-status call is documented, so "listed" is the
# signal. BNR_POLL_INTERVAL (seconds, default 5) sets the polling interval.
wait_for_object_store() {
  local query=$1 name=$2 timeout=${3:-120} deadline found
  deadline=$((SECONDS + timeout))
  while true; do
    if found=$(api_get "/backup-recovery/organizations/${ACCOUNT_ID}/v1/object-storage?${query}" 2>/dev/null \
        | jq -r --arg n "$name" '
            (if type == "array" then . else (.items // []) end)
            | map(select(.object_store_name == $n)) | .[0].object_store_name // empty' 2>/dev/null) \
        && [ -n "$found" ]; then
      return 0
    fi
    [ "$SECONDS" -ge "$deadline" ] && return 1
    sleep "${BNR_POLL_INTERVAL:-5}"
  done
}

# GET a Console API path with the standard headers. Usage: api_get "/path"
# x-account-id is sent when ACCOUNT_ID is set, as the Console UI does.
api_get() {
  require_env CONSOLE_API ACCESS_TOKEN AGENT_ID
  local args=(-sS --fail-with-body "${CONSOLE_API}$1"
    -H "Authorization: Bearer ${ACCESS_TOKEN}"
    -H "x-agent-id: ${AGENT_ID}"
    -H "Accept: application/json")
  [ -z "${ACCOUNT_ID:-}" ] || args+=(-H "x-account-id: ${ACCOUNT_ID}")
  curl "${args[@]}"
}
