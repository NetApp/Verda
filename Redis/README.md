# Redis

Pre-and post-snapshot execution hooks that can be used with Redis and NetApp Astra Control.

Tested with Redis version 7.0.10 deployed using Bitnami Helm chart version 17.0.10 and NetApp Astra Control Service 23.10.

args: [pre|post]

pre: For persistence mode RDB, run BGSAVE command creating dump.rdb in Redis data directory. For persistence mode AOF,
turn off automatic rewrites (set auto-aof-rewrite-percentage 0).
post: For persistence mode RDB, delete dump.rdb in Redis data directory. For persistence mode AOF,turn on automatic rewrites again 
(set auto-aof-rewrite-percentage to original value)

| Action/Operation | Supported Stages |               Notes                              |
| -----------------|------------------|--------------------------------------------------|
| Snapshot         | pre              | Action depending on Redis persistence mode       |
|                  | post             | Action depending on Redis persistence mode       |
| Backup           | ---              |                                                  |
|                  | ---              |                                                  |
| Restore          | ---              |                                                  |

## Notes
The execution hook script must be executed in the redis-master pod.
