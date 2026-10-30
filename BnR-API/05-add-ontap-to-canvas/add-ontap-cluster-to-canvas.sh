#!/usr/bin/env bash
################################################################################
# NetApp Console API - Add an on-premises ONTAP cluster to the canvas
#
# POST /occm/api/onprem/working-environments
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
# ACCESS_TOKEN / CONSOLE_API / WORKSPACE_ID are the names used in the other
# sections; BEARER_TOKEN / API_HOST / TENANT_ID are accepted as aliases.
ACCESS_TOKEN="${ACCESS_TOKEN:-${BEARER_TOKEN:-}}"
CONSOLE_API="${CONSOLE_API:-${API_HOST:-https://cloudmanager.cloud.netapp.com}}"
ORG_ID="${ORG_ID:-}"
ACCOUNT_ID="${ACCOUNT_ID:-}"
AGENT_ID="${AGENT_ID:-}"
RESPONSE_FILE="${RESPONSE_FILE:-/tmp/netapp_add_ontap_cluster_response.json}"

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Add an on-premises ONTAP cluster to the NetApp Console storage canvas.

Required:
  --cluster-address ADDRESS   ONTAP cluster-management address
  --cluster-password PASSWORD ONTAP cluster-user password
                              (prefer the CLUSTER_PASSWORD variable: command-line
                              arguments are visible to other users in 'ps')

Optional:
  --cluster-user-name USER    ONTAP cluster user name (default: admin)
  --name NAME                 Canvas working-environment name
                              (default: cluster address)
  --tenant-id ID              Console workspace/project ID
  --project-name NAME         Console project name. Used to look up the
                              workspace ID when --tenant-id is omitted.
  --account-id ID             Account (organization) ID
  --org-id ID                 Alias for --account-id
  --agent-id ID               Console agent ID
  --api-host URL              API host (default: CONSOLE_API, else
                              https://cloudmanager.cloud.netapp.com)
  --response-file FILE        Save the API response here
  --dry-run                   Print a redacted request body and exit
  -h, --help                  Show this help text

Environment (used when the matching flag is omitted):
  ACCESS_TOKEN       (required) Console access token (alias: BEARER_TOKEN)
  ACCOUNT_ID         (required) Account / organization ID (alias: ORG_ID)
  AGENT_ID           (required) Console agent ID
  CONSOLE_API        API host (alias: API_HOST)
  CLUSTER_ADDRESS    ONTAP cluster-management address
  CLUSTER_PASSWORD   ONTAP cluster-user password
  CLUSTER_USER_NAME  ONTAP cluster user name (default: admin)
  CLUSTER_NAME       Canvas working-environment name (default: CLUSTER_ADDRESS)
  WORKSPACE_ID       Console workspace/project ID (aliases: TENANT_ID, PROJECT_ID)
  PROJECT_NAME       Console project name used to look up the workspace ID
  RESPONSE_FILE      Where to save the API response

Example:
  source ../00-authentication/env.sh   # then refresh ACCESS_TOKEN (see 00-authentication)
  export PROJECT_NAME='<project_name>'
  export CLUSTER_PASSWORD='<cluster_password>'

  $0 --cluster-address <cluster_mgmt_ip_or_fqdn>
EOF
    exit 1
}

print_message() {
    echo -e "${1}${2}${NC}"
}

