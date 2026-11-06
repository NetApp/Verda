#!/usr/bin/env bash
# List Kubernetes clusters discovered by NetApp Backup and Recovery.
# Requires: CONSOLE_API, ACCOUNT_ID, AGENT_ID, ACCESS_TOKEN
set -euo pipefail
# shellcheck source=../../lib/bnr-common.sh
source "$(dirname "$0")/../../lib/bnr-common.sh"
require_env CONSOLE_API ACCOUNT_ID AGENT_ID ACCESS_TOKEN

curl -sS --fail-with-body --location \
  "${CONSOLE_API}/backup-recovery/organizations/${ACCOUNT_ID}/v1/workloads/k8s/clusters" \
  -H "x-agent-id: ${AGENT_ID}" \
  -H "x-account-id: ${ACCOUNT_ID}" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  | jq '.items[] | {id, name, state}'
