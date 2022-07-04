# MongoDB

Pre- and post-snapshot execution hooks for MongoDB.

Tested with: Cassandra 5.0.8 (deployed by Bitnami helm chart) and NetApp Astra Control Service 22.04.

args: [pre|post]

pre: Lock and flush writes to disk with fsyncLock()

post: Unlock database with fsyncUnlock()

| Action/Operation | Supported Stages |               Notes                           |
| -----------------|------------------|-----------------------------------------------|
| Snapshot         | pre              | Flush all writes to disk and lock application |
|                  | post             | Allow writes by unlocking database            |
| Backup           | ---              |                                               |
|                  | ---              |                                               |
| Restore          | ---              |                                               |


## Notes

The current version of Astra Control can only target the containers to execute hooks by image name. The hook will run for any container image that matches the provided regular expression rule in Astra Control.
