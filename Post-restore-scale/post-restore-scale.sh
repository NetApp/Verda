#!/bin/sh 
#

# post-restore-scale.sh
#
# Pre- and post-snapshot and post-restore execution hooks for Elasticsearch.
# Tested with NGINX and NetApp Astra Control Service 23.07.
#
# args: [<deployment>=<# of replicas> <deployment>=<# of replicas> .... <deployment>=<# of replicas>]
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
    error "$0: kubectl command not found, exiting."
    rc=$eusage
    exit ${rc}
  fi
  
  # Get list of existing deployments:
  DEPLOYMENTS=$(kubectl get deployments -o custom-columns=NAME:.metadata.name | grep -v NAME)
}

check_input(){
  if [[ $# -lt 1 ]]
  then
    error "$0: Usage: $0 [<deployment>=<# of replicas> <deployment>=<# of replicas> ... <deployment>=<# of replicas>]"
    exit ${eusage}
  fi

  for kv in "$@"
  do
    if [[ ${kv} =~ "=" ]]
    then
      DEPL_TO_SCALE=$(python -c "print(\"${kv}\".split('=')[0])")
      NEWREPLICAS=$(python -c "print(\"${kv}\".split('=')[1])")

      if [[ $NEWREPLICAS -lt 0 ]]
      then
        error "$0: $DEPL_TO_SCALE - Number of new replicas must be >= 0"
        exit ${eusage}
      fi

      if exists_in_list "${DEPLOYMENTS}" " " "${DEPL_TO_SCALE}"
      then
        info "$0: Deployment $DEPL_TO_SCALE found."
      else
        error "$0: Deployment $DEPL_TO_SCALE does not exist."
        exit ${eusage}
      fi
    else
      error "$0: Usage: $0 [<deployment>=<# of replicas> <deployment>=<# of replicas> ... <deployment>=<# of replicas>]"
      exit ${eusage}
    fi
  done
}

get_replicas(){
  DEPL=$1
  kubectl get deployment $DEPL -o json | jq -r '.spec.replicas'
}

scale_deployment(){
  deployment=$1
  replicas=$2
  ORIG_REPLICAS=$(get_replicas $deployment)
  info "$0: Scaling deployment $deployment from $ORIG_REPLICAS to $replicas."
  kubectl scale deployment $deployment --replicas=${replicas}
  rc=$?
  if [ ${rc} -ne 0 ]; then
    error "$0: Error during postrestorehook"
    rc=${epostrestore}
  fi

  # Annotate deployment with original number of replicas
  kubectl annotate deployment ${deployment} original-replicas=${ORIG_REPLICAS} --overwrite

  ACTREPLICAS=$(get_replicas ${deployment})
  if [[ ${ACTREPLICAS} -ne ${replicas} ]]
  then
    error "$0: Error in scaling deployment ${deployment} to ${replicas} replicas."
    rc=${epostrestore}
  else
    info "$0: Succesfully scaled deployment ${deployment} to ${replicas} replicas."
  fi
}

#
# main
#
init
check_input $@

for kv in "$@"
do
  DEPL_TO_SCALE=$(python -c "print(\"${kv}\".split('=')[0])")
  NEWREPLICAS=$(python -c "print(\"${kv}\".split('=')[1])")
  scale_deployment ${DEPL_TO_SCALE} ${NEWREPLICAS}
done

exit ${rc}
