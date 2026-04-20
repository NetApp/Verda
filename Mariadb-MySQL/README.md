# MariaDB/MySQL

Pre- and post-snapshot execution hooks for MariaDB and MySQL with NetApp Trident protect.
Tested with MySQL 8.4 and NetApp Trident protect 26.02.

args: {quiesce|unfreeze} <user> <password> [host] [port]
quiesce: Flush all tables with read lock
unfreeze: Take database out of read-only mode

| Action/Operation | Supported Stages |               Notes                 |
| -----------------|------------------|-------------------------------------|
| Snapshot         | pre              | Flush all tables with read lock     |
|                  | post             | Take database out of read-only mode |
| Backup           | ---              |                                     |
|                  | ---              |                                     |
| Restore          | ---              |                                     |

Notes:
- Requires privileges to run SET GLOBAL ... (admin user).
- This is instance-wide and covers all schemas in the MySQL server.
