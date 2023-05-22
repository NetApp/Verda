#!/bin/bash
#

# elasticsearch-snap-restore-hooks.sh
#
# Pre- and post-snapshot and post-restore execution hooks for Elasticsearch.
# Tested with Elasticsearch 8.6.2 (deployed by Bitnami helm chart 19.6.0) and NetApp Astra Control Service 23.04.
#
# args: [pre|post|postrestore]
# pre: Flush all Elasticsearch indices and make indices and index metadata read-only by setting index.blocks.read_only
# post: Unset index.blocks.read_only from all indices
# postrestore: Wait for Elasticsearch cluster to become ready and unset index.blocks.read_only from all indices
#
# After a restore, the postrestore action MUST be executed to make sure index.blocks.read_only is set to false for all indices.
#

# unique error codes for every error case
ebase=100
eusage=$((ebase+1))
ebadstage=$((ebase+2))
epre=$((ebase+3))
epost=$((ebase+4))
epostrestore=$((ebase+5))
epostrestore_esnotready=$((ebase+6))
eindexcount=$((ebase+7))

# How many mins to wait for ES to become ready:
let max_wait_minutes=10

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
# Get status of ES cluster and wait until it's "green"
#
wait_es_green() {
  info "Waiting for Elasticsearch to become ready"
  sleep 60
  let i=1
  es_state=$(curl -X GET "localhost:9200/_cluster/health?local=true&pretty" | awk -F: '/status/ {print $2}' | awk -F\" '{print $2}')
  while [ ${es_state} != "green" ]; do
    sleep 60
    if (( $i > $max_wait_minutes )); then
      info "Waited too long for Elastisearch to become ready, aborting"
      exit ${epostrestore_esnotready}
    fi
    info "Waiting for Elasticsearch to become ready, waited already ${i} mins, one more minute"
    (( i++ ))
  done
  info "Elastisearch is ready"
}

#
# Get number of indices
#
get_index_count() {
  info "Getting number of indices"
  let index_count=$(curl -X GET "localhost:9200/_cat/indices/*?v=true&s=index&pretty" | wc -l)
  rc=$?
  if [ ${rc} -ne 0 ]; then
    rc=${eindexcount}
  fi
  (( index_count-- ))
  info "Number of indices: $index_count"
  return ${rc}
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
    error "Usage: $0 <pre|post|postrestore>"
    exit ${eusage}
fi

if [ "${stage}" != "pre" ] && [ "${stage}" != "post" ] && [ "${stage}" != "postrestore" ]; then
    error "Invalid arg: ${stage}"
    exit ${ebadstage}
fi

get_index_count
if (( ${index_count} == 0 )); then
  info "No indices present - nothing to do"
  rc=0
  exit $rc
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
    # wait a minute...
    wait_es_green
    unquiesce
    rc=$?
    if [ ${rc} -ne 0 ]; then
        error "Error during post-restore hook"
    fi
fi

exit ${rc}
