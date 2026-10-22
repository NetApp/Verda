#!/usr/bin/env bash
# Local snapshot protection policy (ONTAP S3 backup target)
#
# Usage: ontap-s3-1-local-snapshot.sh --policy-name <name>     (mandatory; an exported POLICY_NAME is ignored)
#
# Required environment variables (the script aborts if any is unset or empty):
#   ACCOUNT_ID           NetApp Console organization/account ID used in the API URL and X-Account-Id header
#   AGENT_ID             Console agent ID (agentID in the request body)
#   ACCESS_TOKEN         Bearer access token generated from your refresh token
#   ONTAP_BUCKET_NAME    ONTAP S3 bucket name
#   ONTAP_CRED_NAME      Name of the ONTAP S3 credential in Backup and Recovery (not needed if ONTAP_S3_SERVER_URL is set)
#
# Optional environment variables (default in parentheses; the wrapper sets these from its flags):
#   ONTAP_S3_SERVER_URL          ONTAP S3 server address; if set, the credential lookup is skipped (looked up from ONTAP_CRED_NAME)
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
#   RETRY_COUNT                  Backup retries: number of retry attempts (3)
#   RETRY_AFTER                  Backup retries: wait before retrying, e.g. 5m (5m)
#   PARTIAL_BACKUP               Allow partial backups: true or false (false)
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

REQUIRED_VARS=(ACCOUNT_ID AGENT_ID ACCESS_TOKEN ONTAP_BUCKET_NAME ONTAP_CRED_NAME)
missing=()
for v in "${REQUIRED_VARS[@]}"; do [ "$v" = ONTAP_CRED_NAME ] && [ -n "${ONTAP_S3_SERVER_URL:-}" ] && continue; [ -n "${!v:-}" ] || missing+=("$v"); done
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

# --- ONTAP S3 target: look up the server address from the credential name ----
# (mirrors the UI: GET .../v1/credentials?provider=ONTAP_S3, then GET .../v1/object-storage?...)
# Skipped when ONTAP_S3_SERVER_URL is set.
api_get() {  # $1 = URL, further args = extra headers ("Name: value"); prints the body, exits on a non-2xx status
  local url="$1" out code body h; shift
  local args=(-s -w '\n%{http_code}' -H "Authorization: Bearer $ACCESS_TOKEN" -H "X-Agent-Id: $AGENT_ID" -H 'Accept: application/json')
  for h in "$@"; do args+=(-H "$h"); done
  out=$(curl "${args[@]}" "$url") || { echo "ERROR: request failed: $url" >&2; exit 1; }
  code="${out##*$'\n'}"; body="${out%$'\n'*}"
  [[ "$code" =~ ^2 ]] || { echo "ERROR: GET $url returned HTTP $code" >&2; echo "$body" >&2; exit 1; }
  printf '%s' "$body"
}
if [ -z "${ONTAP_S3_SERVER_URL:-}" ]; then
  BASE="${CONSOLE_API:-https://api.bluexp.netapp.com}/backup-recovery/organizations/$ACCOUNT_ID/v1"
  creds=$(api_get "$BASE/credentials?provider=ONTAP_S3")
  match=$(printf '%s' "$creds" | jq -c --arg n "$ONTAP_CRED_NAME" '[.[] | select(.credential_name == $n)]')
  if [ "$(printf '%s' "$match" | jq length)" -ne 1 ]; then
    echo "ERROR: expected exactly one ONTAP S3 credential named '$ONTAP_CRED_NAME'. Available credentials:" >&2
    printf '%s' "$creds" | jq -r '.[] | "  " + .credential_name' >&2
    exit 1
  fi
  ONTAP_S3_SERVER_URL=$(printf '%s' "$match" | jq -r '.[0].storage_server_name // empty')
  cred_id=$(printf '%s' "$match" | jq -r '.[0].credential_uuid // empty')
  if [ -z "$ONTAP_S3_SERVER_URL" ] || [ -z "$cred_id" ]; then
    echo "ERROR: credential '$ONTAP_CRED_NAME' has no storage_server_name / credential_uuid in the response:" >&2
    printf '%s' "$match" | jq -c '.[0] | del(.access_key)' >&2; exit 1
  fi
  buckets=$(api_get "$BASE/object-storage?provider=ONTAP_S3&credential-id=$cred_id")
  if ! printf '%s' "$buckets" | jq -e --arg b "$ONTAP_BUCKET_NAME" 'any(.[]; .object_store_name == $b)' >/dev/null; then
    echo "ERROR: bucket '$ONTAP_BUCKET_NAME' not found for credential '$ONTAP_CRED_NAME'. Available buckets:" >&2
    printf '%s' "$buckets" | jq -r '.[] | "  " + .object_store_name' >&2
    exit 1
  fi
fi

PROVIDER_BLOCK=$(cat <<JSON
{"bucketName":"$ONTAP_BUCKET_NAME","storageServerUrl":"$ONTAP_S3_SERVER_URL"}
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
  "backupArchitectureType": "LocalSnapshots",
  "schedulesAndRetentions": [$SCHEDULES],
  "localSnapshot": {
    "objectStoreSettings": {"provider": "ontap-s3", "ontapS3Provider": $PROVIDER_BLOCK}
  },
  "advancedSettings": {
    "backupRetries": {"retryCount": ${RETRY_COUNT:-3}, "retryAfter": "${RETRY_AFTER:-5m}"},
    "partialBackup": {"enabled": ${PARTIAL_BACKUP:-false}}
  }
}
EOF
