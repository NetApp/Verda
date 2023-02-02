#!/bin/bash
#

# sqlserver2022-snap-restore-hooks.sh
#
# Pre- and post-snapshot and post-restore execution hooks for SQL Server 2022.
# Tested with XXXX and NetApp Astra Control Service 23.01
#
# args: [pre|post|postrestore]
# pre: 
# post:
# postrestore: 
#

# unique error codes for every error case
ebase=100
eusage=$((ebase+1))
ebadstage=$((ebase+2))
epre=$((ebase+3))
epost=$((ebase+4))
epostrestore=$((ebase+5))

sqlcmd="/opt/mssql-tools/bin/sqlcmd -U sa -P ${SA_PASSWORD}"

#
# Writes the given message to standard output
#
# $* - The message to write
#
msg() {
    echo "$*"
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
# Get all user databases
# 
get_user_dbs() {
  info "Getting a list of all user DBs"
  dbs=$($sqlcmd -Q "SELECT name from sys.databases where database_id > 4" | tail -n +3 | head -n -2)
}

#
# Run quiesce steps here
#
quiesce() {
    info "Freezing all user DBs"
    $sqlcmd -q "ALTER SERVER CONFIGURATION SET SUSPEND_FOR_SNAPSHOT_BACKUP = ON" 2>&1 &
    rc=$?
    if [ ${rc} -ne 0 ]; then
        rc=${epre}
    fi
    return ${rc}
}

#
# Run unquiesce hook steps here
#
unquiesce() {
    info "Unfreezing all user DBs"
    $sqlcmd -Q "ALTER SERVER CONFIGURATION SET SUSPEND_FOR_SNAPSHOT_BACKUP = OFF"
    rc=$?
    if [ ${rc} -ne 0 ]; then
        if [ ${stage} = "post" ]; then
          rc=${epost}
        else
          rc=${epostrestore}
        fi
    fi
    return ${rc}
}

#
# main
#

# check arg
stage=$1
if [ -z "${stage}" ]; then
    echo "Usage: $0 <pre|post|postrestore>"
    exit ${eusage}
fi

if [ "${stage}" != "pre" ] && [ "${stage}" != "post" ] && [ "${stage}" != "postrestore" ]; then
    echo "Invalid arg: ${stage}"
    exit ${ebadstage}
fi

get_user_dbs
echo $dbs

# log something to stdout
info "Running $0 ${stage}"

if [ "${stage}" = "pre" ]; then
    quiesce
    rc=$?
    if [ ${rc} -ne 0 ]; then
        error "Error during pre-snapshot hook"
    fi
fi

if [ "${stage}" = "post" ]; then
    unquiesce
    rc=$?
    if [ ${rc} -ne 0 ]; then
        error "Error during post-snapshot hook"
    fi
fi

if [ "${stage}" = "postrestore" ]; then
    # wait a minute...
    unquiesce
    rc=$?
    if [ ${rc} -ne 0 ]; then
        error "Error during post-restore hook"
    fi
fi

exit ${rc}
