#!/bin/sh
#
# mariadb_mysql_POSIX.sh
#
# Pre- and post-snapshot execution hooks for MariaDB and MySQL with NetApp
# storage engines.
# Trident protect. Developed with Trident Protect 26.02, MySQL 8.4,
# MariaDB 11.4, and MariaDB 12.2.  Note that MariaDB use is restricted
# to only InnoDB storage engines.
# - MySQL supports the SUPER_READ_ONLY system variable, enabling it to
#   produce database-consistent ONTAP snapshots.
# - MariaDB currently only supports the READ_ONLY system variable. If
#   used with InnoDB tables, it can produce crash-consistent database
#   snapshots. Since all other table types will not be crash-consistent,
#   meaning they are subject to data loss, this script checks for
#   InnoDB storage engine usage and aborts when other storage engine
#   usage is found.
#
# args: {pre|post} <user> <password> [host] [port]
#   pre:  Place the database in read-only mode. Flush all tables with read lock.
#         Intended for use with "pre" stage hooks.
#   post: Take database out of read-only mode. Intended for use with "post"
#         stage hooks.
#
# Notes:
# - <user> must a database account that has admin privileges.
# - This quiesce is instance-wide and covers all databases in the
#   MySQL/MariaDB server.
#
# | Action/Operation | Supported Stages |               Notes                 |
# | -----------------|------------------|-------------------------------------|
# | Snapshot         | pre              | Flush all tables with read lock     |
# |                  | post             | Take database out of read-only mode |
# | Backup           | ---              |                                     |
# |                  | ---              |                                     |
# | Restore          | ---              |                                     |


if [ -n "${BASH_VERSION-}" ]; then
  set -o posix
fi

usage() {
  cat <<'EOF'
Usage:
  mariadb_mysql_new.sh pre  <user> <password> [host] [port]
  mariadb_mysql_new.sh post <user> <password> [host] [port]

Notes:
- Requires privileges to run SET GLOBAL ... (admin user).
- This is instance-wide and covers all schemas in the MySQL server.
EOF
}

if [ "$#" -lt 3 ]; then
  usage
  exit 2
fi

# Find the mysql client
mysqlcmd=$(command -v mariadb)
if [ -z "$mysqlcmd" ]; then
  mysqlcmd=$(command -v mysql)
  if [ -z "$mysqlcmd" ]; then
    echo "Error: No mysql client found!"
    exit 3
  else
    EXTRA_OPTIONS=""  # Usually no extra options are necessary for MySQL.
  fi
else
  # Some MariaDB version complain about SSL certs for client connections.
  # SSL for client connections is not necessary here since the client
  # and server are running in the same pod.
  EXTRA_OPTIONS="--skip-ssl"  # Use if MariDB gripes about missing SSL certs.
fi

ACTION="$1"
USER="$2"
PASS="$3"
HOST="${4:-127.0.0.1}"
PORT="${5:-3306}"

# Prefer env var over putting password on command line flags
# (still visible to the process environment for that process, but avoids -pPASS in argv)
mysql_cmd() {
  #cmdline="MYSQL_PWD=\"${PASS}\" ${mysqlcmd} \
  #  --protocol=tcp \
  #  -h \"${HOST}\" \
  #  -P \"${PORT}\" \
  #  -u \"${USER}\" \
  #  --batch --skip-column-names \
  #  ${EXTRA_OPTIONS} \
  #  \"$@\""

  #date +"%Y-%m-%d %H:%M:%S.%3N" >> /tmp/hooks.log
  #echo $cmdline >> /tmp/hooks.log

  MYSQL_PWD="${PASS}" ${mysqlcmd} \
    --protocol=tcp \
    -h "${HOST}" \
    -P "${PORT}" \
    -u "${USER}" \
    --batch --skip-column-names \
    ${EXTRA_OPTIONS} \
    "$@"
  #echo mysqlcmd exit status = $? >> /tmp/hooks.log
  #date +"%Y-%m-%d %H:%M:%S.%3N" >> /tmp/hooks.log
}

mysql_exec() {
  mysql_cmd -e "$1"
}

wait_for_mysql() {
  # quick connectivity check
  mysql_exec "SELECT 1;" > /dev/null
}

