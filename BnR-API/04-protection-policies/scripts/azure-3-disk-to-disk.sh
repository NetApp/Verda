#!/usr/bin/env bash
# Disk-to-disk protection policy (AZURE backup target)
#
# Usage: azure-3-disk-to-disk.sh --policy-name <name>     (mandatory; an exported POLICY_NAME is ignored)
#
# Required environment variables (the script aborts if any is unset or empty):
#   ACCOUNT_ID                  NetApp Console organization/account ID used in the API URL and X-Account-Id header
#   AGENT_ID                    Console agent ID (agentID in the request body)
#   ACCESS_TOKEN                Bearer access token generated from your refresh token
#   AZURE_SUBSCRIPTION_ID       Azure subscription ID of the backup target
#   AZURE_RG                    Azure resource group of the backup target
#   AZURE_STORAGE_ACCOUNT       Azure storage account of the backup target
#   TARGET_SYSTEM_NAME          Name of the secondary ONTAP system as shown in the Console (not needed if TARGET_SYSTEM_ID or SECONDARY_TARGET is set)
#
# Optional environment variables (default in parentheses; the wrapper sets these from its flags):
#   SECONDARY_TARGET             Secondary system as shown in the UI drop-down: "system | svm | aggregate"; replaces the TARGET_* name/SVM/aggregate
#   TARGET_SYSTEM_ID             Secondary ONTAP system ID, e.g. VsaWorkingEnvironment-xxxxxxxx; selects the system instead of its name
#   TARGET_SVM                   SVM on the secondary system; only needed if it has more than one
#   TARGET_AGGREGATE             Aggregate on that SVM; only needed if it has more than one
#   TARGET_CLUSTER_ID            Cluster ID of the secondary system; looked up unless set
#   TARGET_STORAGE_SYSTEM_UUID   SVM UUID on the secondary system; looked up unless set
#   HOURLY_EVERY_HOURS           Hourly schedule: run every N hours (1)
#   HOURLY_RETENTION             Hourly schedule: local snapshots to keep (3)
#   DAILY_AT                     Daily schedule: time of day HH:MM (00:00)
#   DAILY_RETENTION              Daily schedule: local snapshots to keep (3)
#   WEEKLY_ENABLED               Add a weekly schedule: true or false (false)
#   WEEKLY_DAY                   Weekly schedule: day of week, e.g. Sunday (Sunday)
#   WEEKLY_AT                    Weekly schedule: time of day HH:MM (00:00)
#   WEEKLY_RETENTION             Weekly schedule: local snapshots to keep (12)
#   MONTHLY_ENABLED              Add a monthly schedule: true or false (false)
#   MONTHLY_DAY                  Monthly schedule: day of month 1-31 (2)
#   MONTHLY_AT                   Monthly schedule: time of day HH:MM (01:00)
#   MONTHLY_RETENTION            Monthly schedule: local snapshots to keep (3)
#   SECONDARY_HOURLY_RETENTION   Copies to keep on the secondary ONTAP system, hourly (5)
#   SECONDARY_DAILY_RETENTION    ... daily (4)
#   SECONDARY_WEEKLY_RETENTION   ... weekly, only if weekly is enabled (3)
#   SECONDARY_MONTHLY_RETENTION  ... monthly, only if monthly is enabled (2)
#   RETRY_COUNT                  Backup retries: number of retry attempts (3)
#   RETRY_AFTER                  Backup retries: wait before retrying, e.g. 5m (5m)
#   PARTIAL_BACKUP               Allow partial backups: true or false (false)
#
# Choosing the secondary ONTAP system (the replication target). Two ways, same result:
#   TARGET_SYSTEM_NAME  Names only the system, e.g. BlueXPWEPerfStage2. If it has exactly one SVM
#                       and one aggregate, they are picked automatically; if it has several, the
#                       script stops and lists them (then set TARGET_SVM / TARGET_AGGREGATE).
#   SECONDARY_TARGET    Names the whole choice as the UI drop-down shows it, e.g.
#                       "BlueXPWEPerfStage2 | svm_BlueXPWEPerfStage2 | aggr1". When set, it replaces
#                       TARGET_SYSTEM_NAME, TARGET_SVM, TARGET_AGGREGATE and TARGET_SYSTEM_ID.
#                       List the available entries with: create-k8s-policy.sh --list-secondary-targets
# Either way, the cluster ID and SVM UUID are looked up, unless you set TARGET_CLUSTER_ID /
# TARGET_STORAGE_SYSTEM_UUID yourself.
#
set -euo pipefail

