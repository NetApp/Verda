#!/usr/bin/env bash
# Wrapper: create a Backup and Recovery for Kubernetes protection policy
# via the NetApp Console API by dispatching to the matching per-target script.
#
# Usage:
#   create-k8s-policy.sh <target> <type> --policy-name <name> [options]   create the policy
#   create-k8s-policy.sh <target> <type> --vars      show the variables that combination needs
#   create-k8s-policy.sh --list                      list all supported combinations
#   create-k8s-policy.sh --list-secondary-targets    list the secondary ONTAP targets, as in the UI drop-down
#   create-k8s-policy.sh -h | --help
#
# Targets: azure | aws | ontap-s3 | sgws
# Types:   local-snapshot | disk-to-object | disk-to-disk | 3-2-1-fanout
#
# Mandatory:
#   --policy-name <name>            name of the protection policy to create
#                                   (an exported POLICY_NAME is ignored; not needed with --vars)
#
# Schedules. Hourly and daily are always created; weekly and monthly only when
# enabled (--weekly / --monthly, or any of their options). Defaults in parentheses.
#   --hourly-every <hours>          hourly: run every N hours (1)
#   --hourly-retention <n>          hourly: local snapshots to keep (3)
#   --daily-at <HH:MM>              daily: time of day (00:00)
#   --daily-retention <n>           daily: local snapshots to keep (3)
#   --weekly                        add a weekly schedule
#   --weekly-day <Sunday..Saturday> weekly: day of week (Sunday)
#   --weekly-at <HH:MM>             weekly: time of day (00:00)
#   --weekly-retention <n>          weekly: local snapshots to keep (12)
#   --monthly                       add a monthly schedule
#   --monthly-day <1-31>            monthly: day of month (2)
#   --monthly-at <HH:MM>            monthly: time of day (01:00)
#   --monthly-retention <n>         monthly: local snapshots to keep (3)
#
# Retention of the copies kept away from the cluster (not for local-snapshot):
#   --secondary-<period>-retention <n>   on the secondary ONTAP system (disk-to-disk, 3-2-1-fanout)
#   --object-<period>-retention <n>      in the object store (disk-to-object, 3-2-1-fanout)
#   --replica-<period>-retention <n>     shorthand: sets both for every destination the type has
#   where <period> is hourly | daily | weekly | monthly.
#   Defaults, secondary / object store:  hourly 5 / 5, daily 4 / 4, weekly 3 / 4, monthly 2 / 3.
#   The weekly and monthly ones need --weekly / --monthly.
#
# Secondary ONTAP system (disk-to-disk and 3-2-1-fanout only; the replication target).
# Two ways, same result:
#   TARGET_SYSTEM_NAME=<system>   environment variable. Names only the system, e.g. BlueXPWEPerfStage2.
#                                 With exactly one SVM and one aggregate they are picked automatically;
#                                 with several, the script stops and lists them (then set TARGET_SVM /
#                                 TARGET_AGGREGATE, or use --secondary-target).
#   --secondary-target "<system> | <svm> | <aggregate>"
#                                 (or env SECONDARY_TARGET) names the whole choice as the UI drop-down
#                                 shows it, e.g. "BlueXPWEPerfStage2 | svm_BlueXPWEPerfStage2 | aggr1".
#                                 It replaces TARGET_SYSTEM_NAME, TARGET_SVM and TARGET_AGGREGATE.
#   --list-secondary-targets      print the available entries (needs ACCOUNT_ID, AGENT_ID, ACCESS_TOKEN)
# Either way, the cluster ID and SVM UUID are looked up, unless you set TARGET_CLUSTER_ID /
# TARGET_STORAGE_SYSTEM_UUID yourself.
#
# Backup behaviour:
#   --retry-count <n>               backup retry attempts (3)
#   --retry-after <duration>        wait before retrying, e.g. 5m (5m)
#   --partial-backup <true|false>   allow partial backups (false)
#
# Apart from --policy-name, every option also exists as an environment variable (see --vars); a command-line
# option wins over the environment, and a specific --secondary-/--object- option
# wins over the --replica- shorthand. Values are sent as given: apart from the
# format checks below, the API decides which values are allowed.
#
# The per-target scripts must sit in the same directory as this wrapper.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
unset POLICY_NAME   # the policy name comes from --policy-name only
policy_name=""

