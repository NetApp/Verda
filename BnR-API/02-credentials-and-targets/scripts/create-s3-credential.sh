#!/usr/bin/env bash
################################################################################
# NetApp Console API - Add an object-storage credential for Backup and Recovery
# (ONTAP S3, StorageGRID or S3-compatible)
#
# POST /backup-recovery/organizations/${ACCOUNT_ID}/v1/credentials
#
# Requires: curl, jq. Variables follow 00-authentication/env.sh.example.
# ONTAP_S3 and S3_COMPATIBLE are tested (2026-10-28). SGWS is not yet tested.
# The call returns a job ID.
################################################################################
set -euo pipefail
# shellcheck source=../../lib/bnr-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/bnr-common.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Connection settings. No defaults for IDs: set them via env.sh or flags.
ACCESS_TOKEN="${ACCESS_TOKEN:-${BEARER_TOKEN:-}}"
CONSOLE_API="${CONSOLE_API:-${API_HOST:-https://cloudmanager.cloud.netapp.com}}"
ORG_ID="${ORG_ID:-}"
ACCOUNT_ID="${ACCOUNT_ID:-}"
AGENT_ID="${AGENT_ID:-}"
WORKSPACE_ID="${WORKSPACE_ID:-${TENANT_ID:-${PROJECT_ID:-}}}"

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Add an object-storage credential to Backup and Recovery. The credential holds
the endpoint, port and keys that the bucket scripts in 06-create-backup-target
refer to by name.

Required:
  --provider NAME             ONTAP_S3, SGWS (StorageGRID) or S3_COMPATIBLE
  --name NAME                 Credential name
  --server FQDN               Storage server / gateway node / S3 endpoint FQDN
  --access-key KEY            Access key (prefer the ACCESSKEY variable)
  --secret-key KEY            Secret key (prefer the SECRETKEY variable:
                              command-line arguments are visible in 'ps')

Optional:
  --port PORT                 Port the server listens on (default: ONTAP_S3 80,
                              SGWS 443, S3_COMPATIBLE 443)
  --account-id ID             Account (organization) ID
  --org-id ID                 Alias for --account-id
  --agent-id ID               Console agent ID
  --workspace-id ID           Console workspace/project ID, sent as
                              x-netapp-workspace-id (optional)
  --api-host URL              API host (default: CONSOLE_API, else
                              https://cloudmanager.cloud.netapp.com)
  --wait                      After the request is accepted, poll the credential
                              list until the new credential appears. Exit 0 when
                              it is listed, 1 on timeout.
  --timeout SECONDS           Maximum time for --wait (default: 120)
  --dry-run                   Print the request body (keys redacted) and exit

Lookup (print and exit, nothing is created):
  --list                      List the credentials of --provider

  -h, --help                  Show this help text

Environment (used when the matching flag is omitted):
  ACCESS_TOKEN    (required) Console access token (alias: BEARER_TOKEN)
  ACCOUNT_ID      (required) Account / organization ID (alias: ORG_ID)
  AGENT_ID        (required) Console agent ID
  CONSOLE_API     API host (alias: API_HOST)
  WORKSPACE_ID    Console workspace/project ID (aliases: TENANT_ID, PROJECT_ID)
  STORAGE_SERVER  Same as --server
  STORAGE_PORT    Same as --port
  ACCESSKEY       Same as --access-key
  SECRETKEY       Same as --secret-key

Example:
  source ../../00-authentication/env.sh   # then refresh ACCESS_TOKEN
  export ACCESSKEY='<access_key>'
  export SECRETKEY='<secret_key>'

  $0 --provider S3_COMPATIBLE --name <credential_name> \\
     --server <s3_endpoint_fqdn> --port 443 --wait
EOF
    exit 1
}

print_message() {
    echo -e "${1}${2}${NC}"
}

