# Post-Restore URL-Rewrite

Post-restore execution hook to change the container image URL from region A to region B (and/or B to A) after a restore. This is intended for use in situations where container registries are regional, and the original region is no longer available due to a DR scenario.

The order of the region arguments does not matter, the execution hook will match the defined region of the source app/backup/snapshot, and then update the container image to use the other image. This means the same execution hook can be used for both failover and failback.

args: [regionA, regionB]

## Hook arguments

The arguments are explained below:

post: invokes a post-restore operation.

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`<regionA>`: Either the source or destination region

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`<regionB>`: Either the source or destination region

| Action/Operation | Supported Stages |                 Notes                                        |
| -----------------|------------------|--------------------------------------------------------------|
| Restore          | post             | Swap from regionA to regionB (or vice versa) after a restore |

## Defining the hook

To add an execution hook for post-restore image URL rewrites, you will need to:

1. Update the `rewrite-infra.yaml` definition to match the namespace of your application
    1. Optionally update any labels in the same definition to better align with your business practices
1. Apply the `rewrite-infra.yaml` definition to your application namespace
1. Add the `url-rewrite.sh` script to your Astra Control environment
1. Create an execution hook within your Astra Control application with the following settings:
    1. Operation: `Post-restore`
    1. Hook Arguments: *regionA* *regionB* (order does not matter)
    1. Hook filter:
        1. `Container name`: `alpine-astra-hook`
1. Verify the `alpine:latest` container is matched
1. Perform a clone or restore operation
