#!/usr/bin/env bash
################################################################################
# NetApp Console API - Create an Azure Blob storage account as a Backup and
# Recovery target
#
# POST /backup-recovery/organizations/${ACCOUNT_ID}/v1/object-storage
#
# Requires: curl, jq. Variables follow 00-authentication/env.sh.example.
# Helper lookups (the same calls the Console UI makes):
#   GET /account/${ACCOUNT_ID}/providers/cloudmanager_cbs/api/v1/azure/subscription
#   GET /account/${ACCOUNT_ID}/providers/cloudmanager_cbs/api/v1/azure/subscription/${SUBSCRIPTION_ID}/resource-group
#
# Tested 2026-10-28 with and without --object-lock (the request is accepted; the
# lock state itself has not been checked). The Console UI sends no encryption or
# lock-mode field for Azure, so neither is exposed here.
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

Create an Azure storage account (Blob) as a Backup and Recovery target.
The Console creates the storage account in the given subscription, resource
group and region and returns a job ID.

Required:
  --name NAME                 Storage account name (object_store_name).
                              Azure allows 3-24 lowercase letters and digits.
  --subscription-id ID        Azure subscription ID (GUID), or
  --subscription-name NAME    Subscription name. The script looks up the ID.
  --resource-group NAME       Existing Azure resource group
  --region NAME               Azure region, for example eastus. Independent of
                              the resource group's region.

Optional:
  --object-lock               Enable object lock (immutable storage). Default: off.
  --account-id ID             Account (organization) ID
  --org-id ID                 Alias for --account-id
  --agent-id ID               Console agent ID
  --workspace-id ID           Console workspace/project ID, sent as
                              x-netapp-workspace-id (optional)
  --api-host URL              API host (default: CONSOLE_API, else
                              https://cloudmanager.cloud.netapp.com)
  --wait                      After the request is accepted, poll the object-storage
                              list until the storage account appears. Exit 0 when it is
                              listed, 1 on timeout.
  --timeout SECONDS           Maximum time for --wait (default: 120)
  --dry-run                   Print the request body and exit

Lookups (print and exit, no storage account is created):
  --list-subscriptions        Azure subscriptions available to the Console (id and name)
  --list-resource-groups      Resource groups of the subscription given with
                              --subscription-id or --subscription-name

  -h, --help                  Show this help text

Environment (used when the matching flag is omitted):
  ACCESS_TOKEN    (required) Console access token (alias: BEARER_TOKEN)
  ACCOUNT_ID      (required) Account / organization ID (alias: ORG_ID)
  AGENT_ID        (required) Console agent ID
  CONSOLE_API     API host (alias: API_HOST)
  WORKSPACE_ID    Console workspace/project ID (aliases: TENANT_ID, PROJECT_ID)
  SUBSCRIPTION_ID Azure subscription ID, same as --subscription-id
                  (alias: AZURE_SUBSCRIPTION_ID)

Example:
  source ../00-authentication/env.sh   # then refresh ACCESS_TOKEN (see 00-authentication)

  $0 --list-subscriptions
  $0 --list-resource-groups --subscription-name <subscription_name>
  $0 --name <storage_account_name> --subscription-name <subscription_name> \\
     --resource-group <resource_group> --region <azure_region> --object-lock
EOF
    exit 1
}

print_message() {
    echo -e "${1}${2}${NC}"
}

NAME=""
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-${AZURE_SUBSCRIPTION_ID:-}}"
SUBSCRIPTION_NAME=""
RESOURCE_GROUP=""
REGION=""
OBJECT_LOCK="false"
LIST_SUBSCRIPTIONS="false"
LIST_RESOURCE_GROUPS="false"
WAIT="false"
TIMEOUT="120"
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        --name)            NAME="${2:?missing value for $1}"; shift 2 ;;
        --subscription-id) SUBSCRIPTION_ID="${2:?missing value for $1}"; shift 2 ;;
        --subscription-name) SUBSCRIPTION_NAME="${2:?missing value for $1}"; shift 2 ;;
        --resource-group)  RESOURCE_GROUP="${2:?missing value for $1}"; shift 2 ;;
        --list-subscriptions)   LIST_SUBSCRIPTIONS="true"; shift ;;
        --list-resource-groups) LIST_RESOURCE_GROUPS="true"; shift ;;
        --region)          REGION="${2:?missing value for $1}"; shift 2 ;;
        --object-lock)     OBJECT_LOCK="true"; shift ;;
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
        -H "X-Account-Id: ${ACCOUNT_ID}"
        -H "X-Agent-Id: ${AGENT_ID}")
    [ -n "$WORKSPACE_ID" ] && args+=(-H "x-netapp-workspace-id: ${WORKSPACE_ID}")
    curl "${args[@]}"
}

CBS_BASE="/account/${ACCOUNT_ID}/providers/cloudmanager_cbs/api/v1/azure"

if [ "$LIST_SUBSCRIPTIONS" = "true" ]; then
    console_get "${CBS_BASE}/subscription" | jq -r '.subscription[] | "\(.id)  \(.name)"'
    exit 0
fi