usage() { sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; }

TARGETS=(azure aws ontap-s3 sgws)
TYPES=(local-snapshot disk-to-object disk-to-disk 3-2-1-fanout)
PERIODS=(hourly daily weekly monthly)

script_for() {  # $1=target $2=type
  local n
  case "$2" in
    local-snapshot) n=1 ;; disk-to-object) n=2 ;; disk-to-disk) n=3 ;; 3-2-1-fanout) n=4 ;;
  esac
  echo "$DIR/$1-$n-$2.sh"
}

die() { echo "ERROR: $*" >&2; echo "Run '$(basename "$0") --help' for usage." >&2; exit 2; }

list_secondary_targets() {
  for v in ACCOUNT_ID AGENT_ID ACCESS_TOKEN; do [ -n "${!v:-}" ] || die "$v must be set to list the secondary targets"; done
  CBS="${CONSOLE_API:-https://cloudmanager.cloud.netapp.com}/account/$ACCOUNT_ID/providers/cloudmanager_cbs/api"
  api_get() {  # $1 = URL; prints the body, exits on a non-2xx status
    local out code body
    out=$(curl -s -w '\n%{http_code}' -H "Authorization: Bearer $ACCESS_TOKEN" -H "X-Agent-Id: $AGENT_ID" \
      -H "X-Account-Id: $ACCOUNT_ID" -H 'Accept: application/json' "$1") || { echo "ERROR: request failed: $1" >&2; exit 1; }
    code="${out##*$'\n'}"; body="${out%$'\n'*}"
    [[ "$code" =~ ^2 ]] || { echo "ERROR: GET $1 returned HTTP $code" >&2; echo "$body" >&2; exit 1; }
    printf '%s' "$body"
  }
  wes=$(api_get "$CBS/v1/working-environment")
  printf '%s' "$wes" | jq -r '(."working-environment" // [])[] | [.id, .name] | @tsv' | while IFS=$'\t' read -r id name; do
    api_get "$CBS/v2/working-environment/$id/svm" | jq -r --arg s "$name" '(.svm // [])[] | .name as $v | (.aggregates // [])[] | "\($s) | \($v) | \(.name)"'
  done
}

case "${1:-}" in
  -h|--help|"") usage; exit 0 ;;
  --list)
    for t in "${TARGETS[@]}"; do for y in "${TYPES[@]}"; do echo "$t $y"; done; done
    exit 0 ;;
  --list-secondary-targets) list_secondary_targets; exit 0 ;;
esac

target="${1:-}"; type="${2:-}"; shift $(( $# < 2 ? $# : 2 ))

# Friendly aliases
case "$target" in
  ontap|ontaps3|ontap_s3) target=ontap-s3 ;;
  storagegrid|sg)         target=sgws ;;
esac
case "$type" in
  321|3-2-1|fanout|fan-out)             type=3-2-1-fanout ;;
  snapshot|local|local-snapshots)       type=local-snapshot ;;
  d2o|disk2object|disk-to-object-store) type=disk-to-object ;;
  d2d|disk2disk)                        type=disk-to-disk ;;
esac

[[ " ${TARGETS[*]} " == *" $target "* ]] || die "unknown or missing target '${target}' (use: ${TARGETS[*]})"
[[ " ${TYPES[*]} "   == *" $type "*   ]] || die "unknown or missing type '${type}' (use: ${TYPES[*]})"

script="$(script_for "$target" "$type")"
[ -f "$script" ] || die "script not found: $script"

# Which copy destinations does this policy type have?
has_sec=false; has_obj=false
case "$type" in
  disk-to-disk)  has_sec=true ;;
  disk-to-object) has_obj=true ;;
  3-2-1-fanout)  has_sec=true; has_obj=true ;;
esac