PROVIDER=""
NAME=""
SERVER="${STORAGE_SERVER:-}"
PORT="${STORAGE_PORT:-}"
# The keys are passed to jq and curl through the environment and stdin, not
# through arguments, so they do not show up in 'ps'.
ACCESSKEY="${ACCESSKEY:-}"
SECRETKEY="${SECRETKEY:-}"
LIST="false"
WAIT="false"
TIMEOUT="120"
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        --provider)    PROVIDER="${2:?missing value for $1}"; shift 2 ;;
        --name)        NAME="${2:?missing value for $1}"; shift 2 ;;
        --server)      SERVER="${2:?missing value for $1}"; shift 2 ;;
        --port)        PORT="${2:?missing value for $1}"; shift 2 ;;
        --access-key)  ACCESSKEY="${2:?missing value for $1}"; shift 2 ;;
        --secret-key)  SECRETKEY="${2:?missing value for $1}"; shift 2 ;;
        --list)        LIST="true"; shift ;;
        --wait)        WAIT="true"; shift ;;
        --timeout)     TIMEOUT="${2:?missing value for $1}"; shift 2 ;;
        --account-id|--org-id) ACCOUNT_ID="${2:?missing value for $1}"; shift 2 ;;
        --agent-id)    AGENT_ID="${2:?missing value for $1}"; shift 2 ;;
        --workspace-id) WORKSPACE_ID="${2:?missing value for $1}"; shift 2 ;;
        --api-host)    CONSOLE_API="${2:?missing value for $1}"; shift 2 ;;
        --dry-run)     DRY_RUN="true"; shift ;;
        -h|--help)     usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

[ -z "$ACCOUNT_ID" ] && ACCOUNT_ID="$ORG_ID"
CONSOLE_API="${CONSOLE_API%/}"

for command in jq curl; do
    if ! command -v "$command" >/dev/null 2>&1; then
        print_message "$RED" "Error: $command is required."
        exit 1
    fi
done

case "$PROVIDER" in
    ONTAP_S3)      DEFAULT_PORT=80 ;;
    SGWS|S3_COMPATIBLE) DEFAULT_PORT=443 ;;
    "") print_message "$RED" "Error: Missing required argument: --provider"; echo; usage ;;
    *)  print_message "$RED" "Error: --provider must be ONTAP_S3, SGWS or S3_COMPATIBLE."; exit 1 ;;
esac

# --dry-run only prints the body, so it needs no token or agent.
if [ "$DRY_RUN" = "true" ]; then
    require_env ACCOUNT_ID
else
    require_env ACCESS_TOKEN ACCOUNT_ID AGENT_ID
fi

BASE="/backup-recovery/organizations/${ACCOUNT_ID}/v1"

# Print the credential list of $PROVIDER as JSON.
fetch_credentials() {
    local args=(-sS --fail-with-body --get "${CONSOLE_API}${BASE}/credentials"
        --data-urlencode "provider=${PROVIDER}"
        -H "Authorization: Bearer ${ACCESS_TOKEN}"
        -H "Accept: application/json"
        -H "X-Agent-Id: ${AGENT_ID}")
    [ -n "$WORKSPACE_ID" ] && args+=(-H "x-netapp-workspace-id: ${WORKSPACE_ID}")
    curl "${args[@]}"
}

CRED_LIST='(if type == "array" then . else (.items // .credentials // .records // []) end)'

if [ "$LIST" = "true" ]; then
    fetch_credentials | jq -r "${CRED_LIST} | .[] | \"\(.credential_name)  \(.credential_uuid)  \(.storage_server_name // \"\")\""
    exit 0
fi

if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || [ "$TIMEOUT" -lt 1 ]; then
    print_message "$RED" "Error: --timeout must be a positive number of seconds, got '$TIMEOUT'."
    exit 1
fi

PORT="${PORT:-$DEFAULT_PORT}"

MISSING=""
[ -z "$NAME" ] && MISSING="$MISSING --name"
[ -z "$SERVER" ] && MISSING="$MISSING --server"
[ -z "$ACCESSKEY" ] && MISSING="$MISSING --access-key"
[ -z "$SECRETKEY" ] && MISSING="$MISSING --secret-key"
if [ -n "$MISSING" ]; then
    print_message "$RED" "Error: Missing required arguments or environment variables:${MISSING}"
    echo
    usage
fi

if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    print_message "$RED" "Error: --port must be a number between 1 and 65535, got '$PORT'."
    exit 1
