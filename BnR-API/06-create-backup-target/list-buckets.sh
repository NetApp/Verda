#!/usr/bin/env bash
################################################################################
# NetApp Console API - List the backup-target buckets already created in Backup
# and Recovery, per object-storage provider
#
# GET /backup-recovery/organizations/${ACCOUNT_ID}/v1/object-storage?provider=<P>[&credential-id=<id>]
# GET /backup-recovery/organizations/${ACCOUNT_ID}/v1/credentials?provider=<P>
#
# Requires: curl, jq. Variables follow 00-authentication/env.sh.example.
# ONTAP S3, StorageGRID and S3-compatible are queried per credential, AWS per AWS
# account (aws-account-id), Azure per subscription and resource group. Tested
# 2026-10-28 for ONTAP S3, S3-compatible, AWS and Azure. StorageGRID returned an
# empty list and is not yet tested with buckets. Read-only.
################################################################################
set -euo pipefail
# shellcheck source=../lib/bnr-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/bnr-common.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ACCESS_TOKEN="${ACCESS_TOKEN:-${BEARER_TOKEN:-}}"
CONSOLE_API="${CONSOLE_API:-${API_HOST:-https://cloudmanager.cloud.netapp.com}}"
ORG_ID="${ORG_ID:-}"
ACCOUNT_ID="${ACCOUNT_ID:-}"
AGENT_ID="${AGENT_ID:-}"

# Providers that need a credential, and providers that are queried directly.
CREDENTIAL_PROVIDERS=(ONTAP_S3 SGWS S3_COMPATIBLE)
DIRECT_PROVIDERS=(AWS AZURE)

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

List the buckets that exist in Backup and Recovery, grouped by object-storage
provider (and by credential for ONTAP S3, StorageGRID and S3-compatible).
Read-only.

Optional:
  --provider NAME             Only this provider: AWS, AZURE, ONTAP_S3, SGWS
                              or S3_COMPATIBLE (default: all)
  --aws-account-id ID         Only this AWS account (default: every AWS account
                              known to the Console)
  --subscription-id ID        Azure subscription (needed for Azure)
  --subscription-name NAME    Azure subscription name; the script looks up the ID
  --resource-group NAME       Azure resource group (needed for Azure)
  --json                      Print one JSON document instead of a text list
  --debug                     Print each request URL to stderr
  --account-id ID             Account (organization) ID
  --org-id ID                 Alias for --account-id
  --agent-id ID               Console agent ID
  --api-host URL              API host (default: CONSOLE_API, else
                              https://cloudmanager.cloud.netapp.com)
  -h, --help                  Show this help text

Environment (used when the matching flag is omitted):
  ACCESS_TOKEN    (required) Console access token (alias: BEARER_TOKEN)
  ACCOUNT_ID      (required) Account / organization ID (alias: ORG_ID)
  AGENT_ID        (required) Console agent ID
  CONSOLE_API     API host (alias: API_HOST)

Example:
  source ../00-authentication/env.sh   # then refresh ACCESS_TOKEN
  $0
  $0 --provider ONTAP_S3
  $0 --json | jq '.[] | {provider, credential, buckets: (.buckets | length)}'
EOF
    exit 1
}

print_message() {
    echo -e "${1}${2}${NC}" >&2
}

ONLY_PROVIDER=""
AWS_ACCOUNT_ID=""
AZ_SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-${AZURE_SUBSCRIPTION_ID:-}}"
AZ_SUBSCRIPTION_NAME=""
AZ_RESOURCE_GROUP=""
DEBUG="false"
AS_JSON="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        --provider)    ONLY_PROVIDER="${2:?missing value for $1}"; shift 2 ;;
        --aws-account-id) AWS_ACCOUNT_ID="${2:?missing value for $1}"; shift 2 ;;
        --subscription-id)   AZ_SUBSCRIPTION_ID="${2:?missing value for $1}"; shift 2 ;;
        --subscription-name) AZ_SUBSCRIPTION_NAME="${2:?missing value for $1}"; shift 2 ;;
        --resource-group)    AZ_RESOURCE_GROUP="${2:?missing value for $1}"; shift 2 ;;
        --debug)       DEBUG="true"; shift ;;
        --json)        AS_JSON="true"; shift ;;
        --account-id|--org-id) ACCOUNT_ID="${2:?missing value for $1}"; shift 2 ;;
        --agent-id)    AGENT_ID="${2:?missing value for $1}"; shift 2 ;;
        --api-host)    CONSOLE_API="${2:?missing value for $1}"; shift 2 ;;
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

case "$ONLY_PROVIDER" in
    ""|AWS|AZURE|ONTAP_S3|SGWS|S3_COMPATIBLE) ;;
    *) print_message "$RED" "Error: --provider must be AWS, AZURE, ONTAP_S3, SGWS or S3_COMPATIBLE."; exit 1 ;;
esac

require_env ACCESS_TOKEN ACCOUNT_ID AGENT_ID