show_vars=false
need_val() { [ $# -ge 2 ] && [ -n "${2:-}" ] || die "option $1 needs a value"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --vars)                     show_vars=true; shift ;;
    --list-secondary-targets)   list_secondary_targets; exit 0 ;;
    --policy-name)              need_val "$@"; policy_name="$2"; shift 2 ;;
    --hourly-every)             need_val "$@"; export HOURLY_EVERY_HOURS="$2"; shift 2 ;;
    --hourly-retention)         need_val "$@"; export HOURLY_RETENTION="$2"; shift 2 ;;
    --daily-at)                 need_val "$@"; export DAILY_AT="$2"; shift 2 ;;
    --daily-retention)          need_val "$@"; export DAILY_RETENTION="$2"; shift 2 ;;
    --weekly)                   export WEEKLY_ENABLED=true; shift ;;
    --weekly-day)               need_val "$@"; export WEEKLY_ENABLED=true WEEKLY_DAY="$2"; shift 2 ;;
    --weekly-at)                need_val "$@"; export WEEKLY_ENABLED=true WEEKLY_AT="$2"; shift 2 ;;
    --weekly-retention)         need_val "$@"; export WEEKLY_ENABLED=true WEEKLY_RETENTION="$2"; shift 2 ;;
    --monthly)                  export MONTHLY_ENABLED=true; shift ;;
    --monthly-day)              need_val "$@"; export MONTHLY_ENABLED=true MONTHLY_DAY="$2"; shift 2 ;;
    --monthly-at)               need_val "$@"; export MONTHLY_ENABLED=true MONTHLY_AT="$2"; shift 2 ;;
    --monthly-retention)        need_val "$@"; export MONTHLY_ENABLED=true MONTHLY_RETENTION="$2"; shift 2 ;;
    --secondary-hourly-retention|--secondary-daily-retention|--secondary-weekly-retention|--secondary-monthly-retention)
      need_val "$@"; $has_sec || die "$1 does not apply to $type policies (no secondary copy)"
      p="${1#--secondary-}"; p="${p%-retention}"; printf -v "cli_sec_$p" '%s' "$2"; shift 2 ;;
    --object-hourly-retention|--object-daily-retention|--object-weekly-retention|--object-monthly-retention)
      need_val "$@"; $has_obj || die "$1 does not apply to $type policies (no object-store copy)"
      p="${1#--object-}"; p="${p%-retention}"; printf -v "cli_obj_$p" '%s' "$2"; shift 2 ;;
    --replica-hourly-retention|--replica-daily-retention|--replica-weekly-retention|--replica-monthly-retention)
      need_val "$@"; { $has_sec || $has_obj; } || die "$1 does not apply to $type policies (no secondary or object-store copy)"
      p="${1#--replica-}"; p="${p%-retention}"; printf -v "cli_rep_$p" '%s' "$2"; shift 2 ;;
    --secondary-target)         need_val "$@"; $has_sec || die "--secondary-target does not apply to $type policies (no secondary copy)"
                                export SECONDARY_TARGET="$2"; shift 2 ;;
    --retry-count)              need_val "$@"; export RETRY_COUNT="$2"; shift 2 ;;
    --retry-after)              need_val "$@"; export RETRY_AFTER="$2"; shift 2 ;;
    --partial-backup)           need_val "$@"; export PARTIAL_BACKUP="$2"; shift 2 ;;
    *) die "unknown option '$1'" ;;
  esac
done

if $show_vars; then
  echo "$target / $type needs this command-line option:"
  echo "  --policy-name <name>        name of the protection policy to create"
  echo
  echo "...and these environment variables:"
  sed -n '/^# Required environment variables/,/^#$/p' "$script" | sed '1d;$d' | sed 's/^#   /  /'
  echo
  echo "Optional (defaults in parentheses; or use the wrapper's command-line options):"
  sed -n '/^# Optional environment variables/,/^#$/p' "$script" | sed '1d;$d' | sed 's/^#   /  /'
  if $has_sec; then
    echo
    sed -n '/^# Choosing the secondary ONTAP system/,/^#$/p' "$script" | sed '$d' | sed 's/^# \{0,1\}//'
  fi
  exit 0
fi

[ -n "$policy_name" ] || die "--policy-name <name> is required"

