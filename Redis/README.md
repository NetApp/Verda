# Redis

A pre-snapshot execution hook that can be used with Redis and NetApp Astra Control.

Tested with Redis version 6.2.7 deployed using Bitnami Helm chart version 16.8.9 and NetApp Astra Control Service 22.04.

args: [pre]

pre: Save the contents of the Redis database by running a background save (BGSAVE).

When creating an app snapshot, the pre-snapshot execution hook creates a `dump.rdb`
file that is stored in the Redis directory (`/data`).

Restoring a Redis database can be achieved by copying the `dump.rdb` file to the
Redis directory and restarting the Redis instance.

| Action/Operation | Supported Stages |               Notes                              |
| -----------------|------------------|--------------------------------------------------|
| Snapshot         | pre              | Runs BGSAVE and creates a dump.rdb file          |
| Backup           | ---              |                                                  |
|                  | ---              |                                                  |
| Restore          | ---              | Manually copy dump.rdb file to config directory  |
