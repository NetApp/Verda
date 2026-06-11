#!/bin/sh
#

# cassandra-snap-hooks.sh
#
# Pre- and post-snapshot execution hooks for Cassandra.
# Tested with Cassandra 4.0.4 (deployed by Bitnami helm chart 9.2.5) and NetApp Astra Control Service 22.04.
#
# args: [pre|post]
# pre: flush all keyspaces and tables by "nodetool flush"
# post: check all tables ("nodetool verify")
#
# A restore operation to a new namespace or cluster requires that the original instance of the application to be taken down. This is to ensure 
# that the peer group information carried over does not lead to cross-instance communication. Cloning of the app will not work.

# unique error codes for every error case
ebase=100
eusage=$((ebase+1))
ebadstage=$((ebase+2))
epre=$((ebase+3))
epost=$((ebase+4))

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
# Run quiesce steps here
#
quiesce() {
    info "Quiescing Cassandra - flushing all keyspaces and tables"
    nodetool flush
    rc=$?
    if [ ${rc} -ne 0 ]; then
        rc=${epre}
    fi
    return ${rc}
}

#
# Run unquiesce steps here
#
unquiesce() {
    info "Unquiescing Cassandra"
    nodetool verify
    rc=$?
    if [ ${rc} -ne 0 ]; then
        rc=${epost}
    fi
    return ${rc}
}

#
# main
#

# check arg
stage=$1
if [ -z "${stage}" ]; then
    echo "Usage: $0 <pre|post>"
    exit ${eusage}
fi

if [ "${stage}" != "pre" ] && [ "${stage}" != "post" ]; then
    echo "Invalid arg: ${stage}"
    exit ${ebadstage}
fi

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

exit ${rc}