CLUSTER_ADDRESS="${CLUSTER_ADDRESS:-}"
CLUSTER_PASSWORD="${CLUSTER_PASSWORD:-}"
CLUSTER_USER_NAME="${CLUSTER_USER_NAME:-admin}"
CLUSTER_NAME="${CLUSTER_NAME:-}"
TENANT_ID="${TENANT_ID:-${PROJECT_ID:-${WORKSPACE_ID:-}}}"
PROJECT_NAME="${PROJECT_NAME:-}"
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        --cluster-address)   CLUSTER_ADDRESS="${2:?missing value for $1}"; shift 2 ;;
        --cluster-password)  CLUSTER_PASSWORD="${2:?missing value for $1}"; shift 2 ;;
        --cluster-user-name) CLUSTER_USER_NAME="${2:?missing value for $1}"; shift 2 ;;
        --name)              CLUSTER_NAME="${2:?missing value for $1}"; shift 2 ;;
        --tenant-id)         TENANT_ID="${2:?missing value for $1}"; shift 2 ;;
        --project-name)      PROJECT_NAME="${2:?missing value for $1}"; shift 2 ;;
        --org-id)            ORG_ID="${2:?missing value for $1}"; shift 2 ;;
        --account-id)        ACCOUNT_ID="${2:?missing value for $1}"; shift 2 ;;
        --agent-id)          AGENT_ID="${2:?missing value for $1}"; shift 2 ;;
        --api-host)          CONSOLE_API="${2:?missing value for $1}"; shift 2 ;;
        --response-file)     RESPONSE_FILE="${2:?missing value for $1}"; shift 2 ;;
        --dry-run)           DRY_RUN="true"; shift ;;
        -h|--help)           usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

[ -z "$ACCOUNT_ID" ] && ACCOUNT_ID="$ORG_ID"
[ -z "$CLUSTER_NAME" ] && CLUSTER_NAME="$CLUSTER_ADDRESS"
CONSOLE_API="${CONSOLE_API%/}"

for command in jq curl; do
    if ! command -v "$command" >/dev/null 2>&1; then
        print_message "$RED" "Error: $command is required."
        exit 1
    fi
done

# ACCOUNT_ID may come from --org-id.
require_env ACCESS_TOKEN ACCOUNT_ID AGENT_ID

MISSING=""
[ -z "$CLUSTER_ADDRESS" ] && MISSING="$MISSING --cluster-address"
[ -z "$CLUSTER_PASSWORD" ] && MISSING="$MISSING --cluster-password"
[ -z "$CLUSTER_USER_NAME" ] && MISSING="$MISSING --cluster-user-name"
if [ -n "$MISSING" ]; then
    print_message "$RED" "Error: Missing required arguments or environment variables:${MISSING}"
    exit 1
fi

