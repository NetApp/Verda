# Verda - Protecting popular cloud-native K8s applications with Astra Control

This project aims to help users protect popular Kubernetes applications with NetApp Astra Control by taking app-consistent snapshots, backups, and other techniques.

A snapshot is a consistent point-in-time copy of an app that is stored on the volume used by the app. Snapshots are used to restore the state of an app.

Astra Control also allows you to take backups for an offsite copy of your application and its data. A backup can be slower to create when compared to snapshots. Backups can be accessed across data centers and cloud regions to enable disaster recovery and app migrations. You can also choose a longer retention period for backups.

Some applications might require app-specific steps to be performed. This could be:
* before or after a snapshot is created.
* before or after a backup is created.
* after restoring from a snapshot or backup.
* after a failover of an application (Astra Control Center with replication only).

Astra Control can execute app-specific custom scripts called execution hooks.

An execution hook is a custom action coded as a script that can be executed when snapshots or backups are created for an app managed by Astra Control. Execution hooks can also be used during app restores. For example, if you have a database app, you can use execution hooks to pause all database transactions before a snapshot, and resume transactions after the snapshot is complete. This ensures application-consistent snapshots.

This repo provides execution hook examples for popular cloud-native applications to make protecting applications straightforward, robust, and easy to orchestrate.

Furthermore, the repo provides shell script templates to write your own execution hooks.

The execution hooks provided in this repo are provided under **Community Support**. Readers are advised to test them in staging environments before using in production.

User contributions are welcome! Take a look at the [Contribution Guide](#contribution-guide) to get started.

## Execution Hook Actions and Stages

| Action/Operation | Supported Stages |               Notes                    |
| -----------------|------------------|----------------------------------------|
| Snapshot         | Pre/Post         |                                        |
| Backup           | Pre/Post-Backup  |                                        |
| Restore          | Post-Restore     |Pre-restore is not needed and supported |
| Failover         | Post-failover    |ACC with replication only

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

 *  When you add or edit an execution hook to an application, you can add filters to an execution hook to mange which containers the hook will match. Filters are useful for applications that use the same container image on all containers, but might use each image for a different purpose (such as Elasticsearch). Filters enable you to create scenarios where execution hooks will run on some of those identical containers, but not necessarily all of them. If you create multiple filters for a single execution hook, they are combined with a logical AND operator. You can have up to 10 active filters per execution hook.
Each filter you add to an execution hook uses a regular expression to match containers in your cluster. When a hook matches a container, the hook will run its associated script on that container.

    * Regular expressions for filters use the [Regular Expression 2 (RE2)](https://github.com/google/re2/wiki/Syntax) syntax, which does not support creating a filter that excludes containers from the list of matches.

    * The following hook filter types are available:
        - Container image
        - Namespace
        - Pod name
        - Label
        - Container name

 *  When a snapshot or backup is run, execution hook events take place in the following order:

    -   Any applicable pre-snapshot/backup execution hooks are run on the appropriate containers. You can create and run as many custom pre-snapshot/backup hooks as you need, but the order of execution of these hooks before the snapshot is neither guaranteed nor configurable.

    -   The snapshot/backup is performed.

    -   Any applicable post-snapshot/backup execution hooks are run on the appropriate containers. You can create and run as many custom post-snapshot/backup hooks as you need, but the order of execution of these hooks after the snapshot/backup is neither guaranteed nor configurable.
    
 * When a restore is run, any applicable post-restore execution hooks are run on the appropriate containers after a 5min wait time after restore complete. You can create and run as many custom post-restore hooks as you need, but the order of execution of these hooks after the restore is neither guaranteed nor configurable.

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

Protection strategies are available for the following applications:

* [Cassandra](https://github.com/NetApp/execution-hooks/tree/main/Cassandra)
* [Elasticsearch](https://github.com/NetApp/execution-hooks/tree/main/Elasticsearch)
* [MariaDB & MySQL](https://github.com/NetApp/execution-hooks/tree/main/Mariadb-MySQL)
* [MongoDB](https://github.com/NetApp/execution-hooks/tree/main/MongoDB)
* [PostgreSQL](https://github.com/NetApp/execution-hooks/tree/main/PostgreSQL)
* [Redis](https://github.com/NetApp/execution-hooks/tree/main/Redis)
* [Kafka](https://github.com/NetApp/execution-hooks/tree/main/Kafka)
* [YugabyteDB](https://github.com/NetApp/Verda/tree/main/YugabyteDB)
* [Microsoft SQL Server](https://github.com/NetApp/Verda/tree/main/SQLServer2022)

[URL-Rewrite](https://github.com/NetApp/Verda/tree/main/URL-Rewrite) is a post-restore execution hook to change the container image URL from region A to region B (and/or B to A) after a restore. This is intended for use in situations where container registries are regional, and the original region is no longer available due to a DR scenario. The hook can be modified to change other settings after a restore like Ingress.

[Post-restore-scale](https://github.com/NetApp/Verda/tree/main/Post-restore-scale) is a post-restore execution hook to change the number of replicas of deployments in a restored or cloned application after the restore.

## Contribution Guide

If you would like to add execution hooks/protection guidelines for an application to this repository:

1. Create a new branch from `main`.
2. Switch over to your newly created branch and create a new folder for the desired application.
3. Add the execution hook/protection guide.
4. Open a Pull Request. When creating it, please make sure to provide details on the application. This could be the way it is installed, architectural configuration (single master or multiple masters, for example), and so on.
5. Once a Pull Request is created, the proposed contribution can be tested and reviewed.
