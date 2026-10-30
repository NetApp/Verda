#!/usr/bin/env bash
# Delete a Backup and Recovery for Kubernetes protection policy by its policy ID.
#
# Usage: delete-k8s-policy.sh <policyId> [--yes]
#   <policyId>   the policyId returned when the policy was created (a UUID)
#   --yes, -y    do not ask for confirmation
#
# Required environment variables:
#   ACCOUNT_ID     NetApp Console organization ID (UUID) used in the API URL and X-Account-Id header
#   ACCESS_TOKEN   Bearer access token generated from your refresh token
# Optional environment variables:
#   CONSOLE_API    API base URL (https://cloudmanager.cloud.netapp.com)
#   AGENT_ID       Console agent ID; sent as X-Agent-Id if set
#
# Endpoint: DELETE .../v1/workloads/k8s/kubernetes/policies/<policyId> (verified live: HTTP 204).
# A policy that is still assigned to protected applications may be refused by the server.
set -euo pipefail
# shellcheck source=../../lib/bnr-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/bnr-common.sh"

policy_id=""; assume_yes=false
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    -y|--yes)  assume_yes=true; shift ;;
    -*)        echo "ERROR: unknown option $1" >&2; exit 1 ;;
    *)         [ -z "$policy_id" ] || { echo "ERROR: only one policyId is allowed" >&2; exit 1; }
               policy_id="$1"; shift ;;
  esac
done
[ -n "$policy_id" ] || { echo "ERROR: policyId is required. Usage: $0 <policyId> [--yes]" >&2; exit 1; }
[[ "$policy_id" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] \
  || { echo "ERROR: '$policy_id' is not a policy ID (expected a UUID such as 4b400c55-40ee-4920-b193-e36c6900cff7)" >&2; exit 1; }

require_env ACCOUNT_ID ACCESS_TOKEN

if ! $assume_yes; then
  printf 'Delete protection policy %s? [y/N] ' "$policy_id" >&2
  read -r answer
  case "$answer" in y|Y|yes|YES) ;; *) echo "Aborted." >&2; exit 1 ;; esac
fi

args=(-s -w '\n%{http_code}' -X DELETE
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "X-Account-Id: $ACCOUNT_ID" -H 'Accept: application/json')
[ -z "${AGENT_ID:-}" ] || args+=(-H "X-Agent-Id: $AGENT_ID")

out=$(curl "${args[@]}" "${CONSOLE_API:-https://cloudmanager.cloud.netapp.com}/backup-recovery/organizations/$ACCOUNT_ID/v1/workloads/k8s/kubernetes/policies/$policy_id") \
  || { echo "ERROR: request failed" >&2; exit 1; }
code="${out##*$'\n'}"; body="${out%$'\n'*}"
if [[ "$code" =~ ^2 ]]; then
  echo "Deleted policy $policy_id (HTTP $code)"
  [ -z "$body" ] || printf '%s\n' "$body" | jq . 2>/dev/null || printf '%s\n' "$body"
else
  echo "ERROR: DELETE returned HTTP $code" >&2
  [ -z "$body" ] || { printf '%s\n' "$body" | jq . 2>/dev/null || printf '%s\n' "$body"; } >&2
  exit 1
fi