fi

export PROVIDER NAME SERVER PORT ACCESSKEY SECRETKEY
PAYLOAD=$(jq -n '{
    provider: env.PROVIDER,
    credential_name: env.NAME,
    storage_server_name: env.SERVER,
    port: (env.PORT | tonumber),
    access_key: env.ACCESSKEY,
    secret_password: env.SECRETKEY
}')
# Show only the first four characters of the access key and none of the secret.
REDACTED_PAYLOAD=$(echo "$PAYLOAD" | jq '
    .access_key = ((.access_key | .[0:4]) + "***REDACTED***")
    | .secret_password = "***REDACTED***"')

CREDENTIALS_URL="${CONSOLE_API}${BASE}/credentials"

print_message "$GREEN" "\nNetApp Console - add ${PROVIDER} credential"
echo "Name:     $NAME"
echo "Server:   $SERVER"
echo "Port:     $PORT"
echo "API:      $CONSOLE_API"
echo "Agent:    ${AGENT_ID:-(not set)}"
echo
print_message "$YELLOW" "Request body (keys redacted):"
echo "$REDACTED_PAYLOAD" | jq .

if [ "$DRY_RUN" = "true" ]; then
    print_message "$YELLOW" "\nDry run. No API call was made."
    exit 0
fi

print_message "$BLUE" "\nAdding credential at ${CREDENTIALS_URL}"

BODY_FILE=$(mktemp)
trap 'rm -f "$BODY_FILE"' EXIT
POST_ARGS=(-sS -o "$BODY_FILE" -w '%{http_code}' -X POST "$CREDENTIALS_URL"
    -H "Authorization: Bearer $ACCESS_TOKEN"
    -H "Content-Type: application/json"
    -H "Accept: application/json"
    -H "X-Agent-Id: $AGENT_ID"
    --data-binary @-)
[ -n "$WORKSPACE_ID" ] && POST_ARGS+=(-H "x-netapp-workspace-id: ${WORKSPACE_ID}")

# The body (with the secret) goes through stdin, not the command line.
HTTP_STATUS=$(printf '%s' "$PAYLOAD" | curl "${POST_ARGS[@]}") || HTTP_STATUS=""

if [ -n "$HTTP_STATUS" ] && [ "$HTTP_STATUS" -ge 200 ] && [ "$HTTP_STATUS" -lt 300 ]; then
    print_message "$GREEN" "Credential request accepted."
    print_message "$GREEN" "HTTP Status: $HTTP_STATUS"
    echo
    jq . "$BODY_FILE" 2>/dev/null || cat "$BODY_FILE"
    echo

    if [ "$WAIT" != "true" ]; then
        echo "The credential is usable once the job has finished. Check with:  $0 --provider $PROVIDER --list"
        echo "Or add --wait to poll for it."
        exit 0
    fi

    # Poll the credential list until the new name shows up. No job-status
    # call is documented here, so "listed" is the signal that it is registered.
    print_message "$BLUE" "Waiting up to ${TIMEOUT}s for credential '${NAME}' to be listed..."
    DEADLINE=$((SECONDS + TIMEOUT))
    while true; do
        if FOUND=$(fetch_credentials 2>/dev/null | jq -r --arg name "$NAME" \
            "[${CRED_LIST} | .[] | select((.credential_name // \"\") == \$name)] | .[0].credential_uuid // empty" 2>/dev/null) \
            && [ -n "$FOUND" ]; then
            print_message "$GREEN" "Credential '${NAME}' is listed: ${FOUND}"
            exit 0
        fi
        if [ "$SECONDS" -ge "$DEADLINE" ]; then
            print_message "$RED" "Timed out after ${TIMEOUT}s. The job may still be running, or it failed."
            echo "Check later with:  $0 --provider $PROVIDER --list"
            exit 1
        fi
        sleep 5
    done
fi

print_message "$RED" "Failed to add credential."
print_message "$RED" "HTTP Status: ${HTTP_STATUS:-none}"
echo
jq . "$BODY_FILE" 2>/dev/null || cat "$BODY_FILE"
exit 1
