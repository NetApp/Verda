#!/usr/bin/env bash
################################################################################
# NetApp Console API - Create an AWS S3 bucket as a Backup and Recovery target
#
# POST /backup-recovery/organizations/${ACCOUNT_ID}/v1/object-storage
#
# Helper lookups (the same calls the Console UI makes):
#   GET /occm/api/accounts/cloud-providers            (AWS account name -> account ID)
#   GET /account/${ACCOUNT_ID}/providers/cloudmanager_cbs/api/v1/aws/region
#   GET /account/${ACCOUNT_ID}/providers/cloudmanager_cbs/api/v1/aws/awsAccountId/${AWS_ACCOUNT_ID}/region/${REGION}/key
#
# Requires: curl, jq. Variables follow 00-authentication/env.sh.example.
# Tested 2026-10-28 with default encryption, no object lock and no tags. Object lock
# modes, tags and customer-managed KMS keys are not yet tested.
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

Create an AWS S3 bucket as a Backup and Recovery target.
The Console creates the bucket in the given AWS account and region and
returns a job ID.

Required:
  --bucket NAME               Bucket name (object_store_name)
  --region CODE               AWS region code, for example eu-central-1
  --aws-account-id ID         AWS account ID (12 digits), or
  --aws-account-name NAME     Name of the AWS credential in the Console. The
                              script looks up the account ID.

Optional:
  --kms-key-id ID             KMS key ID for encryption (default: empty, which
                              is what the UI sends for the default encryption)
  --object-lock-mode MODE     NONE (default), COMPLIANCE or GOVERNANCE. Any mode
                              other than NONE also sets object_lock=true.
                              Object lock modes are not yet tested.
                              The UI sends no versioning field: versioning
                              appears to be enabled by the Console with object lock.
  --tag KEY=VALUE             AWS tag for the bucket. Repeat for several tags.
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
  --list-aws-accounts         AWS accounts known to the Console (id and name)
  --list-regions              AWS regions available to the account
  --list-kms-keys             KMS keys for --aws-account-id and --region

  -h, --help                  Show this help text

Environment (used when the matching flag is omitted):
  ACCESS_TOKEN    (required) Console access token (alias: BEARER_TOKEN)
  ACCOUNT_ID      (required) Account / organization ID (alias: ORG_ID)
  AGENT_ID        (required) Console agent ID
  CONSOLE_API     API host (alias: API_HOST)
  WORKSPACE_ID    Console workspace/project ID (aliases: TENANT_ID, PROJECT_ID)

Example:
  source ../00-authentication/env.sh   # then refresh ACCESS_TOKEN (see 00-authentication)

  $0 --list-aws-accounts
  $0 --list-regions
  $0 --bucket <bucket_name> --region <region_code> --aws-account-name <aws_credential_name>
EOF
    exit 1
}

print_message() {
    echo -e "${1}${2}${NC}"
}

BUCKET=""
REGION=""
AWS_ACCOUNT_ID=""
AWS_ACCOUNT_NAME=""
KMS_KEY_ID=""
OBJECT_LOCK_MODE="NONE"
TAGS=()
LIST_AWS_ACCOUNTS="false"
LIST_REGIONS="false"
LIST_KMS_KEYS="false"
WAIT="false"
TIMEOUT="120"
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        --bucket)           BUCKET="${2:?missing value for $1}"; shift 2 ;;
        --region)           REGION="${2:?missing value for $1}"; shift 2 ;;
        --aws-account-id)   AWS_ACCOUNT_ID="${2:?missing value for $1}"; shift 2 ;;
        --aws-account-name) AWS_ACCOUNT_NAME="${2:?missing value for $1}"; shift 2 ;;
        --kms-key-id)       KMS_KEY_ID="${2:?missing value for $1}"; shift 2 ;;
        --object-lock-mode) OBJECT_LOCK_MODE="${2:?missing value for $1}"; shift 2 ;;
        --tag)              TAGS+=("${2:?missing value for $1}"); shift 2 ;;
        --account-id|--org-id) ACCOUNT_ID="${2:?missing value for $1}"; shift 2 ;;
        --agent-id)         AGENT_ID="${2:?missing value for $1}"; shift 2 ;;
        --workspace-id)     WORKSPACE_ID="${2:?missing value for $1}"; shift 2 ;;
        --api-host)         CONSOLE_API="${2:?missing value for $1}"; shift 2 ;;
        --list-aws-accounts) LIST_AWS_ACCOUNTS="true"; shift ;;
        --list-regions)     LIST_REGIONS="true"; shift ;;
        --list-kms-keys)    LIST_KMS_KEYS="true"; shift ;;
        --wait)            WAIT="true"; shift ;;
        --timeout)         TIMEOUT="${2:?missing value for $1}"; shift 2 ;;
        --dry-run)          DRY_RUN="true"; shift ;;
        -h|--help)          usage ;;
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
        -H "X-Account-Id: ${ACCOUNT_ID}"
        -H "X-Agent-Id: ${AGENT_ID}")
    [ -n "$WORKSPACE_ID" ] && args+=(-H "x-netapp-workspace-id: ${WORKSPACE_ID}")
    curl "${args[@]}"
}

CBS_BASE="/account/${ACCOUNT_ID}/providers/cloudmanager_cbs/api/v1/aws"
CLOUD_PROVIDERS_PATH="/occm/api/accounts/cloud-providers"

if [ "$LIST_AWS_ACCOUNTS" = "true" ]; then
    console_get "$CLOUD_PROVIDERS_PATH" \
        | jq -r '.awsAccounts[] | "\(.accountId)  \(.accountName)  (\(.accountType))"'
    exit 0
