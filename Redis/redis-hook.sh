#!/bin/bash
#
# redis-hooks.sh
#
# Pre- and post-snapshot execution hooks for Redis to be executed in redis-master pod.
# Tested with Redis version 7.0.10 and NetApp Astra Control Service 23.01.
#
# args: [pre|post]
# pre: For persistence mode RDB, run BGSAVE command creating dump.rdb in Redis data directory. For persistence mode AOF,
# turn off automatic rewrites (set auto-aof-rewrite-percentage 0).
# post: For persistence mode RDB, delete dump.rdb in Redis data directory. For persistence mode AOF,turn on automatic rewrites again 
# (set auto-aof-rewrite-percentage to original value)
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

init(){
  ebase=100
  eusage=$((ebase+1))
  epre=$((ebase+2))
  epost=$((ebase+3))

  # Check if required Redis environment is set:
  if [[ -z $REDIS_PORT || -z $REDIS_PASSWORD ]]; then
    error "REDIS_PORT and/or REDIS_PASSWORD no set, exiting."
    rc=$eusage
    exit ${rc}
  fi

  # Check for existence of redis-cli:
  REDISCMD=$(which redis-cli)
  if [[ -r $REDISCMD && -n $REDISCMD ]]; then
    REDISCLI="$REDISCMD -h localhost -p $REDIS_PORT -a $REDIS_PASSWORD"
  else
    error "redis-cli not found, exiting."
    rc=$eusage
    exit ${rc}
  fi

  DATADIR=$($REDISCLI config get dir | tail -n 1)
  BKUPFILE=$DATADIR/dump.rdb
  REWRITEPCTFILE=$DATADIR/redishook_rewritepct.txt
}

check_input(){
  if [ $# -ne 1 ]
  then
    error "$0: Usage: $0 [pre|post]"
    exit ${eusage}
  fi

  export ACTION=$1

  if [ $ACTION != "pre" ] && [ $ACTION != "post" ]; then
    error "$0: Usage: $0 [pre|post]"
    exit ${eusage}
  fi
}

get_persistence_mode(){
  if [ $($REDISCLI config get appendonly | tail -n 1) = "yes" ]; then
    PERSISTENCE_MODE="AOF"
  else
    PERSISTENCE_MODE="RDB"
  fi
}

#
# Run prehook steps here
#
prehook() {
  if [ $PERSISTENCE_MODE == "RDB" ]; then
    info "Persistence mode: RDB - running BGSAVE"
    # Get UNIX time of last backup:
    let LASTBKUPTIME=$($REDISCLI LASTSAVE | awk '{print $1}')

    # Run BGSAVE:
    $REDISCLI BGSAVE
    
    # Get UNIX time of last backup:
    let NEWBKUPTIME=$($REDISCLI LASTSAVE | awk '{print $1}')

    # Wait for BGSAVE to finish
    while (( $NEWBKUPTIME <= $LASTBKUPTIME )); do
      info "Waiting for BGSAVE to finish, sleeping for 60s"
      sleep 60
      let NEWBKUPTIME=$($REDISCLI LASTSAVE | awk '{print $1}')
    done
    if [ -r $BKUPFILE ]; then
      info "BGSAVE finished"
      rc=0
    else
      error "Error creating backup file $BKUPFILE"
      rc=${epre}
    fi
  else
    info "Persistence mode: AOF - supending automatic rewrites during snapshot"
    ## Get current rewrite-percentage and save it in $REWRITEPCTFILE:
    let REWRITEPERCENT=$($REDISCLI config get auto-aof-rewrite-percentage | tail -n 1)
    printf "$REWRITEPERCENT" > $REWRITEPCTFILE

    # Turn off automatic rewrites:
    CMDOUT=$($REDISCLI config set auto-aof-rewrite-percentage 0)
    if [[ $CMDOUT == "OK" ]]; then
      rc=0
    else
      error "Error setting auto-aof-rewrite-percentage to 0, please check your snapshot/backup"
      rc=${epre}
    fi


    # Wait for rewrites to complete:
    let REWRITEINPROGRESS=$($REDISCLI info persistence | awk -F: '/aof_rewrite_in_progress/ {print $2}' | tr -d '\r')
    while (( $REWRITEINPROGRESS != 0 )); do
      info "Waiting for rewrites to complete"
      sleep 60
      let REWRITEINPROGRESS=$($REDISCLI info persistence | awk -F: '/aof_rewrite_in_progress/ {print $2}' | tr -d '\r')
    done
    rc=0
  fi

  return ${rc}
}

#
# Run posthook steps here
#
posthook() {
  if [ $PERSISTENCE_MODE == "RDB" ]; then
    info "Persistence mode: RDB - deleting old $BKUPFILE"
    rm -f $BKUPFILE
    rc=0
  else
    info "Persistence mode: AOF - re-enabling automatic rewrites after snapshot"
    if [ -r $REWRITEPCTFILE ]; then
      let REWRITEPERCENT=$(cat $REWRITEPCTFILE)
      rm $REWRITEPCTFILE
    else
      info "File $REWRITEPCTFILE with previous auto-aof-rewrite-percentage value not found, setting auto-aof-rewrite-percentage to 100"
      let REWRITEPERCENT=100
    fi
    CMDOUT=$($REDISCLI config set auto-aof-rewrite-percentage $REWRITEPERCENT)
    if [[ $CMDOUT == "OK" ]]; then
      rc=0
    else
      error "Error setting auto-aof-rewrite-percentage to $REWRITEPERCENT, please check"
      rc=${epost}
    fi
  fi
  return ${rc}
}

#
# main
#
init
check_input $@
get_persistence_mode

# log something to stdout
info "Running $0 ${ACTION}"

if [ "${ACTION}" = "pre" ]; then
    prehook
    rc=$?
    if [ ${rc} -ne 0 ]; then
        error "Error during prehook"
        rc=${epre}
    fi
  elif [ "${ACTION}" = "post" ]; then
    posthook
    rc=$?
    if [ ${rc} -ne 0 ]; then
        error "Error during posthook"
        rc=${epost}
    fi
fi

exit ${rc}
