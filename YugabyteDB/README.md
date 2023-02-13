# YugabyteDB

Pre-snapshot and post-restore execution hooks for YugabyteDB.

Tested with: YugabyteDB version 2.17.0.0-b24 (deployed with Helm chart)

Instructions for deployment: https://docs.yugabyte.com/preview/deploy/kubernetes/

args: [pre <master-addresses> <db-name> | post <master-addresses> <yugabyte-snapshot-UUID>]

Hook arguments
--------------

The arguments are explained below:

pre: invokes a pre-snapshot operation.

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`<master-addresses>`: A comma-separated list of master IP addresses. Example: "10.240.0.195,10.240.0.141,10.240.0.38"

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`<db-name>`: The name of the database.

post: invokes a post-restore operation.

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`<yugabyte-snapshot-UUID>`: The unique identifier of the YugabyteDB snapshot that must be restored.


| Action/Operation | Supported Stages |               Notes                                        |
| -----------------|------------------|------------------------------------------------------------|
| Snapshot         | pre              | Create a snapshot on the desired database                  |
| Restore          | post             | Restore a database to state referenced by desired snapshot |

Defining the hook
-----------------

To add execution hook(s) for an instance of YugabyteDB, you will need to:

1. Discover the application. Identify the namespace your YugabyteDB deployment is present in. [Define](https://docs.netapp.com/us-en/astra-control-service/use/manage-apps.html#define-apps)
   the YugabyteDB application.
2. Click the application instance. Under the "Execution Hooks" tab, Click "Add".
3. Provide the appropriate operation ("Pre-snapshot" or "Post-restore"), the hook arguments, and a name for the hook.
   For example, a Pre-Snapshot hook invocation may have the arguments "pre 10.240.0.195,10.240.0.141,10.240.0.38 yb_demo".
4. **IMPORTANT:** Add a Hook Filter. Since YugabyteDB contains master and tablet server processes, the execution hook must be run on a single pod.
   One option is to choose the "Pod name" Hook filter type. In this manner, the name of a YB Master pod can be provided.
5. Define the script (`yugabyte-hooks.sh`).
6. Repeat the steps for defining additional execution hooks.
