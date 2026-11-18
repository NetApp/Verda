#!/usr/bin/env bash
# Local snapshot protection policy (S3-compatible backup target)
#
# Usage: s3-compatible-1-local-snapshot.sh --policy-name <name> [--dry-run]     (mandatory; an exported POLICY_NAME is ignored)
#
# Required environment variables (the script aborts if any is unset or empty):
#   ACCOUNT_ID          NetApp Console organization/account ID used in the API URL and X-Account-Id header
#   AGENT_ID            Console agent ID (agentID in the request body)
#   ACCESS_TOKEN        Bearer access token generated from your refresh token
#   S3COMPAT_CRED_NAME      Name of the S3-compatible credential in Backup and Recovery (not needed if S3COMPAT_CREDENTIAL_ID and S3COMPAT_SERVER_URL are both set)
#   S3COMPAT_BUCKET_NAME    S3-compatible bucket name
#
# Optional environment variables (default in parentheses; the wrapper sets these from its flags):
#   S3COMPAT_CREDENTIAL_ID           S3-compatible credential ID; looked up from S3COMPAT_CRED_NAME unless set
#   S3COMPAT_SERVER_URL              S3-compatible server address (storageServerUrl); looked up from S3COMPAT_CRED_NAME unless set
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
# shellcheck source=../../lib/bnr-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/bnr-common.sh"
bnr_env_aliases

# --- command line: --policy-name is mandatory (an exported POLICY_NAME is ignored) ---
POLICY_NAME=""
DRY_RUN=false
while [ $# -gt 0 ]; do
  case "$1" in
    --policy-name)
      { [ $# -ge 2 ] && [ -n "$2" ]; } || { echo "ERROR: --policy-name needs a value" >&2; exit 1; }
      POLICY_NAME="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "ERROR: unknown option '$1'. This script only takes --policy-name <name> and --dry-run; use create-k8s-policy.sh for the other options." >&2; exit 1 ;;
  esac
done
[ -n "$POLICY_NAME" ] || { echo "ERROR: --policy-name <name> is required. Usage: $(basename "$0") --policy-name <name> [--dry-run]" >&2; exit 1; }
POLICY_NAME_JSON=$(printf '%s' "$POLICY_NAME" | jq -Rs .)   # safely quoted for the JSON body

REQUIRED_VARS=(ACCOUNT_ID AGENT_ID ACCESS_TOKEN S3COMPAT_CRED_NAME S3COMPAT_BUCKET_NAME)
needed=()
for v in "${REQUIRED_VARS[@]}"; do [ "$v" = S3COMPAT_CRED_NAME ] && [ -n "${S3COMPAT_CREDENTIAL_ID:-}" ] && [ -n "${S3COMPAT_SERVER_URL:-}" ] && continue; needed+=("$v"); done
require_env_documented "$0" "${needed[@]}"

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

# --- S3-compatible target: look up credential ID and server address from the credential name ---
# (mirrors the UI: GET .../v1/credentials?provider=S3_COMPATIBLE, then GET .../v1/object-storage?...)
# S3COMPAT_CREDENTIAL_ID / S3COMPAT_SERVER_URL are kept if you set them; the lookup is skipped if you set both.
if [ -z "${S3COMPAT_CREDENTIAL_ID:-}" ] || [ -z "${S3COMPAT_SERVER_URL:-}" ]; then
  BASE="/backup-recovery/organizations/$ACCOUNT_ID/v1"
  creds=$(api_get_or_die "$BASE/credentials?provider=S3_COMPATIBLE")
  match=$(printf '%s' "$creds" | jq -c --arg n "$S3COMPAT_CRED_NAME" '[.[] | select(.credential_name == $n)]')
  if [ "$(printf '%s' "$match" | jq length)" -ne 1 ]; then
    echo "ERROR: expected exactly one S3-compatible credential named '$S3COMPAT_CRED_NAME'. Available credentials:" >&2
    printf '%s' "$creds" | jq -r '.[] | "  " + .credential_name' >&2
    exit 1
  fi
  [ -n "${S3COMPAT_CREDENTIAL_ID:-}" ] || S3COMPAT_CREDENTIAL_ID=$(printf '%s' "$match" | jq -r '.[0].credential_uuid // empty')
  [ -n "${S3COMPAT_SERVER_URL:-}" ] || S3COMPAT_SERVER_URL=$(printf '%s' "$match" | jq -r '.[0].storage_server_name // empty')
  if [ -z "$S3COMPAT_CREDENTIAL_ID" ] || [ -z "$S3COMPAT_SERVER_URL" ]; then
    echo "ERROR: credential '$S3COMPAT_CRED_NAME' has no credential_uuid / storage_server_name in the response:" >&2
    printf '%s' "$match" | jq -c '.[0] | del(.access_key)' >&2; exit 1
  fi
  buckets=$(api_get_or_die "$BASE/object-storage?provider=S3_COMPATIBLE&credential-id=$S3COMPAT_CREDENTIAL_ID")
  if ! printf '%s' "$buckets" | jq -e --arg b "$S3COMPAT_BUCKET_NAME" 'any(.[]; .object_store_name == $b)' >/dev/null; then
    echo "ERROR: bucket '$S3COMPAT_BUCKET_NAME' not found for credential '$S3COMPAT_CRED_NAME'. Available buckets:" >&2
    printf '%s' "$buckets" | jq -r '.[] | "  " + .object_store_name' >&2
    exit 1
  fi
fi

PROVIDER_BLOCK=$(cat <<JSON
{"bucketName":"$S3COMPAT_BUCKET_NAME","storageServerUrl":"$S3COMPAT_SERVER_URL"}
JSON
)

# POST the policy. With --dry-run, print the request body instead and make no create call
# (the read-only lookups above still ran).
POLICIES_URL="${CONSOLE_API}/backup-recovery/organizations/$ACCOUNT_ID/v1/workloads/k8s/kubernetes/policies"
post_policy() {
  if [ "$DRY_RUN" = true ]; then
    echo "Dry run. POST $POLICIES_URL" >&2
    jq .
    echo "Dry run. No policy was created." >&2
  else
    curl -s -X POST "$POLICIES_URL" \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "X-Account-Id: $ACCOUNT_ID" \
      -H 'Accept: application/json' \
      -H 'Content-Type: application/json' \
      -d @- | jq .
  fi
}
post_policy <<EOF
{
  "policyName": $POLICY_NAME_JSON,
  "workloadType": "K8S",
  "agentID": "$AGENT_ID",
  "backupArchitectureType": "LocalSnapshots",
  "schedulesAndRetentions": [$SCHEDULES],
  "localSnapshot": {
    "objectStoreSettings": {"provider": "generic-s3", "genericS3Provider": $PROVIDER_BLOCK}
  },
  "advancedSettings": {
    "backupRetries": {"retryCount": ${RETRY_COUNT:-3}, "retryAfter": "${RETRY_AFTER:-5m}"},
    "partialBackup": {"enabled": ${PARTIAL_BACKUP:-false}}
  }
}
EOF
