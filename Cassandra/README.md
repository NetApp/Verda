# Cassandra

Pre- and post-snapshot execution hooks for Cassandra.

Tested with: Cassandra 4.0.4 (deployed by Bitnami helm chart 9.2.5) and NetApp Astra Control Service 22.04.

args: [pre|post]

pre: flush all keyspaces and tables by "nodetool flush"

post: check all tables ("nodetool verify")

| Action/Operation | Supported Stages |               Notes                                                                               |
| -----------------|------------------|---------------------------------------------------------------------------------------------------|
| Snapshot         | pre              | Flush all keyspaces and tables by "nodetool flush" before starting the snapshot operation.        |                                |
|                  | post             | Check all tables (`nodetool verify`) after the snapshot has been created.                         |
| Backup           | ---              |                                                                                                   |
|                  | ---              |                                                                                                   |
| Restore          | ---              |                                                                                                   |


## Notes

A restore operation to a new namespace or cluster requires that the original instance of the Cassandra application to be taken down. This is to ensure that the peer group information carried over does not lead to cross-instance communication. Cloning of the app will not work.
