#!/bin/bash
#
# sqlserver2022-snap-restore-hooks.sh
#
# Pre- and post-snapshot and post-restore execution hooks for SQL Server 2022.
# Tested with Microsoft SQL Server 2022 (RTM) - 16.0.1000.6 (X64) and NetApp Astra Control Service 23.01
#
# args: [pre|post|postrestore]
# pre: Sets all user databases READ_ONLY by issuing "ALTER DATABASE ${db} SET READ_ONLY WITH ROLLBACK IMMEDIATE"
# post: Sets all user databases READ_WRITE again
# postrestore: Sets all user databases READ_WRITE again
#

# unique error codes for every error case
ebase=100
eusage=$((ebase+1))
ebadstage=$((ebase+2))
epre=$((ebase+3))
epost=$((ebase+4))
epostrestore=$((ebase+5))
eaccess=$((ebase+6))

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
# test DB access
#
test_access(){
  $sqlcmd -Q "SELECT name from sys.databases" > /dev/null 2>&1
  rc=$?
  if [ "${rc}" -ne "0" ] ; then
    return ${eaccess}
  fi
  return 0
}

#
# Get all user databases
# 
get_user_dbs() {
  info "Getting a list of all user DBs:"
  dbs=$($sqlcmd -Q "SELECT name from sys.databases where database_id > 4" | tail -n +3 | head -n -2)
  for db in ${dbs}
  do
    info "${db}"
  done
}

#
# read_only puts DB in READ_ONLY
#
read_only() {
    db=$1
    info "Setting user DB ${db} READ_ONLY"
    $sqlcmd -Q "ALTER DATABASE ${db} SET READ_ONLY WITH ROLLBACK IMMEDIATE"
    return $?
}
#
# read_write puts DB in READ_WRITE
#
read_write() {
    db=$1
    info "Setting user DB ${db} READ_WRITE"
    $sqlcmd -Q "ALTER DATABASE ${db} SET READ_WRITE"
    rc=$?
    return $?
}

#
# freeze_all puts all DBs in READ_ONLY
#
freeze_all(){
  for db in ${dbs}
  do
    read_only ${db}
    rc=$?
    if [ ${rc} -ne 0 ]; then
        error "Error setting ${db} READ_ONLY"
        rc=${epre}
        break
    fi
  done
  return ${rc}
}

#
# thaw_all puts all DBs in READ_WRITE
#
thaw_all(){
  for db in ${dbs}
  do
    read_write ${db}
    rc=$?
    if [ ${rc} -ne 0 ]; then
        error "Error setting ${db} READ_WRITE"
        if [ ${rc} -ne 0 ]; then
          if [ ${stage} = "post" ]; then
            rc=${epost}
          else
            rc=${epostrestore}
          fi
        fi
        break
    fi
  done
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

test_access
rc=$?
if [ ${rc} -ne 0 ]; then
  echo "Problem accessing SQL Server"
  return ${rc}
fi

get_user_dbs

# log something to stdout
info "Running $0 ${stage}"

if [ "${stage}" = "pre" ]; then
  freeze_all
  rc=$?
  if [ ${rc} -ne 0 ]; then
        error "Error during pre-snapshot hook"
    fi
fi

if [ "${stage}" = "post" ]; then
  thaw_all
  rc=$?
  if [ ${rc} -ne 0 ]; then
        error "Error during post-snapshot hook"
    fi
fi

if [ "${stage}" = "postrestore" ]; then
  for db in ${dbs}
  do
    read_write ${db}
    rc=$?
    if [ ${rc} -ne 0 ]; then
        error "Error during post-restore hook"
    fi
  done
fi

exit ${rc}
