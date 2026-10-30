#!/usr/bin/env bash
################################################################################
# NetApp Console API - Create a StorageGRID bucket as a Backup and Recovery
# target (provider SGWS)
#
# POST /backup-recovery/organizations/${ACCOUNT_ID}/v1/object-storage
#
# Helper lookup (the same call the Console UI makes):
#   GET /backup-recovery/organizations/${ACCOUNT_ID}/v1/credentials?provider=SGWS
#
# Requires: curl, jq. Variables follow 00-authentication/env.sh.example.
# Not yet tested against a real StorageGRID system.
################################################################################
set -euo pipefail
# shellcheck source=../lib/bnr-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/bnr-common.sh"

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

Create a StorageGRID bucket as a Backup and Recovery target (not yet tested).
The StorageGRID credential must already exist (see
02-credentials-and-targets/storagegrid.md). The call returns a job ID.

Required:
  --bucket NAME               Bucket name (object_store_name)
  --credential-name NAME      Existing StorageGRID credential. The script looks up its id.
  --credential-id ID          Credential id, if you already have it

Optional:
  --object-lock               Enable object lock (default: off)
  --account-id ID             Account (organization) ID
  --org-id ID                 Alias for --account-id
  --agent-id ID               Console agent ID
  --workspace-id ID           Console workspace/project ID, sent as
                              x-netapp-workspace-id (optional)
  --api-host URL              API host (default: CONSOLE_API, else
                              https://cloudmanager.cloud.netapp.com)
  --wait                      After the request is accepted, poll the object-storage
                              list until the bucket appears. Exit 0 when it is
                              listed, 1 on timeout.
  --timeout SECONDS           Maximum time for --wait (default: 120)
  --dry-run                   Print the request body and exit

Lookups (print and exit, no bucket is created):
  --list-credentials          StorageGRID credentials (name, id, server)

  -h, --help                  Show this help text

Environment (used when the matching flag is omitted):
  ACCESS_TOKEN    (required) Console access token (alias: BEARER_TOKEN)
  ACCOUNT_ID      (required) Account / organization ID (alias: ORG_ID)
  AGENT_ID        (required) Console agent ID
  CONSOLE_API     API host (alias: API_HOST)
  WORKSPACE_ID    Console workspace/project ID (aliases: TENANT_ID, PROJECT_ID)

Example:
  source ../00-authentication/env.sh   # then refresh ACCESS_TOKEN (see 00-authentication)

  $0 --list-credentials
  $0 --bucket <bucket_name> --credential-name <credential_name> --object-lock
EOF
    exit 1
}

print_message() {
    echo -e "${1}${2}${NC}"
}

BUCKET=""
CREDENTIAL_ID=""
CREDENTIAL_NAME=""
OBJECT_LOCK="false"
LIST_CREDENTIALS="false"
WAIT="false"
TIMEOUT="120"
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        --bucket)          BUCKET="${2:?missing value for $1}"; shift 2 ;;
        --credential-name) CREDENTIAL_NAME="${2:?missing value for $1}"; shift 2 ;;
        --credential-id)   CREDENTIAL_ID="${2:?missing value for $1}"; shift 2 ;;
        --object-lock)     OBJECT_LOCK="true"; shift ;;
        --list-credentials) LIST_CREDENTIALS="true"; shift ;;
        --account-id|--org-id) ACCOUNT_ID="${2:?missing value for $1}"; shift 2 ;;
        --agent-id)        AGENT_ID="${2:?missing value for $1}"; shift 2 ;;
        --workspace-id)    WORKSPACE_ID="${2:?missing value for $1}"; shift 2 ;;
        --api-host)        CONSOLE_API="${2:?missing value for $1}"; shift 2 ;;
        --wait)            WAIT="true"; shift ;;
        --timeout)         TIMEOUT="${2:?missing value for $1}"; shift 2 ;;
        --dry-run)         DRY_RUN="true"; shift ;;
        -h|--help)         usage ;;
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

if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || [ "$TIMEOUT" -lt 1 ]; then
    print_message "$RED" "Error: --timeout must be a positive number of seconds, got '$TIMEOUT'."
    exit 1
fi

# --dry-run only prints the body, so it needs no token or agent.
if [ "$DRY_RUN" = "true" ]; then
    require_env ACCOUNT_ID
else
    require_env ACCESS_TOKEN ACCOUNT_ID AGENT_ID
fi

# GET a path below CONSOLE_API with the headers the Console UI sends.
console_get() {
    local args=(-sS --fail-with-body "${CONSOLE_API}$1"
        -H "Authorization: Bearer ${ACCESS_TOKEN}"
        -H "Accept: application/json"
        -H "X-Agent-Id: ${AGENT_ID}")
    [ -n "$WORKSPACE_ID" ] && args+=(-H "x-netapp-workspace-id: ${WORKSPACE_ID}")
    curl "${args[@]}"
}

BASE="/backup-recovery/organizations/${ACCOUNT_ID}/v1"
# Credential list shape: array of {credential_uuid, credential_name, storage_server_name, ...}
CRED_LIST='(if type == "array" then . else (.items // .credentials // .records // []) end)'

if [ "$LIST_CREDENTIALS" = "true" ]; then
    console_get "${BASE}/credentials?provider=SGWS" \
        | jq -r "${CRED_LIST} | .[] | \"\(.credential_name)  \(.credential_uuid)  \(.storage_server_name // \"\")\""
    exit 0
fi

