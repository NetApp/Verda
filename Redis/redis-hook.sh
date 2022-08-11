# ~ cat redis_hook.sh
#!/bin/sh
#
#
#
# Execution hooks for Redis
#
# args: [pre]

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

set_defaults(){
  ebase=100
  eusage=$((ebase+1))
  epre=$((ebase+2))
  epost=$((ebase+3))
}

check_input(){
  if [ $# -ne 1 ]
  then
    error "$0: Usage: $0 [pre]"
    exit ${eusage}
  fi

  export ACTION=$1

  if [ $ACTION != "pre" ]; then
    error "$0: Usage: $0 [pre]"
    exit ${eusage}
  fi
}
#
# Run prehook steps here
#
prehook() {
    redis-cli -a $REDIS_PASSWORD BGSAVE
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
        error "Error during prehook"
    fi
fi
exit ${rc}