BASE="/backup-recovery/organizations/${ACCOUNT_ID}/v1"
LIST_OF='(if type == "array" then . else (.items // .buckets // .records // []) end)'

# Accumulated result: [{provider, credential, buckets: [...], error}]
RESULTS='[]'

add_result() { # provider credential buckets-json error
    RESULTS=$(echo "$RESULTS" | jq -c \
        --arg p "$1" --arg c "$2" --argjson b "$3" --arg e "$4" \
        '. + [{provider: $p, credential: (if $c == "" then null else $c end),
               buckets: $b, error: (if $e == "" then null else $e end)}]')
}

# GET a path below CONSOLE_API with the headers the Console UI sends to the
# account-level endpoints (they want X-Account-Id, which api_get does not send).
console_get() {
    curl -sS --fail-with-body "${CONSOLE_API}$1" \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" -H "Accept: application/json" \
        -H "X-Account-Id: ${ACCOUNT_ID}" -H "X-Agent-Id: ${AGENT_ID}"
}

# The reason for the last failed call (curl's HTTP error line plus the API's
# message) goes to this file, because the calls run in command substitutions.
ERR_FILE=$(mktemp)
trap 'rm -f "$ERR_FILE"' EXIT

# "<prefix>: <reason>" for add_result, from the last failed call.
fail_text() { # prefix
    local reason
    reason=$(tr '\n' ' ' < "$ERR_FILE" | sed -e 's/curl: ([0-9]*) //' -e 's/  */ /g' | cut -c1-240)
    echo "$1${reason:+: $reason}"
}

# Query one object-storage list. Prints the bucket array as JSON, or returns 1.
fetch_buckets() { # provider [extra query, e.g. credential-id=<id>]
    local query="provider=$1" body
    [ -n "${2:-}" ] && query="${query}&$2"
    : > "$ERR_FILE"
    [ "$DEBUG" = "true" ] && echo "GET ${CONSOLE_API}${BASE}/object-storage?${query}" >&2
    if body=$(api_get "${BASE}/object-storage?${query}" 2>"$ERR_FILE"); then
        echo "$body" | jq -c "${LIST_OF}"
    else
        { echo "$body" | jq -r '.message // .error // .detail // empty' 2>/dev/null || echo "$body" | head -c 200; } >> "$ERR_FILE" || true
        return 1
    fi
}

query_provider() { # provider
    local provider=$1 buckets err creds cred_ids
    if [ "$provider" = "AWS" ]; then
        # The API needs the AWS account ID to list S3 buckets. Query every AWS
        # account known to the Console, unless --aws-account-id limits it.
        local accounts
        if [ -n "$AWS_ACCOUNT_ID" ]; then
            accounts=$(jq -nc --arg id "$AWS_ACCOUNT_ID" '[{id: $id, name: $id}]')
        else
            : > "$ERR_FILE"
            if ! accounts=$(console_get "/occm/api/accounts/cloud-providers" 2>"$ERR_FILE"); then
                add_result "$provider" "" '[]' "$(fail_text 'AWS account list failed')"
                return
            fi
            accounts=$(echo "$accounts" | jq -c '[.awsAccounts[]? | {id: .accountId, name: "\(.accountName) (\(.accountId))"}]')
        fi
        if [ "$(echo "$accounts" | jq 'length')" -eq 0 ]; then
            add_result "$provider" "" '[]' "no AWS account found in the Console (add one, or pass --aws-account-id)"
            return
        fi
        while IFS= read -r acct; do
            local aid aname
            aid=$(echo "$acct" | jq -r '.id'); aname=$(echo "$acct" | jq -r '.name')
            if buckets=$(fetch_buckets "$provider" "aws-account-id=$aid"); then
                add_result "$provider" "$aname" "$buckets" ""
            else
                add_result "$provider" "$aname" '[]' "$(fail_text 'bucket list failed')"
            fi
        done < <(echo "$accounts" | jq -c '.[]')
        return
    fi
    if [ "$provider" = "AZURE" ]; then
        # The API needs the subscription ID and the resource group.
        local sub_id="$AZ_SUBSCRIPTION_ID" sub_enc rg_enc
        if [ -z "$sub_id" ] && [ -n "$AZ_SUBSCRIPTION_NAME" ]; then
            : > "$ERR_FILE"
            if ! sub_id=$(console_get "/account/${ACCOUNT_ID}/providers/cloudmanager_cbs/api/v1/azure/subscription" 2>"$ERR_FILE" \
                    | jq -r --arg n "$AZ_SUBSCRIPTION_NAME" '[.subscription[]? | select(.name == $n)] | .[0].id // empty'); then
                add_result "$provider" "" '[]' "$(fail_text 'Azure subscription lookup failed')"
                return
            fi
            if [ -z "$sub_id" ]; then
                add_result "$provider" "" '[]' "no Azure subscription named '$AZ_SUBSCRIPTION_NAME'"
                return
            fi
        fi
        if [ -z "$sub_id" ] || [ -z "$AZ_RESOURCE_GROUP" ]; then
            add_result "$provider" "" '[]' "needs --subscription-id (or --subscription-name) and --resource-group (see create-azure-storage-account.sh --list-subscriptions / --list-resource-groups)"
            return
        fi
        sub_enc=$(jq -rn --arg v "$sub_id" '$v | @uri'); rg_enc=$(jq -rn --arg v "$AZ_RESOURCE_GROUP" '$v | @uri')
        if buckets=$(fetch_buckets "$provider" "subscription=${sub_enc}&resource-group=${rg_enc}"); then
            add_result "$provider" "subscription $sub_id, resource group $AZ_RESOURCE_GROUP" "$buckets" ""
        else
            add_result "$provider" "subscription $sub_id, resource group $AZ_RESOURCE_GROUP" '[]' "$(fail_text 'bucket list failed')"
        fi
        return
    fi
    if [[ " ${CREDENTIAL_PROVIDERS[*]} " == *" ${provider} "* ]]; then
        : > "$ERR_FILE"
        if ! creds=$(api_get "${BASE}/credentials?provider=${provider}" 2>"$ERR_FILE"); then
            add_result "$provider" "" '[]' "$(fail_text 'credential list failed (provider not supported by this Backup and Recovery version?)')"
            return
        fi
        creds=$(echo "$creds" | jq -c "${LIST_OF} | map({id: .credential_uuid, name: .credential_name})")
        if [ "$(echo "$creds" | jq 'length')" -eq 0 ]; then
            add_result "$provider" "" '[]' ""
            return
        fi
        while IFS= read -r cred; do
            local id name
            id=$(echo "$cred" | jq -r '.id'); name=$(echo "$cred" | jq -r '.name')
            if buckets=$(fetch_buckets "$provider" "credential-id=$id"); then
                add_result "$provider" "$name" "$buckets" ""
            else
                add_result "$provider" "$name" '[]' "$(fail_text 'bucket list failed')"
            fi
        done < <(echo "$creds" | jq -c '.[]')
    else
        if buckets=$(fetch_buckets "$provider"); then
            add_result "$provider" "" "$buckets" ""
        else
            add_result "$provider" "" '[]' "$(fail_text 'bucket list failed')"
        fi
    fi
}