# --- command line: --policy-name is mandatory (an exported POLICY_NAME is ignored) ---
POLICY_NAME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --policy-name)
      { [ $# -ge 2 ] && [ -n "$2" ]; } || { echo "ERROR: --policy-name needs a value" >&2; exit 2; }
      POLICY_NAME="$2"; shift 2 ;;
    *) echo "ERROR: unknown option '$1'. This script only takes --policy-name <name>; use create-k8s-policy.sh for the other options." >&2; exit 2 ;;
  esac
done
[ -n "$POLICY_NAME" ] || { echo "ERROR: --policy-name <name> is required. Usage: $(basename "$0") --policy-name <name>" >&2; exit 2; }
POLICY_NAME_JSON=$(printf '%s' "$POLICY_NAME" | jq -Rs .)   # safely quoted for the JSON body

REQUIRED_VARS=(ACCOUNT_ID AGENT_ID ACCESS_TOKEN AZURE_SUBSCRIPTION_ID AZURE_RG AZURE_STORAGE_ACCOUNT TARGET_SYSTEM_NAME)
missing=()
for v in "${REQUIRED_VARS[@]}"; do [ "$v" = TARGET_SYSTEM_NAME ] && [ -n "${TARGET_SYSTEM_ID:-}${SECONDARY_TARGET:-}" ] && continue; [ -n "${!v:-}" ] || missing+=("$v"); done
if [ ${#missing[@]} -gt 0 ]; then
  echo "ERROR: the following environment variables must be set before running $(basename "$0"):" >&2
  for v in "${missing[@]}"; do echo "  $v  -  $(grep -m1 "^#   $v " "$0" | sed -E "s/^#   $v +//")" >&2; done
  echo "Example: export ${missing[0]}=<value>" >&2
  exit 1
fi

# --- schedule fragments: hourly and daily always; weekly and monthly only when enabled ---
SCHEDULES=$(cat <<JSON
{"schedule": {"repeatTaskEveryMins": 0, "repeatTaskEveryHour": ${HOURLY_EVERY_HOURS:-1},
              "minuteOffset": "ZeroMinutes", "snapMirrorLabel": "Hourly"},
 "retention": {"retentionCount": ${HOURLY_RETENTION:-3}, "retentionDays": 0,
               "verificationEnabled": false, "isSnapLockEnabled": false},
 "schedulerType": "Hourly", "backupType": "DATA"},
{"schedule": {"hoursOfTheDay": "${DAILY_AT:-00:00}",
              "minuteOffset": "ZeroMinutes", "snapMirrorLabel": "Daily"},
 "retention": {"retentionCount": ${DAILY_RETENTION:-3}, "retentionDays": 0,
               "verificationEnabled": false, "isSnapLockEnabled": false},
 "schedulerType": "Daily", "backupType": "DATA"}
JSON
)
if [ "${WEEKLY_ENABLED:-false}" = true ]; then
  SCHEDULES="$SCHEDULES,$(cat <<JSON
{"schedule": {"daysOfTheWeek": "${WEEKLY_DAY:-Sunday}", "hoursOfTheDay": "${WEEKLY_AT:-00:00}",
              "minuteOffset": "ZeroMinutes", "snapMirrorLabel": "Weekly"},
 "retention": {"retentionCount": ${WEEKLY_RETENTION:-12}, "retentionDays": 0,
               "verificationEnabled": false, "isSnapLockEnabled": false},
 "schedulerType": "Weekly", "backupType": "DATA"}
JSON
)"
fi
if [ "${MONTHLY_ENABLED:-false}" = true ]; then
  SCHEDULES="$SCHEDULES,$(cat <<JSON
{"schedule": {"daysOfTheMonth": "${MONTHLY_DAY:-2}", "hoursOfTheDay": "${MONTHLY_AT:-01:00}",
              "minuteOffset": "ZeroMinutes", "snapMirrorLabel": "Monthly"},
 "retention": {"retentionCount": ${MONTHLY_RETENTION:-3}, "retentionDays": 0,
               "verificationEnabled": false, "isSnapLockEnabled": false},
 "schedulerType": "Monthly", "backupType": "DATA"}
JSON
)"
fi
SECONDARY_RETENTIONS=$(cat <<JSON
{"retentionCount": ${SECONDARY_HOURLY_RETENTION:-5}, "schedulerType": "Hourly", "backupType": "DATA", "snapMirrorLabel": "Hourly"},
{"retentionCount": ${SECONDARY_DAILY_RETENTION:-4}, "schedulerType": "Daily", "backupType": "DATA", "snapMirrorLabel": "Daily"}
JSON
)
if [ "${WEEKLY_ENABLED:-false}" = true ]; then
  SECONDARY_RETENTIONS="$SECONDARY_RETENTIONS,$(cat <<JSON
{"retentionCount": ${SECONDARY_WEEKLY_RETENTION:-3}, "schedulerType": "Weekly", "backupType": "DATA", "snapMirrorLabel": "Weekly"}
JSON
)"
fi
if [ "${MONTHLY_ENABLED:-false}" = true ]; then
  SECONDARY_RETENTIONS="$SECONDARY_RETENTIONS,$(cat <<JSON
{"retentionCount": ${SECONDARY_MONTHLY_RETENTION:-2}, "schedulerType": "Monthly", "backupType": "DATA", "snapMirrorLabel": "Monthly"}
JSON
)"
fi

