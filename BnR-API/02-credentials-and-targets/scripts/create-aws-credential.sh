#!/usr/bin/env bash
################################################################################
# NetApp Console API - Add AWS credentials (IAM user access keys) for Backup and
# Recovery
#
# POST /occm/api/accounts/aws
# GET  /occm/api/accounts/cloud-providers   (--list, --wait)
#
# Requires: curl, jq. Variables follow 00-authentication/env.sh.example.
# Untested: the request follows 02-credentials-and-targets/aws-s3.md and has not
# been run against a live system from this script yet.
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

Add AWS credentials (the access keys of an IAM user) to the NetApp Console, so
Backup and Recovery can create and use AWS S3 backup targets. The IAM user needs
the permissions described in the Backup and Recovery documentation.

Required:
  --name NAME                 Credential name (the AWS account name in the Console)
  --access-key-id ID          AWS access key ID (prefer the AWS_ACCESS_KEY_ID variable)
  --secret-access-key KEY     AWS secret access key (prefer the AWS_SECRET_ACCESS_KEY
                              variable: command-line arguments are visible in 'ps')

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
  --dry-run                   Print the request body (keys redacted) and exit

Lookup (print and exit, nothing is created):
  --list                      List the AWS credentials of the agent
                              (AWS account ID, name, type)

  -h, --help                  Show this help text

Environment (used when the matching flag is omitted):
  ACCESS_TOKEN            (required) Console access token (alias: BEARER_TOKEN)
  AGENT_ID                (required) Console agent ID
  CONSOLE_API             API host (alias: API_HOST)
  WORKSPACE_ID            Console workspace/project ID (aliases: TENANT_ID, PROJECT_ID)
  AWS_ACCOUNT_NAME        Same as --name
  AWS_ACCESS_KEY_ID       Same as --access-key-id
  AWS_SECRET_ACCESS_KEY   Same as --secret-access-key

  AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are also the variables the AWS CLI
  reads. Check the access key shown in the summary before you send the request.

Example:
  source ../../00-authentication/env.sh   # then refresh ACCESS_TOKEN
  export AWS_ACCESS_KEY_ID='<access_key_id>'
  export AWS_SECRET_ACCESS_KEY='<secret_access_key>'

  $0 --name <aws_account_name> --wait
EOF
    exit 1
}

print_message() {
    echo -e "$1"
}

AWS_ACCOUNT_NAME="${AWS_ACCOUNT_NAME:-}"
# The keys are passed to jq and curl through the environment and stdin, not
# through arguments, so they do not show up in 'ps'.
AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"
LIST="false"
WAIT="false"
TIMEOUT="120"
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        --name)              AWS_ACCOUNT_NAME="${2-}"; shift $(( $# > 1 ? 2 : 1 )) ;;
        --access-key-id)     AWS_ACCESS_KEY_ID="${2-}"; shift $(( $# > 1 ? 2 : 1 )) ;;
        --secret-access-key) AWS_SECRET_ACCESS_KEY="${2-}"; shift $(( $# > 1 ? 2 : 1 )) ;;
        --list)              LIST="true"; shift ;;
        --wait)              WAIT="true"; shift ;;
        --timeout)           TIMEOUT="${2:?missing value for $1}"; shift 2 ;;
        --agent-id)          AGENT_ID="${2:?missing value for $1}"; shift 2 ;;
        --workspace-id)      WORKSPACE_ID="${2:?missing value for $1}"; shift 2 ;;
        --api-host)          CONSOLE_API="${2:?missing value for $1}"; shift 2 ;;
        --dry-run)           DRY_RUN="true"; shift ;;
        -h|--help)           usage ;;
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
    api_get "$CLOUD_PROVIDERS_PATH" "$WS_HEADER" \
        | jq -r '.awsAccounts[]? | "\(.accountId)  \(.accountName)  (\(.accountType))"'
    exit 0
fi

if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || [ "$TIMEOUT" -lt 1 ]; then
    print_message "Error: --timeout must be a positive number of seconds, got '$TIMEOUT'."
    exit 1
fi

MISSING=""
[ -z "$AWS_ACCOUNT_NAME" ] && MISSING="$MISSING --name"
[ -z "$AWS_ACCESS_KEY_ID" ] && MISSING="$MISSING --access-key-id"
[ -z "$AWS_SECRET_ACCESS_KEY" ] && MISSING="$MISSING --secret-access-key"
if [ -n "$MISSING" ]; then
    print_message "Error: Missing required arguments or environment variables:${MISSING}"
    echo
    usage
fi

export AWS_ACCOUNT_NAME AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
PAYLOAD=$(jq -n '{
    accountName: env.AWS_ACCOUNT_NAME,
    providerKeys: {
        awsAccessKeys: {
            accessKey: env.AWS_ACCESS_KEY_ID,
            secretKey: env.AWS_SECRET_ACCESS_KEY
        }
    }
}')
# Show only the first four characters of the access key and none of the secret.
REDACTED_PAYLOAD=$(echo "$PAYLOAD" | jq '
    .providerKeys.awsAccessKeys.accessKey = ((.providerKeys.awsAccessKeys.accessKey | .[0:4]) + "***REDACTED***")
    | .providerKeys.awsAccessKeys.secretKey = "***REDACTED***"')

CREDENTIALS_URL="${CONSOLE_API}/occm/api/accounts/aws"

print_message "\nNetApp Console - add AWS credentials"
echo "Name:        $AWS_ACCOUNT_NAME"
echo "Access key:  ${AWS_ACCESS_KEY_ID:0:4}..."
echo "API:         $CONSOLE_API"
echo "Agent:       ${AGENT_ID:-(not set)}"
echo
print_message "Request body (keys redacted):"
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

    # Poll the credential list until the new name shows up under awsAccounts.
    print_message "Waiting up to ${TIMEOUT}s for credentials '${AWS_ACCOUNT_NAME}' to be listed..."
    DEADLINE=$((SECONDS + TIMEOUT))
    while true; do
        if api_get "$CLOUD_PROVIDERS_PATH" "$WS_HEADER" 2>/dev/null | jq -e --arg name "$AWS_ACCOUNT_NAME" \
            '[.awsAccounts[]? | select(.accountName == $name)] | length > 0' >/dev/null 2>&1; then
            print_message "Credentials '${AWS_ACCOUNT_NAME}' are listed."
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
