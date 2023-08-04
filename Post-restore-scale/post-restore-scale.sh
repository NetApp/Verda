#!/bin/sh
#

# post-restore-scale.sh
#
# Pre- and post-snapshot and post-restore execution hooks for Elasticsearch.
# Tested with XXX and NetApp Astra Control Service 23.07.
#
# args: [<deployment to scale> <# of replicas>]
#

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

exists_in_list() {
  LIST=$1
  DELIMITER=$2
  VALUE=$3
  LIST_WHITESPACES=`echo $LIST | tr "$DELIMITER" " "`
  for x in $LIST_WHITESPACES; do
    if [ "$x" = "$VALUE" ]; then
        return 0
    fi
  done
  return 1
}

get_deployments(){
  kubectl get deployments -o custom-columns=NAME:.metadata.name | grep -v NAME
}

init(){
  # unique error codes for every error case
  ebase=100
  eusage=$((ebase+1))
  ebadstage=$((ebase+2))
  epre=$((ebase+3))
  epost=$((ebase+4))
  epostrestore=$((ebase+5))

  # Check for existence of kubectl command:
  KUBECTLCMD=$(which kubectl)
  if [[ ! -x $KUBECTLCMD ]]; then
    error "kubectl not found, exiting."
    rc=$eusage
    exit ${rc}
  fi

  DEPLOYMENTS=$(get_deployments)
}

check_input(){
  if [ $# -ne 2 ]
  then
    error "$0: Usage: $0 [<deployment to scale> <# of replicas>]"
    exit ${eusage}
  fi

  DEPL_TO_SCALE=$1
  NEWREPLICAS=$2

  if [[ $NEWREPLICAS -lt 0 ]]
  then
    error "$0: Number of new replicas must be >= 0"
    exit ${eusage}
  fi

  if exists_in_list "$DEPLOYMENTS" " " "$DEPL_TO_SCALE"
  then
    info "$0: Deployment $DEPL_TO_SCALE found."
  else
    error "$0: Deployment $DEPL_TO_SCALE does not exist."
    exit ${eusage}
  fi
}

get_replicas(){
  DEPL=$1
  kubectl get deployment $DEPL -o json | jq -r '.spec.replicas'
}

scale_deployment(){
  OLD_REPLICAS=$(get_replicas $DEPL_TO_SCALE)
  info "$0: Scaling deployment $DEPL_TO_SCALE from $OLD_REPLICAS to $NEWREPLICAS."
  kubectl scale deployment $DEPL_TO_SCALE --replicas=${NEWREPLICAS}
  rc=$?
  if [ ${rc} -ne 0 ]; then
    error "$0: Error during postrestorehook"
    rc=${epostrestore}
  fi

  REPLICAS=$(get_replicas ${DEPL_TO_SCALE})
  if [[ ${REPLICAS} -ne ${NEWREPLICAS} ]]
  then
    error "$0: Error in scaling deployment ${DEPL_TO_SCALE} to ${NEWREPLICAS} replicas."
    rc=${epostrestore}
  else
    info "$0: Succesfully scaled deployment ${DEPL_TO_SCALE} to ${NEWREPLICAS} replicas."
  fi
}

#
# main
#
init
check_input $@
scale_deployment

exit ${rc}