api_get() {  # $1 = URL, further args = extra headers ("Name: value"); prints the body, exits on a non-2xx status
  local url="$1" out code body h; shift
  local args=(-s -w '\n%{http_code}' -H "Authorization: Bearer $ACCESS_TOKEN" -H "X-Agent-Id: $AGENT_ID" -H 'Accept: application/json')
  for h in "$@"; do args+=(-H "$h"); done
  out=$(curl "${args[@]}" "$url") || { echo "ERROR: request failed: $url" >&2; exit 1; }
  code="${out##*$'\n'}"; body="${out%$'\n'*}"
  [[ "$code" =~ ^2 ]] || { echo "ERROR: GET $url returned HTTP $code" >&2; echo "$body" >&2; exit 1; }
  printf '%s' "$body"
}

# --- SECONDARY_TARGET: "system | svm | aggregate", exactly as shown in the UI drop-down ---
if [ -n "${SECONDARY_TARGET:-}" ]; then
  trim() { local x="$1"; x="${x#"${x%%[![:space:]]*}"}"; x="${x%"${x##*[![:space:]]}"}"; printf '%s' "$x"; }
  IFS='|' read -r st_sys st_svm st_agg st_extra <<< "$SECONDARY_TARGET"
  st_sys=$(trim "$st_sys"); st_svm=$(trim "$st_svm"); st_agg=$(trim "$st_agg")
  if [ -z "$st_sys" ] || [ -z "$st_svm" ] || [ -z "$st_agg" ] || [ -n "${st_extra:-}" ]; then
    echo "ERROR: SECONDARY_TARGET must look like 'system | svm | aggregate' (got '$SECONDARY_TARGET')" >&2; exit 1
  fi
  TARGET_SYSTEM_NAME="$st_sys"; TARGET_SVM="$st_svm"; TARGET_AGGREGATE="$st_agg"; TARGET_SYSTEM_ID=""
fi

# --- secondary ONTAP system: look up cluster, SVM and aggregate from the system name ---
# (mirrors the UI: GET .../v1/working-environment, then GET .../v2/working-environment/<id>/svm)
# Values you set yourself are kept; only the missing ones are looked up.
if [ -z "${TARGET_SYSTEM_ID:-}" ] || [ -z "${TARGET_SYSTEM_NAME:-}" ] || [ -z "${TARGET_CLUSTER_ID:-}" ] \
   || [ -z "${TARGET_STORAGE_SYSTEM_UUID:-}" ] || [ -z "${TARGET_SVM:-}" ] || [ -z "${TARGET_AGGREGATE:-}" ]; then
  CBS="${CONSOLE_API:-https://api.bluexp.netapp.com}/account/$ACCOUNT_ID/providers/cloudmanager_cbs/api"
  wes=$(api_get "$CBS/v1/working-environment" "X-Account-Id: $ACCOUNT_ID")
  if [ -n "${TARGET_SYSTEM_ID:-}" ]; then key="$TARGET_SYSTEM_ID"; field=id; else key="$TARGET_SYSTEM_NAME"; field=name; fi
  we=$(printf '%s' "$wes" | jq -c --arg k "$key" --arg f "$field" '[(."working-environment" // [])[] | select(.[$f] == $k)]')
  if [ "$(printf '%s' "$we" | jq length)" -ne 1 ]; then
    echo "ERROR: expected exactly one system with $field '$key'. Available systems:" >&2
    printf '%s' "$wes" | jq -r '(."working-environment" // [])[] | "  " + .name + "  (" + .id + ")"' >&2
    exit 1
  fi
  TARGET_SYSTEM_ID=$(printf '%s' "$we" | jq -r '.[0].id')
  TARGET_SYSTEM_NAME=$(printf '%s' "$we" | jq -r '.[0].name')
  if [ -z "${TARGET_CLUSTER_ID:-}" ]; then
    TARGET_CLUSTER_ID=$(printf '%s' "$we" | jq -r '.[0]["cluster-uuid"] // empty')
    [ -n "$TARGET_CLUSTER_ID" ] || { echo "ERROR: system '$TARGET_SYSTEM_NAME' has no cluster-uuid in the response" >&2; exit 1; }
  fi
  svms=$(api_get "$CBS/v2/working-environment/$TARGET_SYSTEM_ID/svm" "X-Account-Id: $ACCOUNT_ID")
  if [ -n "${TARGET_SVM:-}" ]; then
    svm=$(printf '%s' "$svms" | jq -c --arg n "$TARGET_SVM" '[(.svm // [])[] | select(.name == $n)]')
  else
    svm=$(printf '%s' "$svms" | jq -c '[(.svm // [])[]]')
  fi
  if [ "$(printf '%s' "$svm" | jq length)" -ne 1 ]; then
    echo "ERROR: could not pick a single SVM on '$TARGET_SYSTEM_NAME'. Set SECONDARY_TARGET to one of these (or set TARGET_SVM / TARGET_AGGREGATE):" >&2
    printf '%s' "$svms" | jq -r --arg s "$TARGET_SYSTEM_NAME" '(.svm // [])[] | .name as $v | (.aggregates // [])[] | "  \($s) | \($v) | \(.name)"' >&2
    exit 1
  fi
  TARGET_SVM=$(printf '%s' "$svm" | jq -r '.[0].name')
  [ -n "${TARGET_STORAGE_SYSTEM_UUID:-}" ] || TARGET_STORAGE_SYSTEM_UUID=$(printf '%s' "$svm" | jq -r '.[0].id')
  if [ -n "${TARGET_AGGREGATE:-}" ]; then
    agg=$(printf '%s' "$svm" | jq -c --arg n "$TARGET_AGGREGATE" '[.[0].aggregates[]? | select(.name == $n)]')
  else
    agg=$(printf '%s' "$svm" | jq -c '[.[0].aggregates[]?]')
  fi
  if [ "$(printf '%s' "$agg" | jq length)" -ne 1 ]; then
    echo "ERROR: could not pick a single aggregate on SVM '$TARGET_SVM'. Set SECONDARY_TARGET to one of these (or set TARGET_AGGREGATE):" >&2
    printf '%s' "$svm" | jq -r --arg s "$TARGET_SYSTEM_NAME" '.[0] as $v | ($v.aggregates // [])[] | "  \($s) | \($v.name) | \(.name)"' >&2
    exit 1
  fi
  TARGET_AGGREGATE=$(printf '%s' "$agg" | jq -r '.[0].name')
fi

PROVIDER_BLOCK=$(cat <<JSON
{"ipSpace":"Default","subscriptionID":"$AZURE_SUBSCRIPTION_ID","resourceGroup":"$AZURE_RG","storageAccount":"$AZURE_STORAGE_ACCOUNT"}
JSON
)

curl -s -X POST \
  "${CONSOLE_API:-https://api.bluexp.netapp.com}/backup-recovery/organizations/$ACCOUNT_ID/v1/workloads/k8s/kubernetes/policies" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "X-Account-Id: $ACCOUNT_ID" \
  -H 'Accept: application/json' \
  -H 'Content-Type: application/json' \
  -d @- <<EOF | jq .
{
  "policyName": $POLICY_NAME_JSON,
  "workloadType": "K8S",
  "agentID": "$AGENT_ID",
  "backupArchitectureType": "DiskToDisk",
  "schedulesAndRetentions": [$SCHEDULES],
  "secondarySettings": {
    "isSnapLockEnabled": false,
    "enableIntegrityCheck": false,
    "enableTierBackups": false,
    "transferSchedule": "inline",
    "replicationRetentions": [$SECONDARY_RETENTIONS],
    "backupTargets": [
      {
        "clusterID": "$TARGET_CLUSTER_ID",
        "storageSystemUuid": "$TARGET_STORAGE_SYSTEM_UUID",
        "storageAggregateName": "$TARGET_AGGREGATE",
        "systemName": "$TARGET_SYSTEM_NAME",
        "systemID": "$TARGET_SYSTEM_ID",
        "svm": "$TARGET_SVM"
      }
    ]
  },
  "localSnapshot": {
    "objectStoreSettings": {"provider": "azure", "azureProvider": $PROVIDER_BLOCK}
  },
  "replication": {
    "objectStoreSettings": {"provider": "azure", "azureProvider": $PROVIDER_BLOCK},
    "policyName": "",
    "prefix": "",
    "suffix": ""
  },
  "advancedSettings": {
    "backupRetries": {"retryCount": ${RETRY_COUNT:-3}, "retryAfter": "${RETRY_AFTER:-5m}"},
    "partialBackup": {"enabled": ${PARTIAL_BACKUP:-false}}
  }
}
EOF