# --- resolve copy-retention precedence --------------------------------------
# specific CLI option > --replica- CLI shorthand > specific env var > REPLICA_<P>_RETENTION env var
for p in "${PERIODS[@]}"; do
  P="$(printf '%s' "$p" | tr 'a-z' 'A-Z')"
  s="cli_sec_$p"; o="cli_obj_$p"; r="cli_rep_$p"
  sv="SECONDARY_${P}_RETENTION"; ov="OBJECT_${P}_RETENTION"; rv="REPLICA_${P}_RETENTION"
  sec="${!s:-${!r:-${!sv:-${!rv:-}}}}"
  obj="${!o:-${!r:-${!ov:-${!rv:-}}}}"
  if $has_sec && [ -n "$sec" ]; then export "$sv=$sec"; else unset "$sv" 2>/dev/null || true; fi
  if $has_obj && [ -n "$obj" ]; then export "$ov=$obj"; else unset "$ov" 2>/dev/null || true; fi
done

# --- validate values (flags or environment) ---------------------------------
is_posint() { [[ "$1" =~ ^[1-9][0-9]*$ ]]; }
check_int() {  # $1=VAR name, $2=option name
  local v="${!1:-}"; [ -z "$v" ] && return 0
  is_posint "$v" || die "$2 must be a positive integer (got '$v')"
}
check_time() {  # $1=VAR name, $2=option name
  local v="${!1:-}"; [ -z "$v" ] && return 0
  [[ "$v" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] || die "$2 must be HH:MM, 24-hour (got '$v')"
}
check_bool() { local v="${!1:-}"; [ -z "$v" ] && return 0
  [[ "$v" == true || "$v" == false ]] || die "$2 must be true or false (got '$v')"; }

check_int  HOURLY_EVERY_HOURS --hourly-every
check_int  HOURLY_RETENTION   --hourly-retention
check_int  DAILY_RETENTION    --daily-retention
check_int  WEEKLY_RETENTION   --weekly-retention
check_int  MONTHLY_RETENTION  --monthly-retention
check_int  RETRY_COUNT        --retry-count
check_time DAILY_AT   --daily-at
check_time WEEKLY_AT  --weekly-at
check_time MONTHLY_AT --monthly-at
check_bool WEEKLY_ENABLED  "WEEKLY_ENABLED"
check_bool MONTHLY_ENABLED "MONTHLY_ENABLED"
check_bool PARTIAL_BACKUP  --partial-backup

if [ -n "${WEEKLY_DAY:-}" ]; then   # accept any capitalisation, send e.g. "Sunday"
  WEEKLY_DAY="$(printf '%s' "$WEEKLY_DAY" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')"
  case "$WEEKLY_DAY" in Sunday|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday) export WEEKLY_DAY ;;
    *) die "--weekly-day must be a weekday name, Sunday to Saturday (got '$WEEKLY_DAY')" ;; esac
fi
if [ -n "${MONTHLY_DAY:-}" ]; then
  { is_posint "$MONTHLY_DAY" && [ "$MONTHLY_DAY" -le 31 ]; } || die "--monthly-day must be a day of the month, 1-31 (got '$MONTHLY_DAY')"
fi
if [ -n "${RETRY_AFTER:-}" ]; then
  [[ "$RETRY_AFTER" =~ ^[0-9]+[smh]$ ]] || die "--retry-after must look like 30s, 5m or 1h (got '$RETRY_AFTER')"
fi

for p in "${PERIODS[@]}"; do
  P="$(printf '%s' "$p" | tr 'a-z' 'A-Z')"
  for kind in SECONDARY OBJECT; do
    v="${kind}_${P}_RETENTION"
    check_int "$v" "the $(printf '%s' "$kind" | tr 'A-Z' 'a-z') $p retention"
  done
done
if [ -n "${SECONDARY_WEEKLY_RETENTION:-}${OBJECT_WEEKLY_RETENTION:-}" ] && [ "${WEEKLY_ENABLED:-false}" != true ]; then
  die "a weekly copy retention was given, but the weekly schedule is not enabled (add --weekly)"
fi
if [ -n "${SECONDARY_MONTHLY_RETENTION:-}${OBJECT_MONTHLY_RETENTION:-}" ] && [ "${MONTHLY_ENABLED:-false}" != true ]; then
  die "a monthly copy retention was given, but the monthly schedule is not enabled (add --monthly)"
fi

exec bash "$script" --policy-name "$policy_name"
