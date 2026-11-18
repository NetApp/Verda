#!/usr/bin/env bash
################################################################################
# NetApp Console API - Add Azure credentials (service principal) for Backup and
# Recovery
#
# POST /occm/api/accounts/azure
# GET  /occm/api/accounts/cloud-providers   (--list, --wait)
#
# Requires: curl, jq. Variables follow 00-authentication/env.sh.example.
# Tested against a live system on 2026-11-11 (create and --list).
################################################################################
set -euo pipefail
# shellcheck source=../../lib/bnr-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/bnr-common.sh"

# Connection settings. No defaults for IDs: set them via env.sh or flags.
AGENT_ID="${AGENT_ID:-}"
WORKSPACE_ID="${WORKSPACE_ID:-${TENANT_ID:-${PROJECT_ID:-}}}"

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Add Azure credentials (a service principal) to the NetApp Console, so Backup and
Recovery can discover and create Azure Blob backup targets. The service
principal needs the permissions described in the Console documentation.

Required:
  --name NAME                 Credential name
  --client-id ID              Application (client) ID of the service principal
  --client-secret SECRET      Client secret value (prefer the AZURE_CLIENT_SECRET
                              variable: command-line arguments are visible in 'ps')
  --tenant-id ID              Directory (tenant) ID

Optional:
  --agent-id ID               Console agent ID
  --workspace-id ID           Console workspace/project ID, sent as
                              x-netapp-workspace-id (optional)
  --api-host URL              API host (default: CONSOLE_API, else
                              https://cloudmanager.cloud.netapp.com)
  --wait                      After the request is accepted, poll the credential
                              list until the new credential appears. Exit 0 when
                              it is listed, 1 on timeout.
  --timeout SECONDS           Maximum time for --wait (default: 120)
  --dry-run                   Print the request body (secret redacted) and exit

Lookup (print and exit, nothing is created):
  --list                      List the cloud provider credentials of the agent
                              (group, name, ID, type)

  -h, --help                  Show this help text

Environment (used when the matching flag is omitted):
  ACCESS_TOKEN           (required) Console access token (alias: BEARER_TOKEN)
  AGENT_ID               (required) Console agent ID
  CONSOLE_API            API host (alias: API_HOST)
  WORKSPACE_ID           Console workspace/project ID (aliases: TENANT_ID, PROJECT_ID)
  AZURE_CREDENTIAL_NAME  Same as --name
  AZURE_CLIENT_ID        Same as --client-id
  AZURE_CLIENT_SECRET    Same as --client-secret
  AZURE_TENANT_ID        Same as --tenant-id

Example:
  source ../../00-authentication/env.sh   # then refresh ACCESS_TOKEN
  export AZURE_CLIENT_SECRET='<client_secret>'

  $0 --name <credential_name> --client-id <application_client_id> \\
     --tenant-id <directory_tenant_id> --wait
EOF
    exit 1
}

print_message() {
    echo -e "$1"
}

AZURE_CREDENTIAL_NAME="${AZURE_CREDENTIAL_NAME:-}"
AZURE_CLIENT_ID="${AZURE_CLIENT_ID:-}"
# The secret is passed to jq and curl through the environment and stdin, not
# through arguments, so it does not show up in 'ps'.
AZURE_CLIENT_SECRET="${AZURE_CLIENT_SECRET:-}"
AZURE_TENANT_ID="${AZURE_TENANT_ID:-}"
LIST="false"
WAIT="false"
TIMEOUT="120"
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        --name)          AZURE_CREDENTIAL_NAME="${2-}"; shift $(( $# > 1 ? 2 : 1 )) ;;
        --client-id)     AZURE_CLIENT_ID="${2-}"; shift $(( $# > 1 ? 2 : 1 )) ;;
        --client-secret) AZURE_CLIENT_SECRET="${2-}"; shift $(( $# > 1 ? 2 : 1 )) ;;
        --tenant-id)     AZURE_TENANT_ID="${2-}"; shift $(( $# > 1 ? 2 : 1 )) ;;
        --list)          LIST="true"; shift ;;
        --wait)          WAIT="true"; shift ;;
        --timeout)       TIMEOUT="${2:?missing value for $1}"; shift 2 ;;
        --agent-id)      AGENT_ID="${2:?missing value for $1}"; shift 2 ;;
        --workspace-id)  WORKSPACE_ID="${2:?missing value for $1}"; shift 2 ;;
        --api-host)      CONSOLE_API="${2:?missing value for $1}"; shift 2 ;;
        --dry-run)       DRY_RUN="true"; shift ;;
        -h|--help)       usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

# BEARER_TOKEN, ORG_ID and API_HOST are accepted as aliases; the host defaults to the Console API.
bnr_env_aliases

for command in jq curl; do
    if ! command -v "$command" >/dev/null 2>&1; then
        print_message "Error: $command is required."
        exit 1
    fi
done

# --dry-run only prints the body, so it needs no token or agent.
if [ "$DRY_RUN" != "true" ]; then
    require_env ACCESS_TOKEN AGENT_ID
fi

# Header the Console UI sends when a workspace/project is known (empty otherwise).
WS_HEADER=""
[ -z "$WORKSPACE_ID" ] || WS_HEADER="x-netapp-workspace-id: ${WORKSPACE_ID}"

