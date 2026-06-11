# MariaDB

Pre- and post-snapshot execution hooks for MariaDB with NetApp Trident Protect.
Tested with MariaDB 11.4, and MariaDB 12.2 and Trident Protect 26.02.
Note that MariaDB use is restricted to only InnoDB storage engines.

args: {pre|post} <user> <password> [host] [port]
  pre:  Place the database in read-only mode. Flush all tables with read lock.
        Intended for use with "pre" stage hooks.
  post: Take database out of read-only mode. Intended for use with "post"
        stage hooks.

Notes:
- <user> must be a database account that has admin privileges.
- This quiesce is instance-wide and covers all databases in the
  MariaDB server.

| Action/Operation | Supported Stages |               Notes                 |
| -----------------|------------------|-------------------------------------|
| Snapshot         | pre              | Flush all tables with read lock     |
|                  | post             | Take database out of read-only mode |
| Backup           | ---              |                                     |
|                  | ---              |                                     |
| Restore          | ---              |                                     |
