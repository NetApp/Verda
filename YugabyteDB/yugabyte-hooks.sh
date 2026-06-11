#!/bin/sh
#
#
# Pre and post execution hooks for YugabyteDB
# This execution hook has been tested with YugabyteDB 2.17.0.0-b24 (deployed using Helm) and NetApp Astra Control Service
# args: [pre <master-addresses> <db-name> | post <master-addresses> <yugabyte-snapshot-UUID>]
# pre: Performs a pre-snapshot hook, where a snapshot of the desired database is taken.
# post: Performs a post-restore hook, where a snapshot (referenced by Yugabyte Snapshot UUID) is used to restore data changes)

# error codes
ebase=100
eusage=$((ebase+1))
ebadstage=$((ebase+2))
epre=$((ebase+3))
epost=$((ebase+4))
# Writes the given message to standard output
#
# $* - The message to write

msg() {
    echo "$*"
}

# Writes the given information message to standard output
#
# $* - The message to write

info() {
    msg "INFO: $*"
}

# Writes the given error message to standard error
#
# $* - The message to write

error() {
    msg "ERROR: $*" 1>&2
}

set_defaults(){
  ebase=100
  eusage=$((ebase+1))
  epre=$((ebase+2))
  epost=$((ebase+3))
}

check_input(){
  if [ $# -ne 3 ]
  then
    error "$0: Usage: $0 [pre <master-addresses> <db-name> | post <master-addresses> <yugabyte-snapshot-UUID>]"
    exit ${eusage}
  fi

  export ACTION=$1
  export MASTER_ADDRESSES=$2

  if [[ $ACTION == "post" ]]
  then
    export SNAPSHOT_UUID=$3
  elif [[ $ACTION == "pre" ]]
  then
    export DB_NAME=$3
  elif [[ $ACTION != "post" && $ACTION != "pre" ]];
  then
    error "$0: Usage: $0 [pre <master-addresses> <db-name> | post <master-addresses> <yugabyte-snapshot-UUID>]"
    exit ${eusage}
  fi
}
#
# Run pre-snapshot hook steps here
#
presnapshothook() {
    yb-admin -master_addresses $MASTER_ADDRESSES create_database_snapshot ysql.$DB_NAME
    return 0
}
#
# Run post-restore hook steps here
#

postrestorehook() {
   yb-admin -master_addresses $MASTER_ADDRESSES restore_snapshot $SNAPSHOT_UUID
   return 0
}
#
# main
#
check_input $@

if [ "${ACTION}" = "pre" ]; then
    presnapshothook "${MASTER_ADDRESSES}" "${DB_NAME}"
    rc=$?
    if [ ${rc} -ne 0 ]; then
        error "Error during pre-snapshot hook"
    fi
fi

if [ "${ACTION}" = "post" ]; then
    postrestorehook "${MASTER_ADDRESSES}" "${SNAPSHOT_UUID}"
    rc=$?
    if [ ${rc} -ne 0 ]; then
        error "Error during post-snapshot hook"
    fi
fi

exit ${rc}