CLOUD_PROVIDERS_PATH="/occm/api/accounts/cloud-providers"

if [ "$LIST" = "true" ]; then
    require_env ACCESS_TOKEN AGENT_ID
    # The response groups the credentials by provider (for example awsAccounts);
    # print the group name next to each credential.
    api_get "$CLOUD_PROVIDERS_PATH" "$WS_HEADER" | jq -r '
        to_entries[] | select(.value | type == "array") | .key as $group
        | .value[] | select(type == "object" and has("accountName"))
        | "\($group)  \(.accountName)  \(.accountId // "")  \(.accountType // "")"'
    exit 0
fi

if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || [ "$TIMEOUT" -lt 1 ]; then
    print_message "Error: --timeout must be a positive number of seconds, got '$TIMEOUT'."
    exit 1
fi

MISSING=""
[ -z "$AZURE_CREDENTIAL_NAME" ] && MISSING="$MISSING --name"
[ -z "$AZURE_CLIENT_ID" ] && MISSING="$MISSING --client-id"
[ -z "$AZURE_CLIENT_SECRET" ] && MISSING="$MISSING --client-secret"
[ -z "$AZURE_TENANT_ID" ] && MISSING="$MISSING --tenant-id"
if [ -n "$MISSING" ]; then
    print_message "Error: Missing required arguments or environment variables:${MISSING}"
    echo
    usage
fi

export AZURE_CREDENTIAL_NAME AZURE_CLIENT_ID AZURE_CLIENT_SECRET AZURE_TENANT_ID
PAYLOAD=$(jq -n '{
    accountName: env.AZURE_CREDENTIAL_NAME,
    providerKeys: {
        applicationId: env.AZURE_CLIENT_ID,
        applicationKey: env.AZURE_CLIENT_SECRET,
        tenantId: env.AZURE_TENANT_ID
    }
}')
REDACTED_PAYLOAD=$(echo "$PAYLOAD" | jq '.providerKeys.applicationKey = "***REDACTED***"')

CREDENTIALS_URL="${CONSOLE_API}/occm/api/accounts/azure"

print_message "\nNetApp Console - add Azure credentials"
echo "Name:       $AZURE_CREDENTIAL_NAME"
echo "Client ID:  $AZURE_CLIENT_ID"
echo "Tenant ID:  $AZURE_TENANT_ID"
echo "API:        $CONSOLE_API"
echo "Agent:      ${AGENT_ID:-(not set)}"
echo
print_message "Request body (secret redacted):"
echo "$REDACTED_PAYLOAD" | jq .

if [ "$DRY_RUN" = "true" ]; then
    print_message "\nDry run. No API call was made."
    exit 0
fi

print_message "\nAdding credentials at ${CREDENTIALS_URL}"

BODY_FILE=$(mktemp)
trap 'rm -f "$BODY_FILE"' EXIT
POST_ARGS=(-sS -o "$BODY_FILE" -w '%{http_code}' -X POST "$CREDENTIALS_URL"
    -H "Authorization: Bearer $ACCESS_TOKEN"
    -H "Content-Type: application/json"
    -H "Accept: application/json"
    -H "x-agent-id: $AGENT_ID"
    --data-binary @-)
[ -z "$WS_HEADER" ] || POST_ARGS+=(-H "$WS_HEADER")

# The body (with the secret) goes through stdin, not the command line.
HTTP_STATUS=$(printf '%s' "$PAYLOAD" | curl "${POST_ARGS[@]}") || HTTP_STATUS=""

if [ -n "$HTTP_STATUS" ] && [ "$HTTP_STATUS" -ge 200 ] && [ "$HTTP_STATUS" -lt 300 ]; then
    print_message "Credential request accepted."
    print_message "HTTP Status: $HTTP_STATUS"
    echo
    jq . "$BODY_FILE" 2>/dev/null || cat "$BODY_FILE"
    echo

    if [ "$WAIT" != "true" ]; then
        echo "Check that the credentials are listed with:  $0 --list"
        echo "Or add --wait to poll for them."
        exit 0
    fi

    # Poll the credential list until the new name shows up. The list is grouped by
    # provider, so look for the name anywhere in it.
    print_message "Waiting up to ${TIMEOUT}s for credentials '${AZURE_CREDENTIAL_NAME}' to be listed..."
    DEADLINE=$((SECONDS + TIMEOUT))
    while true; do
        if api_get "$CLOUD_PROVIDERS_PATH" "$WS_HEADER" 2>/dev/null | jq -e --arg name "$AZURE_CREDENTIAL_NAME" \
            '[.. | objects | select((.accountName? // "") == $name)] | length > 0' >/dev/null 2>&1; then
            print_message "Credentials '${AZURE_CREDENTIAL_NAME}' are listed."
            exit 0
        fi
        if [ "$SECONDS" -ge "$DEADLINE" ]; then
            print_message "Timed out after ${TIMEOUT}s. The credentials may still be processed, or the request failed."
            echo "Check later with:  $0 --list"
            exit 1
        fi
        sleep 5
    done
fi

print_message "Failed to add credentials."
print_message "HTTP Status: ${HTTP_STATUS:-none}"
echo
jq . "$BODY_FILE" 2>/dev/null || cat "$BODY_FILE"
exit 1
