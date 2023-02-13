# SQL Server

Pre- and post-snapshot and post-restore execution hooks for Microsoft SQL Server.

Tested with Microsoft SQL Server 2022 (RTM) - 16.0.1000.6 (X64) and NetApp Astra Control Service 23.01

args: [pre|post|postrestore]

pre: Sets all user databases READ_ONLY by issuing "ALTER DATABASE ${db} SET READ_ONLY WITH ROLLBACK IMMEDIATE"

post: Sets all user databases READ_WRITE again

postrestore: Sets all user databases READ_WRITE again

| Action/Operation | Supported Stages |               Notes                                                                                                     |
| -----------------|------------------|-------------------------------------------------------------------------------------------------------------------------|
| Snapshot         | pre              | Sets all user databases READ_ONLY by issuing "ALTER DATABASE ${db} SET READ_ONLY WITH ROLLBACK IMMEDIATE"               |
|                  | post             | Sets all user databases READ_WRITE again                                                                                |
| Backup           | ---              |                                                                                                                         |
|                  | ---              |                                                                                                                         |
| Restore          | post-restore     | Sets all user databases READ_WRITE again                                                                                |

## Notes

After a restore, the post-restore action MUST be executed to make sure the user databases are writeable.
