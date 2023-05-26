# Elasticsearch

Pre- and post-snapshot and post-restore execution hooks for Elasticsearch.

Tested with Elasticsearch 8.6.2 (deployed by Bitnami helm chart 19.6.0) and NetApp Astra Control Service 23.04.

args: [pre|post|postrestore]

pre: Flush all Elasticsearch indices and make indices and index metadata read-only by setting index.blocks.read_only

post: Unset index.blocks.read_only from all indices

postrestore: Unset index.blocks.read_only from all indices

| Action/Operation | Supported Stages |               Notes                                                                                                     |
| -----------------|------------------|-------------------------------------------------------------------------------------------------------------------------|
| Snapshot         | pre              | Flush all Elasticsearch indices and make indices and index metadata read-only by setting index.blocks.read_only.        |
|                  | post             | Unset index.blocks.read_only from all indices.                                                                          |
| Backup           | ---              |                                                                                                                         |
|                  | ---              |                                                                                                                         |
| Restore          | post-restore     | Unset index.blocks.read_only from all indices.                                                                          |


## Notes

After a restore, the post-restore action MUST be executed to make sure `index.blocks.read_only` is set to `false` for all indices of the restored Elasticsearch application.
