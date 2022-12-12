#!/bin/sh
#
# postgresql.sh
#
#
# Pre- and post-snapshot and post-restore execution hooks for PostgreSQL with NetApp Astra Control.
# Tested with PostgreSQL 14.4.0 deployed by Bitnami helm chart 11.6.7 and NetApp Astra Control Service 22.04.
#
# args: [pre|post]
# pre: Lock all tables and start pg_start_backup()
# post: Take database out of read-only mode
#

readonly DEBUG="${DEBUG:-"0"}"
readonly SCRIPT_NAME="${0}"
readonly VERSION="0.2"
readonly SLEEP_TIME=86400 # 1 day

readonly ebase=40
readonly esleeptime=$((ebase+1))
readonly ekill=$((ebase+2))
readonly efailedcmd=$((ebase+3))
readonly efailedcmdrc=$((ebase+4))
readonly efailedcmdres=$((ebase+5))
readonly eusage=$((ebase+6))
readonly enosleepersfound=$((ebase+7))




#
# The postgres container can use a number of variables; see
# https://hub.docker.com/_/postgres
#
#    POSTGRES_PASSWORD          - required
#    POSTGRES_USER              - optional; default: 'postgres'
#    POSTGRES_DB                - optional; default ${POSTGRES_USER}
#    POSTGRES_HOST_AUTH_METHOD  - optional; default: md5
#
readonly POSTGRES_USER="${POSTGRES_USER:-"postgres"}"
readonly POSTGRES_DB="${POSTGRES_DB:-"${POSTGRES_USER}"}"

#
# Writes the given message to standard output
#
# $* - The message to write
#
msg() {
    echo "${SCRIPT_NAME}: $*"
}

#
# Writes the given message to standard output if debug logging is enabled
#
# $* - The message to write
#
debug() {
    if [ "${DEBUG}" = "1" ]; then
        msg "DEBUG: $*"
    fi
}

#
# Writes the given information message to standard output
#
# $* - The message to write
#
info() {
    msg "INFO: $*"
}

#
# Writes the given error message to standard error
#
# $* - The message to write
#
error() {
    msg "ERROR: $*" 1>&2
}

#
# Prints a list of public tables that should be locked while the DB is
# frozen to standard output.
#
get_freeze_table_list() {
    tables=$(PGPASSWORD="${POSTGRES_PASSWORD}" psql -v ON_ERROR_STOP=1 --tuples-only --username "${POSTGRES_USER}" --dbname "${POSTGRES_DB}" <<-EOSQL
SELECT table_name
  FROM information_schema.tables
WHERE table_schema='public'
  AND table_type='BASE TABLE';
EOSQL
)

    echo "${tables}"
}

#
# Prints the list of the pids corresponding to processes executing
# a pg_sleep(${SLEEP_TIME}) in the DB.
#
get_sleeping_pids() {
    sleeping_pids=$(PGPASSWORD="${POSTGRES_PASSWORD}" psql -v ON_ERROR_STOP=1 --tuples-only --username "${POSTGRES_USER}" --dbname "${POSTGRES_DB}" <<-EOSQL
SELECT pid
  FROM pg_stat_activity
WHERE query~*'(${SLEEP_TIME})'
  AND wait_event='PgSleep';
EOSQL
)
    echo "${sleeping_pids}"
}

#
# waits for there to be a process blocking in a pg_sleep(${SLEEP_TIME}).
# Returns esleeptime if after a minute no such process is found; otherwise returns
# 0 on success.
#
wait_for_sleeper() {
    timeout=60
    sleeping_pids=$(get_sleeping_pids)

    while [ "${sleeping_pids}" != "" ]; do
        debug "... waiting for sleeper; timeout: ${timeout}"
        sleep 1

        timeout=$((timeout - 1))
        if [ "${timeout}" = "0" ]; then
            error "timed out waiting for sleeper"
            return ${esleeptime}
        fi

        sleeping_pids=$(get_sleeping_pids)
    done

    return 0
}

#
# Quiesces database ${POSTGRES_DB}
#
quiesce() {
    info "Quiescing database ${POSTGRES_DB}"

    tableList="$(get_freeze_table_list)"
    sname="netappAstraBackup"

    # (1) Start the transaction
    content="BEGIN; "

    # (2) lock all the tables
    for table in ${tableList}; do
        content="${content} LOCK TABLE ${table} IN SHARE MODE; "
    done

    # (3) start the pg_start_backup()
    content="${content} SELECT pg_start_backup('${sname}'); "

    # (4) hold the tables locked
    content="${content} SELECT pg_sleep(${SLEEP_TIME}); "

    # (5) Commit the transaction
    content="${content} COMMIT;"

    cmd_file="$(createTmpFile "${content}")"

    debug "Executing SQL sequence: ${content}"

    (run_cmd "${cmd_file}" "${POSTGRES_DB}" "${POSTGRES_USER}" > /dev/null 2>&1) > /dev/null 2>&1 &

    if ! wait_for_sleeper; then
        error "timed out waiting for sleeper"
        return ${esleeptime}
    fi

    # By this time, psql is running and has read the file
    rm "${cmd_file}"

    # Ask the kernel to write anything in the page cache out to the underlying media
    sync;sync;sync

    debug "Starting read only mode finished successfully"
    info "Quiescing finished successfully"

    return 0
}