# If this database server supports SUPER_READ_ONLY then return 1,
# else return 0.
# Note: SUPER_READ_ONLY is currently only supported on MySQL.
sro_supported() {
  return $(mysql_exec "SHOW GLOBAL VARIABLES LIKE 'SUPER_READ_ONLY';" | awk 'END { print NR ? 1 : 0 }')
}

# Check for InnoDB data engine usage. Return 0 if InnoDB only, 1 if 
# non-InnoDB found.
innodb_only() {
  return $(mysql_exec "SELECT TABLE_SCHEMA AS database_name, TABLE_NAME AS table_name, TABLE_TYPE AS table_type, ENGINE AS engine FROM information_schema.TABLES WHERE engine <> 'InnoDB' AND table_schema NOT IN ('information_schema', 'mysql', 'performance_schema', 'sys') ORDER BY TABLE_SCHEMA, TABLE_NAME;" | awk 'END { print NR ? 1 : 0 }')
}

quiesce() {
  echo "Quiescing MySQL at ${HOST}:${PORT} ..."
  wait_for_mysql

  # Make the database reject writes (Note: This state persists across
  # client sessions.)
  if sro_supported; then
    # sro_supported returned 0...
    # Check for InnoDB
    if innodb_only; then
      # innodb_only returned 0, so only using InnoDB engine.
      echo Enabling read_only mode...
      # Caution: Since administrators can still write to the database under
      # READ_ONLY mode, it is not possible to guarantee that an ONTAP snapshot
      # taken under this mode will generate a database-consistent snapshot.
      # However, if your database only uses InnoDB tables, then an ONTAP
      # snapshot taken in READ_ONLY mode and used in combination with saved
      # redo/undo logs, captured at the same time, will produce a
      # crash-consistent database backup. InnoDB is designed for this; on
      # restore, it can replay the logs to recover the database from the
      # snapshot.
      # To be clear, this solution only works for InnoDB tables/databases.
      # Other table types will not be crash-consistent and so data loss
      # should be expected.
      mysql_exec "SET GLOBAL read_only = ON;"
      roState=$(mysql_exec "SELECT @@global.read_only;")
      echo read_only state is now $roState
    else
      # innodb_only returned 1, so non-InnoDB engine usage found.
      echo "Error: Found non-InnoDB storage engine usage, aborting quiesce attempt!"
      exit 4
    fi
  else
    # sro_supported returned 1...
    echo Enabling super_read_only mode...
    # SUPER_READ_ONLY prevent writes from all users, including administrators. 
    # This mode is sufficient to produce a database-consistent ONTAP snapshot.
    mysql_exec "SET GLOBAL super_read_only = ON;"
    sroState=$(mysql_exec "SELECT @@global.super_read_only;")
    echo super_read_only state is now $sroState
  fi

  # Encourage flushing/closing so storage snapshot is cleaner
  echo Flushing tables...
  mysql_exec "FLUSH TABLES;"
  echo Flushing logs...
  mysql_exec "FLUSH LOGS;"

  echo "MySQL is now quiesced."
}

unfreeze() {
  echo "Unfreezing MySQL at ${HOST}:${PORT} ..."
  wait_for_mysql

  if sro_supported; then
    # sro_supported returned 0...
    # Check for InnoDB
    if innodb_only; then
      # innodb_only returned 0, so only using InnoDB engine.
      # Make the database accept writes (Note: This state persists across
      # client sessions.)
      echo Disabling read_only mode...
      mysql_exec "SET GLOBAL read_only = OFF;"
      roState=$(mysql_exec "SELECT @@global.read_only;")
      echo read_only state is now $roState
    else
      # innodb_only returned 1, so non-InnoDB engine usage found.
      echo "Error: Found non-InnoDB storage engine usage, aborting unfreeze attempt!"
      exit 4
    fi
  else
    # sro_supported returned 1...
    echo Disabling super_read_only mode...
    mysql_exec "SET GLOBAL super_read_only = OFF;"
    sroState=$(mysql_exec "SELECT @@global.super_read_only;")
    echo super_read_only state is now $sroState
  fi

  echo "MySQL is writable again (unfrozen)."
}

case "${ACTION}" in
  pre)  quiesce ;;
  post) unfreeze ;;
  *) usage; exit 2 ;;
esac
