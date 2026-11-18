#!/usr/bin/env bash
# List the Backup and Recovery for Kubernetes protection policies of the account.
# Usage:  ./list-k8s-policies.sh            policyId, name and type, one policy per line
#         ./list-k8s-policies.sh --json     the raw policy objects
#         ./list-k8s-policies.sh -h|--help  show this help
# Read-only. Run it before creating a policy (name already taken?) and before
# deleting one (is it the right policyId?).
# Requires: ACCOUNT_ID, ACCESS_TOKEN; CONSOLE_API defaults to
# https://cloudmanager.cloud.netapp.com. AGENT_ID is sent as X-Agent-Id if set.
# Aliases: BEARER_TOKEN, ORG_ID, API_HOST.
set -euo pipefail
# shellcheck source=../../lib/bnr-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/bnr-common.sh"

as_json=false
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    --json)    as_json=true; shift ;;
    *)         echo "ERROR: unknown option $1. Usage: $0 [--json] [-h|--help]" >&2; exit 1 ;;
  esac
done

bnr_env_aliases
require_env ACCOUNT_ID ACCESS_TOKEN

args=(-sS --fail-with-body
  "${CONSOLE_API}/backup-recovery/organizations/${ACCOUNT_ID}/v1/workloads/k8s/kubernetes/policies"
  -H "Authorization: Bearer ${ACCESS_TOKEN}"
  -H "X-Account-Id: ${ACCOUNT_ID}"
  -H "Accept: application/json")
[ -z "${AGENT_ID:-}" ] || args+=(-H "X-Agent-Id: ${AGENT_ID}")

body=$(curl "${args[@]}") || {
  echo "ERROR: listing policies failed (a 401 means the access token expired: run bnr_renew_token)" >&2
  [ -z "${body:-}" ] || printf '%s\n' "$body" >&2
  exit 1
}

if $as_json; then
  printf '%s\n' "$body" | jq .
else
  printf '%s\n' "$body" | jq -r '
    (if type == "array" then . else (.items // []) end)
    | if length == 0 then "(no policies)" else .[] | [.policyId, .policyName, .backupArchitectureType] | @tsv end'
fi
