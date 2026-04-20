#!/usr/bin/env bash
set -euo pipefail
#
# mariadb_mysql.sh
#
# Pre- and post-snapshot execution hooks for MariaDB and MySQL with NetApp Trident protect.
# Tested with MySQL 8.4 and NetApp Trident protect 26.02.
#
# args: {quiesce|unfreeze} <user> <password> [host] [port]
# quiesce: Flush all tables with read lock
# unfreeze: Take database out of read-only mode
#
# Notes:
# - Requires privileges to run SET GLOBAL ... (admin user).
# - This is instance-wide and covers all schemas in the MySQL server.

usage() {
  cat <<'EOF'
Usage:
  mysql-quiesce.sh quiesce  <user> <password> [host] [port]
  mysql-quiesce.sh unfreeze <user> <password> [host] [port]

Notes:
- Requires privileges to run SET GLOBAL ... (admin user).
- This is instance-wide and covers all schemas in the MySQL server.
EOF
}

if [[ $# -lt 3 ]]; then
  usage
  exit 2
fi

ACTION="$1"
USER="$2"
PASS="$3"
HOST="${4:-127.0.0.1}"
PORT="${5:-3306}"

# Prefer env var over putting password on command line flags
# (still visible to the process environment for that process, but avoids -pPASS in argv)
MYSQL_BASE=( mysql
  --protocol=tcp
  -h "${HOST}"
  -P "${PORT}"
  -u "${USER}"
  --batch --skip-column-names
)

mysql_exec() {
  local sql="$1"
  MYSQL_PWD="${PASS}" "${MYSQL_BASE[@]}" -e "${sql}"
}

wait_for_mysql() {
  # quick connectivity check
  mysql_exec "SELECT 1;" >/dev/null
}

quiesce() {
  echo "Quiescing MySQL at ${HOST}:${PORT} ..."
  wait_for_mysql

  # Make the instance reject writes (persists across sessions)
  mysql_exec "SET GLOBAL super_read_only = ON;"
  mysql_exec "SET GLOBAL read_only = ON;"

  # Encourage flushing/closing so storage snapshot is cleaner
  mysql_exec "FLUSH TABLES;"
  mysql_exec "FLUSH LOGS;"

  # Optional: show state for logs
  mysql_exec "SELECT @@global.read_only, @@global.super_read_only;"
  echo "MySQL is now read-only (quiesced)."
}

unfreeze() {
  echo "Unfreezing MySQL at ${HOST}:${PORT} ..."
  wait_for_mysql

  # Re-enable writes
  mysql_exec "SET GLOBAL super_read_only = OFF;"
  mysql_exec "SET GLOBAL read_only = OFF;"

  mysql_exec "SELECT @@global.read_only, @@global.super_read_only;"
  echo "MySQL is writable again (unfrozen)."
}

case "${ACTION}" in
  quiesce)  quiesce ;;
  unfreeze) unfreeze ;;
  *) usage; exit 2 ;;
esac
