# PostgreSQL

Pre- and post-snapshot execution hooks for PostgresSQL with NetApp Astra Control.

Tested with PostgreSQL 16.4.0 deployed by Bitnami helm chart 15.5.36 and NetApp Astra Control Service 24.03.



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