if [ -n "$ONLY_PROVIDER" ]; then
    PROVIDERS=("$ONLY_PROVIDER")
else
    PROVIDERS=("${DIRECT_PROVIDERS[@]}" "${CREDENTIAL_PROVIDERS[@]}")
fi

for provider in "${PROVIDERS[@]}"; do
    query_provider "$provider"
done

if [ "$AS_JSON" = "true" ]; then
    echo "$RESULTS" | jq .
    exit 0
fi

# Text output. Columns: bucket name, region and creation time ("-" when the API
# does not return the field). The object-lock column only appears for a group
# whose buckets carry an object_lock field; the API does not return it for Azure.
render_rows() { # with-lock-column (true|false)
    jq -r --argjson lock "$1" '.[]
        | [.object_store_name // "(unnamed)",
           (.region // "-"),
           ((.creation_time // "-") | sub("\\s*\\(.*\\)$"; ""))]
          + (if $lock then [(if .object_lock == null then "-" else (.object_lock | tostring) end)] else [] end)
        | @tsv'
}

TOTAL=0
echo "$RESULTS" | jq -c '.[]' | while IFS= read -r group; do
    provider=$(echo "$group" | jq -r '.provider')
    credential=$(echo "$group" | jq -r '.credential // empty')
    count=$(echo "$group" | jq '.buckets | length')
    error=$(echo "$group" | jq -r '.error // empty')
    heading="$provider"
    if [ -n "$credential" ]; then
        case "$provider" in
            AWS)   heading="$provider  (AWS account: $credential)" ;;
            AZURE) heading="$provider  ($credential)" ;;
            *)     heading="$provider  (credential: $credential)" ;;
        esac
    fi
    echo
    if [ -n "$error" ]; then
        echo -e "${YELLOW}${heading}: ${error}${NC}"
        continue
    fi
    echo "${heading}: ${count} bucket(s)"
    if [ "$count" -gt 0 ]; then
        has_lock=$(echo "$group" | jq '[.buckets[] | has("object_lock")] | any')
        {
            if [ "$has_lock" = "true" ]; then
                printf 'BUCKET\tREGION\tCREATED\tOBJECT LOCK\n'
            else
                printf 'BUCKET\tREGION\tCREATED\n'
            fi
            echo "$group" | jq '.buckets' | render_rows "$has_lock"
        } | { column -t -s "$(printf '\t')" 2>/dev/null || cat; } | sed 's/^/  /'
    fi
done

echo
echo "Total: $(echo "$RESULTS" | jq '[.[].buckets | length] | add // 0') bucket(s)"
