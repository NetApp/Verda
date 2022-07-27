# Verda - Protecting applications with Astra Control

This repo provides guidance on protecting popular Kubernetes applications with NetApp Astra Control by taking app-consistent snapshots and backups.

A snapshot is a point-in-time copy of an app that is stored on the volume used by the app. Snapshots are used to restore the state of an app.

Astra also allows users to create app backups. A backup is stored on object storage in the cloud. A backup can be slower to create when compared to snapshots. They can be accessed across regions in the cloud to enable app migrations. You can also choose a longer retention period for backups.

Some applications might require app-specific steps to be performed. This could be:
* before or after a snapshot is created.
* before or after a backup is created.
* after restoring from a snapshot or backup.

Astra Control can execute app-specific custom scripts called execution hooks.

An execution hook is a custom script that you can be executed when snapshots or backups are created for an app managed by Astra Control. Execution hooks can also be used during app restores. For example, if you have a database app, you can use execution hooks to pause all database transactions before a snapshot, and resume transactions after the snapshot is complete. This ensures application-consistent snapshots.

This repo provides execution hook examples for popular applications to make protecting applications simpler, more robust, and easy to orchestrate.

Furthermore, the repo provides shell script templates to write your own execution hooks.

The execution hooks provided in this repo are provided under **Community Support**. Readers are advised to test them in staging environments before using in production.

## Execution Hook Actions and Stages

| Action/Operation | Supported Stages |               Notes                    |
| -----------------|------------------|----------------------------------------|
| Snapshot         | Pre/Post         |                                        |
| Backup           | Pre/Post-Backup  |                                        |
| Restore          | Post-Restore     |Pre-restore is not needed and supported |

## Adding an Execution Hook

* Discover your Kubernetes cluster.
* Manage the desired application.
* Once the application is managed, select the "Execution hooks" tab.
* Add the execution hook.
* Trigger the execution hook by performing an operation (snapshot, backup, restore).
* Verify its execution in the Activity Window of Astra Control.

## Script Templates for Execution Hooks

The `script-templates` directory contains sample scripts. These can be used to obtain an idea on how to structure your execution hooks. These can be used as templates or example hooks.

| Script template               | Operations performed                                                                 |
| ------------------------------|--------------------------------------------------------------------------------------|
| success_sample                | Simple hook that succeeds and writes a message to standard output and standard error |                                      |
| success_sample_args           | Simple hook that uses arguments                                                      |
| success_sample_pre_post       | Simple hook that can be used for pre-snapshot and post-snapshot operations           |
| failure_sample_verbose        | Handling failures in an execution hook with verbose logging                          |
| failure_sample_arg_exit_code  | Handling failures in an execution hook                                               |
| failure_then_success_sample   | Hook failing on first run and succeeding on the second run                           |

## Troubleshooting failures

* If the execution of a hook fails, the return code is captured and is included in the hook failure event. This is also captured in Astra Control's Activity.
* If a hook script fails, the script's stderr/stdout output is logged in the Nautilus logs. It is important to note that execution hook failures are soft.
* The failure does NOT cause the operation to be tagged as a failure.

## Notes about execution hooks