#
# kills the query associated with the given pid.
# Returns 0 on success, ekill on failure.
#
kill_sleeper() {
    pid="${1}"
    debug "Killing sleeping process ${pid}"
    result=$(PGPASSWORD="${POSTGRES_PASSWORD}" psql -v ON_ERROR_STOP=1 --tuples-only --username "${POSTGRES_USER}" --dbname "${POSTGRES_DB}" <<-EOSQL
SELECT pg_cancel_backend(${pid});
EOSQL
)

    debug "kill_sleeper: result: '${result}'"

    case "${result}" in
    *t*)
        return 0
        ;;
    *)
        return ${ekill}
        ;;
    esac
}

#
# Kills all queries executing pg_sleep(${SLEEP_TIME}).
#
kill_all_sleepers() {
    sleeping_pids=$(get_sleeping_pids)
    if [ "${sleeping_pids}" == "" ]; then
      error "no sleepers found"
      return ${enosleepersfound}
    fi
    rc=${ekill}
    for pid in ${sleeping_pids}; do
        rc=0
        if ! kill_sleeper "${pid}"; then
            # Meh, try again
            sleep 1
            if ! kill_sleeper "${pid}"; then
                error "failed to kill sleeper ${pid}"
            fi
        fi
    done
    return ${rc}  # return ekill: no pid has been found.  0: there is a pid found
}

#
# Unquiesces database ${POSTGRES_DB}
#
unquiesce() {
    info "Unquiesceing database ${POSTGRES_DB}"

    debug "Killing all sleeping queries"
    if ! kill_all_sleepers; then
        # if we don't have pid for any reason, we need quit now.  Otherwise, the Thaw function will fail
        info "Warning: no pid has been found, no need to do next step (run_cmd)"
        return 0
    fi

    content="select pg_stop_backup()"
    cmd_file="$(createTmpFile "${content}")"

    # Take database out of read-only mode
    debug "Ending read only mode"
    debug "Executing SQL sequence: ${content}"

    if ! run_cmd "${cmd_file}" "${POSTGRES_DB}" "${POSTGRES_USER}"; then
        error "Command '${content}' failed"
        rm "${cmd_file}"
        return ${efailedcmd}
    fi
    rm "${cmd_file}"

    debug "Ending read-only mode finished successfully"
    info "Unquiesceing finished successfully"

    return 0
}

#
# Runs the given postgres command against the given database as the given
# user.
#
# ${1} - The path to the file containing the command to run
# ${2} - The database against which the function will run the command
# ${3} - The user that can perform the command
#
run_cmd() {
    cmd="${1}"
    db="${2}"
    user="${3}"
    result=""

    debug "Executing external sql script [${cmd}] for database ${db}"
    debug "Command: $(cat "${cmd}")"

    psql="psql -d ${db} -U ${user} --single-transaction --file ${cmd}"
    debug "${psql}"

    result="$(PGPASSWORD=${POSTGRES_PASSWORD} ${psql} 2>&1)"
    exit_status=$?

    debug "result: ${result}"

    if [ "${exit_status}" != "0" ]; then
        error "Command [${psql}] finished with exit code [${exit_status}] and message ${result}".
        return ${efailedcmdrc}
    fi

    if echo "${result}" | grep -qe 'WARNING\|ERROR'; then
        error "Command [${psql}] finished with exit code [${exit_status}] and message ${result}".
        return ${efailedcmdres}
    fi

    return 0
}

#
# Creates a temp file with the given content and writes its name to standard
# output
#
# $* - The content to write to the newly-generated temp file
#
createTmpFile() {
    content="${*}"
    tmpfile="$(mktemp 2> /dev/null)"

    if [ "${tmpfile}" = "" ]; then
        error "createTmpFile: mktemp failed"
        tmpfile="/tmp/netapp-postgres-quiesce"
    fi
    
    echo "${content}" > "${tmpfile}"

    echo "${tmpfile}"
}

# 
# Logical entry point to this script
#
# ${1} - Operation, either "pre" or "post".  When "pre" is specified,
#        then this script will quiesce the database.  When "post" is specified,
#        then this script will unquiesce the database.
#
main() {
    #
    # The "slave" side does not support pg_start_backup.   Therefore, we do nothing.
    # I have tested.  Even we do nothing on the "slave" side, it depends on "master" side to sync.  It works fine.
    #
    if [ "${POSTGRES_REPLICATION_MODE}" = "slave" ]; then
        return 0
    fi

    case "${1}" in
    "pre")
        quiesce
        ;;

    "post")
        unquiesce
        ;;

    *)
        error "Usage ${SCRIPT_NAME} <pre|post>"
        return ${eusage}
        ;;
    esac
}

main "$@"
