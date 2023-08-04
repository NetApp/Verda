# Post-Restore Scale

Post-restore execution hook to scale a deployment down or up after a restore or clone operation.

args: [ <deployment>, <# of replicas> ]

## Hook arguments

The arguments are explained below:

post: invokes a post-restore operation.

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`<deployment>`: Deployment to scale up or down

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`<# of replicas>`: New number of replicas (>= 0) 

| Action/Operation | Supported Stages |                 Notes                                        |
| -----------------|------------------|--------------------------------------------------------------|
| Restore          | post             | Swap from regionA to regionB (or vice versa) after a restore |

## Defining the hook

To add an execution hook for post-restore image URL rewrites, you will need to:

1. Update the `scale-infra.yaml` definition to match the namespace of your application
    1. Optionally update any labels in the same definition to better align with your business practices
1. Apply the `scale-infra.yaml` definition to your application namespace
1. Add the `post-restore-scale.sh` script to your Astra Control environment
1. Create an execution hook within your Astra Control application with the following settings:
    1. Operation: `Post-restore`
    1. Hook Arguments: *deployment* *replicas*
    1. Hook filter:
        1. `Container name`: `alpine-astra-hook`
1. Verify the `alpine:latest` container is matched
1. Perform a clone or restore operation