Consider the following when planning execution hooks for your apps.

 * Astra Control requires execution hooks to be written in the format of executable shell scripts.

 * Script size is limited to 128KB.

 *  Astra Control uses execution hook settings and any matching criteria to determine which hooks are applicable to a snapshot or restore.
    All execution hook failures are soft failures; other hooks and the snapshot/restore are still attempted even if a hook fails. However, when a hook fails, a warning event is recorded in the Activity page event log.

 *  To create, edit, or delete execution hooks, you must be a Astra Control user with Owner, Admin, or Member permissions.

 *  If an execution hook takes longer than 25 minutes to run, the hook will fail, creating an event log entry with a return code of "N/A". Any affected snapshot will time out and be marked as failed, with a resulting event log entry noting the timeout.

    - Since execution hooks often reduce or completely disable the functionality of the application they are running against, you should always try to minimize the time your custom execution hooks take to run.

 *  The current version of Astra Control can only target the containers to execute hooks by image name. The hook will run for any container image that matches the provided regular expression rule in Astra Control., which can result a hooks script being executed multiple times in parallel for the same application. Take this into consideration when developing hook scripts.

    * To figure out an appropriate regular expression for your app’s containers, check the details of the pod(s) and look for the image(s), like below:
    ```bash
    ~ # kubectl get po -n mongodb3
    NAME                        READY   STATUS    RESTARTS   AGE
    mongodb3-54cbd55b54-5nqgh   1/1     Running   0          15h
    ~ # kubectl describe pod/mongodb3-54cbd55b54-5nqgh -n mongodb3 | grep Image:
        Image:          docker.io/bitnami/mongodb:5.0.9-debian-11-r3
    ```

 *  When a snapshot is run, execution hook events take place in the following order:

    -   Any applicable custom pre-snapshot execution hooks are run on the appropriate containers. You can create and run as many custom pre-snapshot hooks as you need, but the order of execution of these hooks before the snapshot is neither guaranteed nor configurable.

    -   The snapshot is performed.

    -   Any applicable custom post-snapshot execution hooks are run on the appropriate containers. You can create and run as many custom post-snapshot hooks as you need, but the order of execution of these hooks after the snapshot is neither guaranteed nor configurable.

    -   Any applicable NetApp-provided default post-snapshot execution hooks are run on the appropriate containers.

 *  Always test your execution hook scripts before enabling them in a production environment. You can use the `kubectl exec` command to conveniently test the scripts. To do so, first upload the hook script you want to test into the pod where it’s supposed to run and then execute like, like in the example below:

  ```bash
  ~ # kubectl cp cassandra-snap-hooks.sh cassandra-0:/tmp -n cassandra
  ~ # kubectl exec -n cassandra --stdin --tty pod/cassandra-0 -- /bin/bash -c  “ls -l /tmp/cassandra*”
  total 416
  -rw-r--r-- 1 1001 root 2288 Jun 29 07:27 cassandra-snap-hooks.sh
  ~ # kubectl exec -n cassandra --stdin --tty pod/cassandra-0 -- /bin/bash -c "/bin/sh -x /tmp/cassandra-snap-hooks.sh pre"
  + ebase=100
  + eusage=101
  + ebadstage=102
  + epre=103
  + epost=104
  + stage=pre
  + [ -z pre ]
  + [ pre != pre ]
  + info Running /tmp/cassandra-snap-hooks.sh pre
  + msg INFO: Running /tmp/cassandra-snap-hooks.sh pre
  + echo INFO: Running /tmp/cassandra-snap-hooks.sh pre
  INFO: Running /tmp/cassandra-snap-hooks.sh pre
  + [ pre = pre ]
  + quiesce
  + info Quiescing Cassandra - flushing all keyspaces and tables
  + msg INFO: Quiescing Cassandra - flushing all keyspaces and tables
  + echo INFO: Quiescing Cassandra - flushing all keyspaces and tables
  INFO: Quiescing Cassandra - flushing all keyspaces and tables
  + nodetool flush
  + rc=0
  + [ 0 -ne 0 ]
  + return 0
  + rc=0
  + [ 0 -ne 0 ]
  + [ pre = post ]
  + exit 0
  ```

After you enable the execution hooks in a production environment, test the resulting snapshots to ensure they are consistent. You can do this by cloning the app to a temporary namespace, restoring the snapshot, and then testing the app.

Execution hooks are available for the following applications:

* [Cassandra](https://github.com/NetApp/execution-hooks/tree/main/Cassandra)
* [Elasticsearch](https://github.com/NetApp/execution-hooks/tree/main/Elasticsearch)
* [MariaDB & MySQL](https://github.com/NetApp/execution-hooks/tree/main/Mariadb-MySQL)
* [MongoDB](https://github.com/NetApp/execution-hooks/tree/main/MongoDB)
* [PostgreSQL](https://github.com/NetApp/execution-hooks/tree/main/PostgreSQL)
* [Redis](https://github.com/NetApp/execution-hooks/tree/main/Redis)
* [Kafka](https://github.com/NetApp/execution-hooks/tree/main/Kafka)
