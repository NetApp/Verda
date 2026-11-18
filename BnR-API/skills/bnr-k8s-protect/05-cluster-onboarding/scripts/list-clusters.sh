#!/usr/bin/env bash
# List Kubernetes clusters discovered by NetApp Backup and Recovery.
# Usage:  ./list-clusters.sh              print id, name and state of each cluster (one JSON object each)
#         ./list-clusters.sh -h | --help  show this help
# Requires: ACCOUNT_ID, AGENT_ID, ACCESS_TOKEN; CONSOLE_API defaults to
# https://cloudmanager.cloud.netapp.com. Aliases: BEARER_TOKEN, ORG_ID, API_HOST.
set -euo pipefail
# shellcheck source=../../lib/bnr-common.sh
source "$(dirname "$0")/../../lib/bnr-common.sh"

case "${1:-}" in
  "")        ;;
  -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
  *)         echo "ERROR: unknown option $1. Usage: $0 [-h|--help]" >&2; exit 1 ;;
esac

bnr_env_aliases
require_env CONSOLE_API ACCOUNT_ID AGENT_ID ACCESS_TOKEN

curl -sS --fail-with-body --location \
  "${CONSOLE_API}/backup-recovery/organizations/${ACCOUNT_ID}/v1/workloads/k8s/clusters" \
  -H "x-agent-id: ${AGENT_ID}" \
  -H "x-account-id: ${ACCOUNT_ID}" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  | jq '.items[] | {id, name, state}'