MISSING=""
[ -z "$BUCKET" ] && MISSING="$MISSING --bucket"
if [ -z "$CREDENTIAL_ID" ] && [ -z "$CREDENTIAL_NAME" ]; then
    MISSING="$MISSING --credential-name or --credential-id"
fi
if [ -n "$MISSING" ]; then
    print_message "$RED" "Error: Missing required arguments:${MISSING}"
    echo
    usage
fi

# Resolve a credential name to its credential_uuid.
if [ -z "$CREDENTIAL_ID" ]; then
    if [ "$DRY_RUN" = "true" ]; then
        CREDENTIAL_ID="<resolved from credential name '${CREDENTIAL_NAME}'>"
    else
        print_message "$BLUE" "Looking up credential '$CREDENTIAL_NAME'" >&2
        CREDENTIALS=$(console_get "${BASE}/credentials?provider=SGWS")
        MATCHES=$(echo "$CREDENTIALS" | jq -c --arg name "$CREDENTIAL_NAME" \
            "[${CRED_LIST} | .[] | select((.credential_name // \"\") == \$name)]")
        case "$(echo "$MATCHES" | jq 'length')" in
            0) print_message "$RED" "Error: no SGWS credential named '$CREDENTIAL_NAME'. Available:"
               echo "$CREDENTIALS" | jq -r "${CRED_LIST} | .[] | \"  \(.credential_name)  \(.credential_uuid)\""
               exit 1 ;;
            1) CREDENTIAL_ID=$(echo "$MATCHES" | jq -r '.[0].credential_uuid // empty')
               if [ -z "$CREDENTIAL_ID" ]; then
                   print_message "$RED" "Error: credential '$CREDENTIAL_NAME' has no credential_uuid."
                   exit 1
               fi
               print_message "$GREEN" "Resolved '$CREDENTIAL_NAME' to $CREDENTIAL_ID" ;;
            *) print_message "$RED" "Error: more than one credential is named '$CREDENTIAL_NAME'."
               echo "$MATCHES" | jq -r '.[] | "  \(.credential_name)  \(.credential_uuid)"'
               exit 1 ;;
        esac
    fi
fi

PAYLOAD=$(jq -n \
    --arg bucket "$BUCKET" \
    --arg credentialId "$CREDENTIAL_ID" \
    --argjson objectLock "$OBJECT_LOCK" \
    '{
        provider: "SGWS",
        object_store_name: $bucket,
        object_lock: $objectLock,
        sgws: {credential_id: $credentialId}
    }')

if [ -z "$(echo "$PAYLOAD" | jq -r '.object_store_name // empty')" ]; then
    print_message "$RED" "Error: the request body has no object_store_name. Not sending."
    echo "$PAYLOAD" | jq .
    exit 1
fi

BUCKETS_URL="${CONSOLE_API}${BASE}/object-storage"

print_message "$GREEN" "\nNetApp Console - StorageGRID bucket"
echo "Bucket:      $BUCKET"
echo "Credential:  $CREDENTIAL_ID"
echo "Object lock: $OBJECT_LOCK"
echo "API:         $CONSOLE_API"
echo "Agent:       ${AGENT_ID:-(not set)}"
echo
print_message "$YELLOW" "Request body:"
echo "$PAYLOAD" | jq .

if [ "$DRY_RUN" = "true" ]; then
    print_message "$YELLOW" "\nDry run. No API call was made."
    exit 0
fi

print_message "$BLUE" "\nCreating bucket at ${BUCKETS_URL}"

BODY_FILE=$(mktemp)
trap 'rm -f "$BODY_FILE"' EXIT
POST_ARGS=(-sS -o "$BODY_FILE" -w '%{http_code}' -X POST "$BUCKETS_URL"
    -H "Authorization: Bearer $ACCESS_TOKEN"
    -H "Content-Type: application/json"
    -H "Accept: application/json"
    -H "X-Agent-Id: $AGENT_ID"
    -d "$PAYLOAD")
[ -n "$WORKSPACE_ID" ] && POST_ARGS+=(-H "x-netapp-workspace-id: ${WORKSPACE_ID}")

HTTP_STATUS=$(curl "${POST_ARGS[@]}") || HTTP_STATUS=""

if [ -n "$HTTP_STATUS" ] && [ "$HTTP_STATUS" -ge 200 ] && [ "$HTTP_STATUS" -lt 300 ]; then
    print_message "$GREEN" "Bucket create request accepted."
    print_message "$GREEN" "HTTP Status: $HTTP_STATUS"
    echo
    jq . "$BODY_FILE" 2>/dev/null || cat "$BODY_FILE"

    if [ "$WAIT" = "true" ]; then
        # Export what the shared helper needs (api_get uses these names).
        export CONSOLE_API ACCESS_TOKEN AGENT_ID ACCOUNT_ID
        print_message "$BLUE" "\nWaiting up to ${TIMEOUT}s for bucket '$BUCKET' to be listed..."
        if wait_for_object_store "provider=SGWS&credential-id=${CREDENTIAL_ID}" "$BUCKET" "$TIMEOUT"; then
            print_message "$GREEN" "The bucket '$BUCKET' is listed."
            exit 0
        fi
        print_message "$RED" "Timed out after ${TIMEOUT}s. The job may still be running, or it failed."
        exit 1
    fi
    exit 0
fi

print_message "$RED" "Failed to create bucket."
print_message "$RED" "HTTP Status: ${HTTP_STATUS:-none}"
echo
jq . "$BODY_FILE" 2>/dev/null || cat "$BODY_FILE"
exit 1