fi

# Resolve an AWS credential name to its 12-digit AWS account ID.
if [ -z "$AWS_ACCOUNT_ID" ] && [ -n "$AWS_ACCOUNT_NAME" ]; then
    if [ "$DRY_RUN" = "true" ]; then
        AWS_ACCOUNT_ID="<resolved from AWS account name '${AWS_ACCOUNT_NAME}'>"
    else
        print_message "$BLUE" "Looking up AWS account '$AWS_ACCOUNT_NAME'" >&2
        ACCOUNTS=$(console_get "$CLOUD_PROVIDERS_PATH")
        MATCHES=$(echo "$ACCOUNTS" | jq -c --arg name "$AWS_ACCOUNT_NAME" \
            '[.awsAccounts[]? | select(.accountName == $name)]')
        case "$(echo "$MATCHES" | jq 'length')" in
            0) print_message "$RED" "Error: no AWS account named '$AWS_ACCOUNT_NAME'. Available:"
               echo "$ACCOUNTS" | jq -r '.awsAccounts[]? | "  \(.accountName)  \(.accountId)"'
               exit 1 ;;
            1) AWS_ACCOUNT_ID=$(echo "$MATCHES" | jq -r '.[0].accountId')
               print_message "$GREEN" "Resolved '$AWS_ACCOUNT_NAME' to $AWS_ACCOUNT_ID" ;;
            *) print_message "$RED" "Error: more than one AWS account is named '$AWS_ACCOUNT_NAME'."
               exit 1 ;;
        esac
    fi
fi

if [ "$LIST_REGIONS" = "true" ]; then
    console_get "${CBS_BASE}/region" | jq -r '.region[] | "\(.code)  \(.name)"'
    exit 0
fi

if [ "$LIST_KMS_KEYS" = "true" ]; then
    require_env AWS_ACCOUNT_ID REGION
    console_get "${CBS_BASE}/awsAccountId/${AWS_ACCOUNT_ID}/region/${REGION}/key" \
        | jq -r '.key[] | "\(.id)  \(.name)  (\(.origin))"'
    exit 0
fi

MISSING=""
[ -z "$BUCKET" ] && MISSING="$MISSING --bucket"
[ -z "$REGION" ] && MISSING="$MISSING --region"
[ -z "$AWS_ACCOUNT_ID" ] && MISSING="$MISSING --aws-account-id or --aws-account-name"
if [ -n "$MISSING" ]; then
    print_message "$RED" "Error: Missing required arguments:${MISSING}"
    echo
    usage
fi

case "$OBJECT_LOCK_MODE" in
    NONE|COMPLIANCE|GOVERNANCE) ;;
    *) print_message "$RED" "Error: --object-lock-mode must be NONE, COMPLIANCE or GOVERNANCE."; exit 1 ;;
esac
OBJECT_LOCK="false"
[ "$OBJECT_LOCK_MODE" != "NONE" ] && OBJECT_LOCK="true"

# Tags: KEY=VALUE pairs -> [{"Key":..., "Value":...}]. Omitted when none are given.
TAGS_JSON="[]"
for tag in ${TAGS[@]+"${TAGS[@]}"}; do
    if [[ "$tag" != *=* ]] || [ -z "${tag%%=*}" ]; then
        print_message "$RED" "Error: --tag must be KEY=VALUE, got '$tag'."
        exit 1
    fi
    TAGS_JSON=$(echo "$TAGS_JSON" | jq -c --arg k "${tag%%=*}" --arg v "${tag#*=}" '. + [{Key: $k, Value: $v}]')
done

PAYLOAD=$(jq -n \
    --arg bucket "$BUCKET" \
    --arg region "$REGION" \
    --arg awsAccountId "$AWS_ACCOUNT_ID" \
    --arg kmsKeyId "$KMS_KEY_ID" \
    --arg lockMode "$OBJECT_LOCK_MODE" \
    --argjson objectLock "$OBJECT_LOCK" \
    --argjson tags "$TAGS_JSON" \
    '{
        provider: "AWS",
        object_store_name: $bucket,
        object_lock: $objectLock,
        region: $region,
        aws: {account_id: $awsAccountId, kms_key_id: $kmsKeyId},
        object_lock_mode: $lockMode
    } + (if ($tags | length) > 0 then {tags: $tags} else {} end)')

if [ -z "$(echo "$PAYLOAD" | jq -r '.object_store_name // empty')" ]; then
    print_message "$RED" "Error: the request body has no object_store_name. Not sending."
    echo "$PAYLOAD" | jq .
    exit 1
fi

BUCKETS_URL="${CONSOLE_API}/backup-recovery/organizations/${ACCOUNT_ID}/v1/object-storage"

print_message "$GREEN" "\nNetApp Console - AWS S3 bucket"
echo "Bucket:         $BUCKET"
echo "Region:         $REGION"
echo "AWS account:    $AWS_ACCOUNT_ID"
echo "KMS key:        ${KMS_KEY_ID:-(default encryption)}"
echo "Object lock:    $OBJECT_LOCK_MODE"
echo "Tags:           $(echo "$TAGS_JSON" | jq -r 'if length == 0 then "(none)" else map("\(.Key)=\(.Value)") | join(", ") end')"
echo "API:            $CONSOLE_API"
echo "Agent:          ${AGENT_ID:-(not set)}"
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
        # The AWS list call needs the AWS account ID.
        if wait_for_object_store "provider=AWS&aws-account-id=${AWS_ACCOUNT_ID}" "$BUCKET" "$TIMEOUT"; then
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
