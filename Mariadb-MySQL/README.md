# MariaDB/MySQL

Pre- and post-snapshot hooks for MariaDB and MySQL with NetApp Astra Control.

Tested with MySQL 8.0.29 (deployed by Bitnami helm chart 9.1.7)/MariaDB 10.6.8 (deployed by Bitnami helm chart 11.0.13) and NetApp Trident protect 24.10.

args: [pre|post]

pre: Flush all tables with read lock

post: Take database out of read-only mode

| Action/Operation | Supported Stages |               Notes                 |
| -----------------|------------------|-------------------------------------|
| Snapshot         | pre              | Flush all tables with read lock     |
|                  | post             | Take database out of read-only mode |
| Backup           | ---              |                                     |
|                  | ---              |                                     |
| Restore          | ---              |                                     |

Note: Due to the design of this hook and the Trident protect execution hook architecture, this hook will wait in the pre-stage until the hook timeout (default 25min) expires. You may think about reducing spec.timeout to a lower value when configuring this hook in your cluster.
