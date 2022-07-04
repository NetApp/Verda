# PostgreSQL

Pre- and post-snapshot execution hooks for PostgresSQL with NetApp Astra Control.

Tested with PostgreSQL 14.4.0 deployed by Bitnami helm chart 11.6.7 and NetApp Astra Control Service 22.04.



args: [pre|post]

pre: Lock all tables and start pg_start_backup()

post: Take database out of read-only mode

| Action/Operation | Supported Stages |               Notes                              |
| -----------------|------------------|--------------------------------------------------|
| Snapshot         | pre              | Lock all tables and start pg_start_backup()      |
|                  | post             | Take database out of read-only mode              |
| Backup           | ---              |                                                  |
|                  | ---              |                                                  |
| Restore          | ---              |                                                  |