# Resolve a subscription name to its subscription ID.
if [ -z "$SUBSCRIPTION_ID" ] && [ -n "$SUBSCRIPTION_NAME" ]; then
    if [ "$DRY_RUN" = "true" ]; then
        SUBSCRIPTION_ID="<resolved from subscription name '${SUBSCRIPTION_NAME}'>"
    else
        print_message "$BLUE" "Looking up subscription '$SUBSCRIPTION_NAME'" >&2
        SUBSCRIPTIONS=$(console_get "${CBS_BASE}/subscription")
        MATCHES=$(echo "$SUBSCRIPTIONS" | jq -c --arg name "$SUBSCRIPTION_NAME" \
            '[.subscription[]? | select(.name == $name)]')
        case "$(echo "$MATCHES" | jq 'length')" in
            0) print_message "$RED" "Error: no subscription named '$SUBSCRIPTION_NAME'. Available:"
               echo "$SUBSCRIPTIONS" | jq -r '.subscription[]? | "  \(.name)  \(.id)"'
               exit 1 ;;
            1) SUBSCRIPTION_ID=$(echo "$MATCHES" | jq -r '.[0].id')
               print_message "$GREEN" "Resolved '$SUBSCRIPTION_NAME' to $SUBSCRIPTION_ID" ;;
            *) print_message "$RED" "Error: more than one subscription is named '$SUBSCRIPTION_NAME'."
               exit 1 ;;
        esac
    fi
fi

if [ "$LIST_RESOURCE_GROUPS" = "true" ]; then
    if [ -z "$SUBSCRIPTION_ID" ]; then
        print_message "$RED" "Error: --list-resource-groups needs a subscription: --subscription-id, --subscription-name, or the SUBSCRIPTION_ID variable."
        echo "List the subscriptions with:  $0 --list-subscriptions"
        exit 1
    fi
    console_get "${CBS_BASE}/subscription/${SUBSCRIPTION_ID}/resource-group" \
        | jq -r '.["resource-group"][] | "\(.name)  (\(.region))"'
    exit 0
fi

MISSING=""
[ -z "$NAME" ] && MISSING="$MISSING --name"
[ -z "$SUBSCRIPTION_ID" ] && MISSING="$MISSING --subscription-id or --subscription-name"
[ -z "$RESOURCE_GROUP" ] && MISSING="$MISSING --resource-group"
[ -z "$REGION" ] && MISSING="$MISSING --region"
if [ -n "$MISSING" ]; then
    print_message "$RED" "Error: Missing required arguments:${MISSING}"
    echo
    usage
fi

if ! [[ "$NAME" =~ ^[a-z0-9]{3,24}$ ]]; then
    print_message "$YELLOW" "Warning: '$NAME' is not a valid Azure storage account name (3-24 lowercase letters and digits). The API may reject it."
fi

PAYLOAD=$(jq -n \
    --arg name "$NAME" \
    --arg subscription "$SUBSCRIPTION_ID" \
    --arg resourceGroup "$RESOURCE_GROUP" \
    --arg region "$REGION" \
    --argjson objectLock "$OBJECT_LOCK" \
    '{
        provider: "AZURE",
        object_store_name: $name,
        object_lock: $objectLock,
        azure: {resource_group: $resourceGroup, subscription: $subscription},
        region: $region
    }')

if [ -z "$(echo "$PAYLOAD" | jq -r '.object_store_name // empty')" ]; then
    print_message "$RED" "Error: the request body has no object_store_name. Not sending."
    echo "$PAYLOAD" | jq .
    exit 1
fi

BUCKETS_URL="${CONSOLE_API}/backup-recovery/organizations/${ACCOUNT_ID}/v1/object-storage"

print_message "$GREEN" "\nNetApp Console - Azure storage account"
echo "Name:           $NAME"
echo "Subscription:   $SUBSCRIPTION_ID"
echo "Resource group: $RESOURCE_GROUP"
echo "Region:         $REGION"
echo "Object lock:    $OBJECT_LOCK"
echo "API:            $CONSOLE_API"
echo "Agent:          ${AGENT_ID:-(not set)}"
echo
print_message "$YELLOW" "Request body:"
echo "$PAYLOAD" | jq .

if [ "$DRY_RUN" = "true" ]; then
    print_message "$YELLOW" "\nDry run. No API call was made."
    exit 0
fi

print_message "$BLUE" "\nCreating storage account at ${BUCKETS_URL}"

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
    print_message "$GREEN" "Storage account create request accepted."
    print_message "$GREEN" "HTTP Status: $HTTP_STATUS"
    echo
    jq . "$BODY_FILE" 2>/dev/null || cat "$BODY_FILE"

    if [ "$WAIT" = "true" ]; then
        # Export what the shared helper needs (api_get uses these names).
        export CONSOLE_API ACCESS_TOKEN AGENT_ID ACCOUNT_ID
        print_message "$BLUE" "\nWaiting up to ${TIMEOUT}s for storage account '$NAME' to be listed..."
        # The Azure list call needs the subscription and the resource group.
        RG_ENC=$(jq -rn --arg v "$RESOURCE_GROUP" '$v | @uri')
        if wait_for_object_store "provider=AZURE&subscription=${SUBSCRIPTION_ID}&resource-group=${RG_ENC}" "$NAME" "$TIMEOUT"; then
            print_message "$GREEN" "The storage account '$NAME' is listed."
            exit 0
        fi
        print_message "$RED" "Timed out after ${TIMEOUT}s. The job may still be running, or it failed."
        exit 1
    fi
    exit 0
fi

print_message "$RED" "Failed to create storage account."
print_message "$RED" "HTTP Status: ${HTTP_STATUS:-none}"
echo
jq . "$BODY_FILE" 2>/dev/null || cat "$BODY_FILE"
exit 1
