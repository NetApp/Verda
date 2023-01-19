#!/bin/sh
#
#
# Pre and post execution hooks for MongoDB (non-sharded)
# This execution hook has been tested with MongoDB 5.0.8 (deployed using Bitnami Helm chart) and NetApp Astra Control Service 22.04
# args: [pre|post]
# pre: Performs a lock operation of the MongoDB instance using db.fsyncLock(). This flushes all write operations to the PVC and prevents additional writes by locking MongoDB.
# post: Unlock MongoDB instance. Runs db.fsyncUnlock()
#
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
  if [ $# -ne 1 ]
  then
    error "$0: Usage: $0 [pre|post]"
    exit ${eusage}
  fi

  export ACTION=$1

  if [ $ACTION != "post" && $ACTION != "pre" ]; then
    error "$0: Usage: $0 [pre|post]"
    exit ${eusage}
  fi
}
#
# Run prehook steps here
#
prehook() {
    mongo admin --eval "printjson(db.fsyncLock())" --authenticationDatabase admin -u root -p $MONGODB_ROOT_PASSWORD
    return 0
}
#
# Run posthook steps here
#
posthook() {
    mongo admin --eval "printjson(db.fsyncUnlock())" --authenticationDatabase admin -u root -p $MONGODB_ROOT_PASSWORD
    return 0
}
#
# main
#
check_input $@

if [ "${ACTION}" = "pre" ]; then
    prehook
    rc=$?
    if [ ${rc} -ne 0 ]; then
        error "Error during pre-snapshot hook"
    fi
fi

if [ "${ACTION}" = "post" ]; then
    posthook
    rc=$?
    if [ ${rc} -ne 0 ]; then
        error "Error during post-snapshot hook"
    fi
fi

exit ${rc}