if [ -z "$TENANT_ID" ]; then
    WORKSPACES_URL="${CONSOLE_API}/tenancy/account/${ACCOUNT_ID}/workspace"
    print_message "$BLUE" "Resolving Console tenant from account '$ACCOUNT_ID'..."

    WORKSPACES_FILE=$(mktemp)
    trap 'rm -f "$WORKSPACES_FILE"' EXIT
    WORKSPACES_STATUS=$(curl -sS -o "$WORKSPACES_FILE" -w '%{http_code}' \
        -X GET "$WORKSPACES_URL" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Accept: application/json")
    WORKSPACES_RESPONSE=$(cat "$WORKSPACES_FILE")

    if [ "$WORKSPACES_STATUS" -lt 200 ] || [ "$WORKSPACES_STATUS" -ge 300 ]; then
        print_message "$RED" "Error: Could not retrieve Console workspaces."
        print_message "$RED" "HTTP Status: $WORKSPACES_STATUS"
        print_message "$YELLOW" "Lookup: $WORKSPACES_URL"
        echo "$WORKSPACES_RESPONSE" | jq . 2>/dev/null || echo "$WORKSPACES_RESPONSE"
        exit 1
    fi

    if [ -n "$PROJECT_NAME" ]; then
        TENANT_ID=$(echo "$WORKSPACES_RESPONSE" | jq -r --arg project "$PROJECT_NAME" '
            (if type == "array" then . else (.items // []) end)
            | map(select((.workspaceName // .name) == $project))
            | map(.workspacePublicId // .publicId // .id)
            | unique
            | if length == 1 then .[0] else empty end
        ')
        if [ -z "$TENANT_ID" ]; then
            print_message "$RED" "Error: Could not find one workspace named '$PROJECT_NAME'."
        fi
    else
        TENANT_ID=$(echo "$WORKSPACES_RESPONSE" | jq -r --arg agent "$AGENT_ID" '
            (if type == "array" then . else (.items // []) end)
            | map(select(any(
                (.associatedAgents // [])[];
                (. == $agent) or (.agentId? == $agent) or (.agentID? == $agent) or (.id? == $agent)
              )))
            | map(.workspacePublicId // .publicId // .id)
            | unique
            | if length == 1 then .[0] else empty end
        ')
        if [ -z "$TENANT_ID" ]; then
            print_message "$RED" "Error: Agent '$AGENT_ID' is not associated with exactly one Console workspace."
            print_message "$YELLOW" "Set PROJECT_NAME to the project selected in the Console, or set WORKSPACE_ID."
        fi
    fi

    if [ -z "$TENANT_ID" ]; then
        print_message "$YELLOW" "Available workspaces:"
        echo "$WORKSPACES_RESPONSE" | jq -r '
          (if type == "array" then . else (.items // []) end)[]
          | "  \(.workspaceName // .name // "(unnamed)") (\(.workspacePublicId // .publicId // .id // "no id"))"
        ' 2>/dev/null || echo "$WORKSPACES_RESPONSE"
        exit 1
    fi

    print_message "$GREEN" "Resolved tenant ID: $TENANT_ID"
fi

PAYLOAD=$(jq -n \
    --arg tenantId "$TENANT_ID" \
    --arg name "$CLUSTER_NAME" \
    --arg clusterAddress "$CLUSTER_ADDRESS" \
    --arg clusterPassword "$CLUSTER_PASSWORD" \
    --arg clusterUserName "$CLUSTER_USER_NAME" \
    '{
        tenantId: $tenantId,
        name: $name,
        clusterAddress: $clusterAddress,
        clusterPassword: $clusterPassword,
        clusterUserName: $clusterUserName,
        location: "ON_PREM"
    }')

WORKING_ENVIRONMENTS_URL="${CONSOLE_API}/occm/api/onprem/working-environments"
REDACTED_PAYLOAD=$(echo "$PAYLOAD" | jq '.clusterPassword = "***REDACTED***"')

print_message "$GREEN" "\nNetApp Console - Add ONTAP cluster to storage canvas"
echo "Cluster address: $CLUSTER_ADDRESS"
echo "Cluster user:    $CLUSTER_USER_NAME"
echo "Canvas name:     $CLUSTER_NAME"
echo "Tenant ID:       $TENANT_ID"
echo "API:             $CONSOLE_API"
echo
print_message "$YELLOW" "Request body (password redacted):"
echo "$REDACTED_PAYLOAD" | jq .

if [ "$DRY_RUN" = "true" ]; then
    print_message "$YELLOW" "\nDry run. No API call was made."
    exit 0
fi

print_message "$BLUE" "\nAdding ONTAP cluster at ${WORKING_ENVIRONMENTS_URL}"
BODY_FILE=$(mktemp)
HTTP_STATUS=$(curl -sS -o "$BODY_FILE" -w '%{http_code}' -X POST "$WORKING_ENVIRONMENTS_URL" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -H "x-account-id: $ACCOUNT_ID" \
    -H "x-agent-id: $AGENT_ID" \
    -d "$PAYLOAD")

mv "$BODY_FILE" "$RESPONSE_FILE"

if [ "$HTTP_STATUS" -ge 200 ] && [ "$HTTP_STATUS" -lt 300 ]; then
    print_message "$GREEN" "ONTAP cluster add request accepted."
    print_message "$GREEN" "HTTP Status: $HTTP_STATUS"
    echo "Response saved to: $RESPONSE_FILE"
    echo
    jq . "$RESPONSE_FILE" 2>/dev/null || cat "$RESPONSE_FILE"
    exit 0
fi

print_message "$RED" "Failed to add ONTAP cluster."
print_message "$RED" "HTTP Status: ${HTTP_STATUS:-none}"
echo "Response saved to: $RESPONSE_FILE"
echo
jq . "$RESPONSE_FILE" 2>/dev/null || cat "$RESPONSE_FILE"
exit 1
