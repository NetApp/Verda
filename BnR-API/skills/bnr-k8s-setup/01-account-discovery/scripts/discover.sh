#!/usr/bin/env bash
# List the accounts, workspaces (projects) and associated agents your user can see,
# so you can pick ACCOUNT_ID, WORKSPACE_ID and AGENT_ID.
#
# Usage:
#   ./discover.sh                          list accounts; if ACCOUNT_ID is set, also its workspaces
#   ./discover.sh --account <id|name>      list the workspaces of that account
#   ./discover.sh --account <id|name> --workspace <id|name> --exports
#                                          print export lines for the selection
#
# Options:
#   --account <id|name>    account to use (default: ACCOUNT_ID)
#   --workspace <id|name>  workspace to use (default: WORKSPACE_ID); needed for --exports
#   --exports              print only `export` lines on stdout (tables go to stderr);
#                          use:  eval "$(./discover.sh --account X --workspace Y --exports)"
#   -h, --help             show this help
#
# Requires: ACCESS_TOKEN (see 00-authentication); CONSOLE_API defaults to
# https://cloudmanager.cloud.netapp.com. Aliases: BEARER_TOKEN, API_HOST.
# AGENT_ID is optional; if set, it is marked with * in the agent list.
# The agent IP (AGENT_IP) cannot be discovered through the API.
set -euo pipefail
# shellcheck source=../../lib/bnr-common.sh
source "$(dirname "$0")/../../lib/bnr-common.sh"
bnr_env_aliases

account_sel="${ACCOUNT_ID:-}"
workspace_sel="${WORKSPACE_ID:-}"
exports=0

while [ $# -gt 0 ]; do
  case "$1" in
    --account)   account_sel="${2:?--account needs a value}"; shift 2 ;;
    --workspace) workspace_sel="${2:?--workspace needs a value}"; shift 2 ;;
    --exports)   exports=1; shift ;;
    -h|--help)   sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "ERROR: unknown option: $1 (try -h)" >&2; exit 1 ;;
  esac
done

require_env CONSOLE_API ACCESS_TOKEN

# Human-readable output: stdout normally, stderr with --exports.
say() { if [ "${exports}" -eq 1 ]; then printf '%s\n' "$*" >&2; else printf '%s\n' "$*"; fi; }
table() { if command -v column >/dev/null 2>&1; then column -t -s $'\t'; else cat; fi; }
show() { if [ "${exports}" -eq 1 ]; then table >&2; else table; fi; }

# GET a tenancy path (no agent header needed here).
tenancy_get() {
  local body
  body=$(curl -sS --fail-with-body "${CONSOLE_API}$1" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Accept: application/json") || {
    echo "ERROR: GET ${CONSOLE_API}$1 failed (a 401 means the access token expired: run bnr_renew_token)" >&2
    [ -z "${body}" ] || printf '%s\n' "${body}" >&2
    exit 1
  }
  printf '%s' "${body}"
}

# ---- accounts ----
accounts=$(tenancy_get "/tenancy/account")
say "Accounts:"
jq -r --arg sel "${account_sel}" '
  (["  NAME", "ACCOUNT_ID"] | @tsv),
  (.[] | [ (if .accountPublicId == $sel or .accountName == $sel then "* " else "  " end) + .accountName,
           .accountPublicId ] | @tsv)' <<<"${accounts}" | show

if [ -z "${account_sel}" ]; then
  say ""
  say "Pick an account and re-run with --account <id|name> to see its workspaces."
  exit 0
fi

# Resolve name or ID to exactly one account.
matches=$(jq -c --arg sel "${account_sel}" \
  '[.[] | select(.accountPublicId == $sel or .accountName == $sel)]' <<<"${accounts}")
case "$(jq 'length' <<<"${matches}")" in
  0) echo "ERROR: no account matches '${account_sel}'" >&2; exit 1 ;;
  1) ;;
  *) echo "ERROR: several accounts are named '${account_sel}'; use the ID" >&2; exit 1 ;;
esac
account_id=$(jq -r '.[0].accountPublicId' <<<"${matches}")

uuid_re='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
if ! [[ "${account_id}" =~ ${uuid_re} ]]; then
  say ""
  say "WARNING: '${account_id}' is not a UUID. Backup and Recovery calls (section 06) document the"
  say "organization ID as a UUID; this older ID format is untested."
fi

# ---- workspaces and agents ----
workspaces=$(tenancy_get "/tenancy/account/${account_id}/workspace")
say ""
say "Workspaces (projects) of ${account_id}:"
jq -r --arg ws "${workspace_sel}" --arg agent "${AGENT_ID:-}" '
  (["  NAME", "WORKSPACE_ID", "ASSOCIATED AGENTS (* = AGENT_ID)"] | @tsv),
  (.[] | [ (if .workspacePublicId == $ws or .workspaceName == $ws then "* " else "  " end) + .workspaceName,
           .workspacePublicId,
           (if (.associatedAgents | length) == 0 then "(none)"
            else (.associatedAgents | map(if . == $agent then . + " *" else . end) | join(", ")) end) ]
         | @tsv)' <<<"${workspaces}" | show

if [ -n "${AGENT_ID:-}" ]; then
  if jq -e --arg a "${AGENT_ID}" 'any(.[]; (.associatedAgents // []) | index($a))' <<<"${workspaces}" >/dev/null; then
    say ""
    say "AGENT_ID is associated with a workspace in this account."
  else
    say ""
    say "WARNING: AGENT_ID is not associated with any workspace in this account."
    say "Associate it in the Console UI (see README, 'Check that the agent is associated')."
  fi
fi

# ---- export lines ----
if [ "${exports}" -eq 1 ]; then
  [ -n "${workspace_sel}" ] || { echo "ERROR: --exports needs --workspace (or WORKSPACE_ID)" >&2; exit 1; }
  ws=$(jq -c --arg sel "${workspace_sel}" \
    '[.[] | select(.workspacePublicId == $sel or .workspaceName == $sel)]' <<<"${workspaces}")
  case "$(jq 'length' <<<"${ws}")" in
    0) echo "ERROR: no workspace matches '${workspace_sel}' in this account" >&2; exit 1 ;;
    1) ;;
    *) echo "ERROR: several workspaces are named '${workspace_sel}'; use the ID" >&2; exit 1 ;;
  esac
  printf 'export ACCOUNT_ID=%q\n' "${account_id}"
  printf 'export WORKSPACE_ID=%q\n' "$(jq -r '.[0].workspacePublicId' <<<"${ws}")"
  case "$(jq '.[0].associatedAgents | length' <<<"${ws}")" in
    0) echo "WARNING: this workspace has no associated agent" >&2 ;;
    1) printf 'export AGENT_ID=%q\n' "$(jq -r '.[0].associatedAgents[0]' <<<"${ws}")" ;;
    *) echo "NOTE: several agents are associated; AGENT_ID not exported. Set it yourself." >&2 ;;
  esac
fi
