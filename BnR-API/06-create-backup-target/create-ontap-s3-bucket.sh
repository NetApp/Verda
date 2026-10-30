#!/usr/bin/env bash
################################################################################
# NetApp Console API - Create an ONTAP S3 bucket as a Backup and Recovery target
#
# POST /backup-recovery/organizations/${ACCOUNT_ID}/v1/object-storage
#
# Requires: curl, jq. Variables follow 00-authentication/env.sh.example.
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
# ACCESS_TOKEN / CONSOLE_API / ACCOUNT_ID are the names used in the other
# sections; BEARER_TOKEN / API_HOST / ORG_ID are accepted as aliases.
ACCESS_TOKEN="${ACCESS_TOKEN:-${BEARER_TOKEN:-}}"
CONSOLE_API="${CONSOLE_API:-${API_HOST:-https://cloudmanager.cloud.netapp.com}}"
ORG_ID="${ORG_ID:-}"
ACCOUNT_ID="${ACCOUNT_ID:-}"
AGENT_ID="${AGENT_ID:-}"

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Create an ONTAP S3 object-storage bucket as a Backup and Recovery target.
The ONTAP S3 credential must already exist (see 02-credentials-and-targets/ontap-s3.md).

Required:
  --bucket NAME               Bucket name (object_store_name)
  --credential-name NAME      Existing ONTAP S3 credential. The script looks up its id.
  --credential-id ID          Credential id, if you already have it

Optional:
  --object-lock               Enable object lock (default: false)
  --account-id ID             Account (organization) ID
  --org-id ID                 Alias for --account-id
  --agent-id ID               Console agent ID
  --api-host URL              API host (default: CONSOLE_API, else
                              https://cloudmanager.cloud.netapp.com)
  --wait                      After the request is accepted, poll the object-storage
                              list until the bucket appears. Exit 0 when it is
                              listed, 1 on timeout.
  --timeout SECONDS           Maximum time for --wait (default: 120)
  --dry-run                   Print the request body and exit

Lookups (print and exit, no bucket is created):
  --list-credentials          ONTAP S3 credentials (name, id, server)

  -h, --help                  Show this help text

Environment (used when the matching flag is omitted):
  ACCESS_TOKEN    (required) Console access token (alias: BEARER_TOKEN)
  ACCOUNT_ID      (required) Account / organization ID (alias: ORG_ID)
  AGENT_ID        (required) Console agent ID
  CONSOLE_API     API host (alias: API_HOST)

Example:
  source ../00-authentication/env.sh   # then refresh ACCESS_TOKEN (see 00-authentication)

  $0 --list-credentials
  $0 --bucket <bucket_name> --credential-name <credential_name>
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

BASE="/backup-recovery/organizations/${ACCOUNT_ID}/v1"

if [ "$LIST_CREDENTIALS" = "true" ]; then
    api_get "${BASE}/credentials?provider=ONTAP_S3" | jq -r '
        (if type == "array" then . else (.items // .credentials // .records // []) end)
        | .[] | "\(.credential_name // .credentialName // .name // "(unnamed)")  \(.credential_uuid // .credentialId // .id // "")  \(.storage_server_name // "")"'
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

# Resolve a credential name to its credential_uuid. Prints the id on stdout.
resolve_credential_id() {
    local name=$1 body matches count id
    print_message "$BLUE" "Looking up credential '$name'" >&2
    body=$(api_get "${BASE}/credentials?provider=ONTAP_S3") || {
        print_message "$RED" "Error: credential list failed." >&2
        echo "$body" | jq . >&2 2>/dev/null || echo "$body" >&2
        return 1
    }

    matches=$(echo "$body" | jq -c --arg name "$name" '
        (if type == "array" then . else (.items // .credentials // .records // []) end)
        | map(select((.credential_name // .credentialName // .name // "") == $name))')
    count=$(echo "$matches" | jq 'length')
    if [ "$count" -gt 1 ]; then
        print_message "$RED" "Error: more than one credential is named '$name'." >&2
        echo "$matches" | jq -r '.[] | "  \(.credential_name // .name)  \(.credential_uuid // .id // "")"' >&2
        return 1
    fi
    if [ "$count" -eq 0 ]; then
        print_message "$RED" "Error: no ONTAP_S3 credential named '$name'. Available:" >&2
        echo "$body" | jq -r '
            (if type == "array" then . else (.items // .credentials // .records // []) end)
            | .[] | "  \(.credential_name // .credentialName // .name // "(unnamed)")  \(.credential_uuid // .credentialId // .id // "")"' >&2 2>/dev/null || true
        return 1
    fi

    id=$(echo "$matches" | jq -r '.[0].credential_uuid // .[0].credentialId // .[0].id // empty')
    if [ -z "$id" ]; then
        print_message "$RED" "Error: credential '$name' has no credential_uuid." >&2
        echo "$matches" | jq . >&2
        return 1
    fi
    print_message "$GREEN" "Resolved credential '$name' to $id" >&2
    printf '%s' "$id"
}

if [ -z "$CREDENTIAL_ID" ]; then
    if [ "$DRY_RUN" = "true" ]; then
        # No API call in dry-run mode: show a placeholder instead of a lookup.
        CREDENTIAL_ID="<resolved from credential name '${CREDENTIAL_NAME}'>"
    else
        CREDENTIAL_ID=$(resolve_credential_id "$CREDENTIAL_NAME") || exit 1
    fi
fi

PAYLOAD=$(jq -n \
    --arg bucket "$BUCKET" \
    --arg credentialId "$CREDENTIAL_ID" \
    --argjson objectLock "$OBJECT_LOCK" \
    '{
        provider: "ONTAP_S3",
        object_store_name: $bucket,
        object_lock: $objectLock,
        ontap_s3: {credential_id: $credentialId}
    }')

if [ -z "$(echo "$PAYLOAD" | jq -r '.object_store_name // empty')" ]; then
    print_message "$RED" "Error: the request body has no object_store_name. Not sending."
    echo "$PAYLOAD" | jq .
    exit 1
fi

BUCKETS_URL="${CONSOLE_API}${BASE}/object-storage"

print_message "$GREEN" "\nNetApp Console - ONTAP S3 bucket"
echo "Bucket:     $BUCKET"
echo "Credential: $CREDENTIAL_ID"
echo "API:        $CONSOLE_API"
echo "Agent:      ${AGENT_ID:-(not set)}"
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
HTTP_STATUS=$(curl -sS -o "$BODY_FILE" -w '%{http_code}' -X POST "$BUCKETS_URL" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -H "x-account-id: $ACCOUNT_ID" \
    -H "x-agent-id: $AGENT_ID" \
    -d "$PAYLOAD") || HTTP_STATUS=""

if [ -n "$HTTP_STATUS" ] && [ "$HTTP_STATUS" -ge 200 ] && [ "$HTTP_STATUS" -lt 300 ]; then
    print_message "$GREEN" "Bucket create request accepted."
    print_message "$GREEN" "HTTP Status: $HTTP_STATUS"
    echo
    jq . "$BODY_FILE" 2>/dev/null || cat "$BODY_FILE"

    if [ "$WAIT" = "true" ]; then
        # Export what the shared helper needs (api_get uses these names).
        export CONSOLE_API ACCESS_TOKEN AGENT_ID ACCOUNT_ID
        print_message "$BLUE" "\nWaiting up to ${TIMEOUT}s for bucket '$BUCKET' to be listed..."
        if wait_for_object_store "provider=ONTAP_S3&credential-id=${CREDENTIAL_ID}" "$BUCKET" "$TIMEOUT"; then
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
