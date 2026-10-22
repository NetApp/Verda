# Verda - Protecting popular cloud-native Kubernetes applications with NetApp Trident Protect and NetApp Backup and Recovery

This project helps users protect popular Kubernetes applications with NetApp Trident Protect and NetApp Backup and Recovery for Kubernetes by taking app-consistent snapshots and backups, and helps automate NetApp Backup and Recovery operations through its API.

The scripts and examples in this repository are provided as-is and are not officially supported by NetApp. NetApp support covers only the execution hooks framework within Trident Protect and Backup and Recovery, and the documented NetApp Console API. Everything in this repository is provided under **Community Support**. Test it in a staging environment before using it in production.

User contributions are welcome! See the [Contribution Guide](#contribution-guide) to get started.

## What's in this repository

| Content | Location | Description |
| ------- | -------- | ----------- |
| **Execution hooks for applications** | One folder per application, for example [`MySQL/`](MySQL), [`PostgreSQL/`](PostgreSQL) | Pre/post hooks for app-consistent snapshots and backups |
| **Execution hook script templates** | [`script-templates/`](script-templates) | Starting points for writing your own hooks |
| **Post-restore hooks** | [`URL-Rewrite/`](URL-Rewrite), [`Post-restore-scale/`](Post-restore-scale) | Adjust an application after a restore or clone |
| **Backup and Recovery API automation** | [`BnR-API/`](BnR-API/README.md) | Example `curl`/`jq` commands and scripts to automate NetApp Backup and Recovery through the NetApp Console API, including protection policy creation and deletion |

## Backup and Recovery API automation

The [`BnR-API`](BnR-API/README.md) folder collects example commands to automate NetApp Backup and Recovery operations without the Console UI:

- [Authentication](BnR-API/00-authentication/README.md): create an access token from a refresh token
- [Account discovery](BnR-API/01-account-discovery/README.md): find account, workspace/project and agent IDs
- [Credentials and backup targets](BnR-API/02-credentials-and-targets): Azure, AWS S3, ONTAP S3 and StorageGRID
- [Cluster onboarding](BnR-API/03-cluster-onboarding/README.md): OCCM credentials, Trident Protect installation, listing discovered clusters
- [Protection policies](BnR-API/04-protection-policies/README.md): create and delete snapshot, backup, replication and 3-2-1 fan-out policies for Azure, AWS S3, ONTAP S3 and StorageGRID (untested) targets

## Protecting applications with execution hooks

A snapshot is a consistent point-in-time copy of an app that is stored on the volume used by the app. Snapshots are used to restore the state of an app.

Trident Protect also allows you to take backups for an offsite copy of your application and its data. A backup can be slower to create when compared to snapshots. Backups can be accessed across data centers and cloud regions to enable disaster recovery and app migrations. You can also choose a longer retention period for backups.

Some applications might require app-specific steps to be performed:

- before or after a snapshot is created.
- before or after a backup is created.
- after restoring from a snapshot or backup.
- after a failover of an application (Astra Control Center with replication only).

Trident Protect and Backup and Recovery can execute app-specific custom scripts called execution hooks.

An execution hook is a custom action coded as a script that can be executed when snapshots or backups are created for an app managed by Trident Protect. Execution hooks can also be used during app restores. For example, if you have a database app, you can use execution hooks to pause all database transactions before a snapshot, and resume transactions after the snapshot is complete. This ensures application-consistent snapshots.

This repo provides execution hook examples for popular cloud-native applications to make protecting applications straightforward, robust, and easy to orchestrate. It also provides shell script templates to write your own execution hooks.

### Execution Hook Actions and Stages

| Action/Operation | Supported Stages | Notes                                             |
| ---------------- | ---------------- | ------------------------------------------------- |
| Snapshot         | Pre/Post         |                                                   |
| Backup           | Pre/Post-Backup  |                                                   |
| Restore          | Post-Restore     | Pre-restore is not needed and supported           |
| Failover         | Post-failover    | Trident protect with snap-mirror replication only |

### Adding an Execution Hook

- Define the desired application in Trident Protect.
- Once the application is defined, create the execution hooks for the application following the [Trident Protect documentation](https://docs.netapp.com/us-en/trident/trident-protect/trident-protect-use-execution-hooks.html#create-an-execution-hook).
- Trigger the execution hook by performing the respective operation (snapshot, backup, restore).
- Verify its execution in the status output of the respective operation's custom resource and/or in the status output of the corresponding exechooksrun CR.

### Script Templates for Execution Hooks

The `script-templates` directory contains sample scripts. Use them as templates or example hooks.

| Script template                  | Operations performed                                                                 |
| -------------------------------- | ------------------------------------------------------------------------------------ |
| success\_sample                  | Simple hook that succeeds and writes a message to standard output and standard error |
| success\_sample\_args            | Simple hook that uses arguments                                                      |
| success\_sample\_pre\_post       | Simple hook that can be used for pre-snapshot and post-snapshot operations           |
| failure\_sample\_verbose         | Handling failures in an execution hook with verbose logging                          |
| failure\_sample\_arg\_exit\_code | Handling failures in an execution hook                                               |
| failure\_then\_success\_sample   | Hook failing on first run and succeeding on the second run                           |

### Troubleshooting failures

- If the execution of a hook fails, the return code is captured and is included in the hook failure event and captured in the operation's CR status.
- If a hook script fails, the script's stderr/stdout output is logged in the operation's CR status.
- Execution hook failures are soft. The failure does NOT cause the operation to be tagged as a failure.

### Notes about execution hooks

Consider the following when planning execution hooks for your apps.

 * Trident Protect requires execution hooks to be written in the format of executable shell scripts.

 * Script size is limited to 96kB.

 * Trident protect uses execution hook settings and any matching criteria to determine which hooks are applicable to a snapshot or restore.
All execution hook failures are soft failures; other hooks and the snapshot/restore are still attempted even if a hook fails. However, when a hook fails, a warning event is recorded in the operation's CR status.

 *  When creating an execution hook CR, you can define the timeout as a number defining how long in minutes that the execution hook is allowed to run. The minimum value is 1 minute, and the default value is 25 minutes if not specified. If an execution hook takes longer than the timeout to run, the hook will fail, creating an entry in the hook operation's CR. Any affected snapshot will time out and be marked as failed, with a resulting event log entry noting the timeout.

    - Since execution hooks often reduce or completely disable the functionality of the application they are running against, you should always try to minimize the time your custom execution hooks take to run.

 *  When you add an execution hook to an application, you can add filters to an execution hook to mange which containers the hook will match. Filters are useful for applications that use the same container image on all containers, but might use each image for a different purpose (such as Elasticsearch). Filters enable you to create scenarios where execution hooks will run on some of those identical containers, but not necessarily all of them. If you create multiple filters for a single execution hook, they are combined with a logical AND operator. You can have up to 10 active filters per execution hook.
Each filter you add to an execution hook uses a regular expression to match containers in your cluster. When a hook matches a container, the hook will run its associated script on that container.

* Regular expressions for filters use the [Regular Expression 2 (RE2)](https://github.com/google/re2/wiki/Syntax) syntax, which does not support creating a filter that excludes containers from the list of matches.

    * The following hook filter types are available in Trident Protect:
        - Container image
        - Namespace name
        - Pod name
        - Pod label
        - Container name

 *  When a snapshot or backup is run, execution hook events take place in the following order:

    -   Any applicable pre-snapshot/backup execution hooks are run on the appropriate containers. You can create and run as many custom pre-snapshot/backup hooks as you need, but the order of execution of these hooks before the snapshot is neither guaranteed nor configurable.

    -   The snapshot/backup is performed.

    -   Any applicable post-snapshot/backup execution hooks are run on the appropriate containers. You can create and run as many custom post-snapshot/backup hooks as you need, but the order of execution of these hooks after the snapshot/backup is neither guaranteed nor configurable.
    
* Post-restore hooks will wait for up to 5 minutes for the pods to be ready, if they are not ready within 5 minutes Trident Protect will try to run the post-restore hooks anyway.

* You can create and run as many custom post-restore hooks as you need, but the order of execution of these hooks after the restore is neither guaranteed nor configurable.
    
 *  Always test your execution hook scripts before enabling them in a production environment. You can use the `kubectl exec` command to conveniently test the scripts. To do so, first upload the hook script you want to test into the pod where it’s supposed to run and then execute it, like in the example below:

 ```bash
  kubectl cp cassandra-snap-hooks.sh cassandra-0:/tmp -n cassandra
  kubectl exec -n cassandra --stdin --tty pod/cassandra-0 -- /bin/bash -c  'ls -l /tmp/cassandra*'
  total 416
  -rw-r--r-- 1 1001 root 2288 Jun 29 07:27 cassandra-snap-hooks.sh
  kubectl exec -n cassandra --stdin --tty pod/cassandra-0 -- /bin/bash -c '/bin/sh -x /tmp/cassandra-snap-hooks.sh pre'
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

### Applications with protection strategies

- [Cassandra](Cassandra)
- [Elasticsearch](Elasticsearch)
- [MariaDB](MariaDB)
- [MySQL](MySQL)
- [MongoDB](MongoDB)
- [PostgreSQL](PostgreSQL)
- [Redis](Redis)
- [Kafka](Kafka)
- [YugabyteDB](YugabyteDB)
- [Microsoft SQL Server](SQLServer2022)

[URL-Rewrite](URL-Rewrite) is a post-restore execution hook to change the container image URL from region A to region B (and/or B to A) after a restore. This is intended for situations where container registries are regional and the original region is no longer available due to a DR scenario. The hook can be modified to change other settings after a restore, like Ingress. Note that the new resource transformations in Trident Protect and Backup and Recovery might provide an easier way to change settings after a restore.

[Post-restore-scale](Post-restore-scale) is a post-restore execution hook to change the number of replicas of deployments in a restored or cloned application after the restore. Note that the new resource transformations in Trident Protect and Backup and Recovery might provide an easier way to change settings after a restore.

## Contribution Guide

### Contributing execution hooks or protection guidelines

1. Create a new branch from `main`.
2. Switch to your new branch and create a new folder for the application.
3. Add the execution hook/protection guide.
4. Open a Pull Request. Provide details on the application, such as how it is installed and its architectural configuration (single master or multiple masters, for example).
5. Once the Pull Request is created, the proposed contribution can be tested and reviewed.

### Contributing Backup and Recovery API examples

1. Create a new branch from `main`.
2. Add your examples under [`BnR-API/`](BnR-API/README.md), either as a new page in an existing section or as a new numbered section folder.
3. Follow the page structure: purpose, required variables, command, verification (no example output).
4. Use placeholders only. Never commit real IDs, hostnames, keys, tokens or secrets.
5. Mention the NetApp Console / Trident Protect version and date you tested with, and mark untested commands as "Untested".
6. Run `shellcheck` on any shell script.
7. Open a Pull Request describing what the commands do and the environment you tested them in.
