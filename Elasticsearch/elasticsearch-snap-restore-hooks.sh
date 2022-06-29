#!/bin/sh
#

# elasticsearch-snap-restore-hooks.sh
#
# Pre- and post-snapshot and post-restore execution hooks for Elasticsearch.
# Tested with Elasticsearch 8.2.3 (deployed by Bitnami helm chart 18.2.13) and NetApp Astra Control Service 22.04.
#
# args: [pre|post|postrestore]
# pre: Flush all Elasticsearch indices and make indices and index metadata read-only by setting index.blocks.read_only
# post: Unset index.blocks.read_only from all indices
# postrestore: Unset index.blocks.read_only from all indices
#
# After a restore, the postrestore action MUST be executed to make sure index.blocks.read_only is set to false for all indices.
#
# The current version of Astra Control can only target the containers to execute hooks by image name. The hook will run for any container image that matches the provided regular
# expression rule in Astra Control.


# unique error codes for every error case
ebase=100
eusage=$((ebase+1))
ebadstage=$((ebase+2))
epre=$((ebase+3))
epost=$((ebase+4))
epostrestore=$((ebase+5))

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
    info "Quiescing Elasticsearch - flushing all indices and setting index.blocks.read_only on all indices"
    curl -XPOST 'http://localhost:9200/_flush?pretty=true'; curl -H'Content-Type: application/json' -XPUT localhost:9200/_settings?pretty -d'{"index": {"blocks.read_only": true} }'
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
    info "Unquiescing Elasticsearch - unsetting index.blocks.read_only blocks from all indices"
    curl -H'Content-Type: application/json' -XPUT localhost:9200/_settings?pretty -d'{"index": {"blocks.read_only": false} }'
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
    echo "Usage: $0 <pre|post|postrestore>"
    exit ${eusage}
fi

if [ "${stage}" != "pre" ] && [ "${stage}" != "post" ] && [ "${stage}" != "postrestore" ]; then
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

if [ "${stage}" = "postrestore" ]; then
    unquiesce
    rc=$?
    if [ ${rc} -ne 0 ]; then
        error "Error during post-restore hook"
    fi
fi

exit ${rc}
