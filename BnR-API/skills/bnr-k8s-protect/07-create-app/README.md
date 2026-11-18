# Create and protect an application

Create an application in Backup and Recovery for Kubernetes and, optionally, assign a protection policy to it.

Script: [`create-app-API.sh`](scripts/create-app-API.sh)

Tested live 2026-11-11 on an OpenShift cluster: create and protect of a namespace-based application, HTTP 201 for both calls. Retested 2026-11-16 with Trident Protect 100.2610.1 and an Azure disk-to-object policy: HTTP 201 for both calls, and on the cluster the Application CR, a schedule, a snapshot and a running backup appeared within a minute. Right after the call the CR reports `protectionState: Partial` with the detail "Scheduled backup unavailable" until the first backup completes. Protecting through the API does not add the `protect.trident.netapp.io/protection-*` annotations to the CR. The first backup completed (about 3 minutes for a small test namespace) and objects appeared in the Azure container. Label selectors, the `virtual-machine-label-selector` app type, `--site-prefix` and `--policy-file` are untested.

Run the commands below from this section's `scripts/` folder (`cd scripts`).

## Prerequisites

- [Authentication](../00-authentication/README.md) and [account discovery](../01-account-discovery/README.md) completed.
- A discovered cluster, see [cluster onboarding](../05-cluster-onboarding/README.md).
- A protection policy, see [protection policies](../06-protection-policies/README.md).

## Required variables

```bash
export ACCESS_TOKEN="<access_token>"       # BEARER_TOKEN is accepted as an alias
export ACCOUNT_ID="<account_public_id>"    # ORG_ID is accepted as an alias
export AGENT_ID="<console_agent_id>"
export CONSOLE_API="https://cloudmanager.cloud.netapp.com"   # API_HOST is accepted as an alias
```

## Create the application

```bash
./create-app-API.sh --cluster-name "<cluster_name>" --app-name "<app_name>" \
  --namespaces "<namespace>" --policy-name "<policy_name>"
```

`--policy-name` is optional. Without it the script only creates the application (unprotected): there is no policy lookup and no protect request. To protect it later, assign a policy in the Console or send the protect request shown at the end of the script output. Tested live 2026-11-16: create without a policy (HTTP 201, state `discovering`, `unprotected`), then a `POST .../apps/<app_id>/protect` with `{"policyName", "policyId"}` (HTTP 201; the response shows `protectionState: "protecting"`, the app state `ready`, and a `protectionJobID`).

```bash
./create-app-API.sh --cluster-name "<cluster_name>" --app-name "<app_name>" --namespaces "<namespace>"
```

### Other ways to protect an application

An application without a policy can be protected in three ways:

1. **Console:** assign a protection policy to the application.
2. **API:** `POST .../v1/workloads/k8s/apps/<app_id>/protect` with `{"policyName", "policyId"}`, which is what the script does after creating the application.
3. **Annotations on the Application custom resource**, documented by NetApp under [Add and protect a new Kubernetes application](https://docs.netapp.com/us-en/data-services-backup-recovery/br-use-protect-kubernetes-applications.html#add-and-protect-a-new-kubernetes-application), "Add a namespace-based app (CR)":
   - `protect.trident.netapp.io/protection-command`: `protect` or `unprotect`
   - `protect.trident.netapp.io/protection-policy-name`: the name of a Backup and Recovery protection policy that already exists

   Tested when the application is created with the Trident protect CLI (March 2026, Trident protect CLI on an OpenShift cluster, policy of type disk-to-object). Protection starts immediately, and Backup and Recovery creates the app vault and the schedules. See the NetApp Community post [CLI support in NetApp Backup and Recovery for Kubernetes](https://community.netapp.com/community/discussion/466046/cli-support-in-netapp-backup-and-recovery-for-kubernetes), section "Create and protect applications with the CLI":

   ```bash
   tridentctl-protect create application <app_name> --namespaces <namespace> -n <namespace> \
     --annotation protect.trident.netapp.io/protection-policy-name=<policy_name> \
     --annotation protect.trident.netapp.io/protection-command=protect
   ```

   The same annotations can be set in an Application CR (`kind: Application`, `apiVersion: protect.trident.netapp.io/v1`) before applying it with `kubectl apply -f`. The policy must already exist in Backup and Recovery.

   For an application that already exists, NetApp's documentation shows `kubectl annotate` for adding annotations to the application CR (its example sets a different annotation). Adapted to these two. Tested 2026-11-16 for `protection-command="unprotect"` on an application that was protected through the API: after the annotation, `kubectl get schedules` showed no schedules in the namespace, the Console showed the application as unprotected, and the completed backup (reclaim policy `Retain`) and snapshot stayed on the cluster. Then `protection-command="protect"` together with `protection-policy-name="<policy>"` and `--overwrite` on the same application restarted protection: a new schedule appeared within seconds, the Console showed the application as protected again, and the backup took about 3 minutes (small test namespace). Both annotations were tested on an application created with `create-app-API.sh`:

   ```bash
   kubectl annotate application -n <application_cr_namespace> <application_cr_name> \
     protect.trident.netapp.io/protection-command="protect" \
     protect.trident.netapp.io/protection-policy-name="<policy_name>"
   ```

   The Community post shows that an application created in the Console UI also has an Application CR in its namespace (same name as the application), so an application created with `create-app-API.sh` has one too: verified 2026-11-16, the CR `pu-test-app` appeared in the namespace `pu-alpine` (check with `kubectl get application -A`). The annotations act on that CR (see above).

The script prints these options after it creates an application without a policy.

Add `--dry-run` to print the create and protect requests without sending them. The cluster and policy lookups still run.

Further options: `--label-selectors`, `--app-type virtual-machine-label-selector` with the VM freeze flags, and `--site-prefix` with `--policy-file` to look up several policies by prefixed name. Run `./create-app-API.sh --help` for all options.

The API response is saved to `RESPONSE_FILE` (default: a new private temporary file; the path is printed).

## Verify

Check in the Console, under Backup and Recovery for Kubernetes, that the application is listed with its policy.

## Check that the first backup succeeded

HTTP 201 from the protect call and `protectionState: "protecting"` in the response only mean that protection was accepted. Check the result on the cluster:

```bash
kubectl get schedules,backups,snapshots -n <namespace>
kubectl describe backup <backup_name> -n <namespace>
```

What a successful run looks like (Azure disk-to-object policy, small test namespace, 2026-11-17): the schedule appears within seconds, the snapshot is `Completed` after about 25 seconds and the backup after about 3 minutes 20 seconds. While the first backup runs, the Application CR has no `protection-state` annotation, and its `status` shows `protectionState: Partial`, `protectionHealthState: Unhealthy` and the detail "Scheduled backup unavailable". When the backup completes, the annotations become `protect.trident.netapp.io/protection-state: Protected` (with `protection-state-at`, an empty `protection-state-msg` and `protection-state-policy-name`), and `status` shows `protectionState: Protected` and `protectionHealthState: Healthy`. The annotation times are UTC.

Example of a failure (2026-11-17): the snapshot was `Completed`, but the backup was `Failed` with the error `Backup for one or more of the application's volumes failed. Error: CBSRelationship pvc-... could not be established; ... Failed to perform modify panoramic protection for System OnPremWorkingEnvironment-... Failed to backup System <ontap_system>`. The cause was that the ONTAP system holding the volumes was not reachable from the Console agent; the AWS bucket, the app vault and the schedules were fine. The error names the ONTAP system, so check the system's status on the canvas and the agent's network access to it first.

The failure is also written to the Application CR by Trident Protect, in the annotations `protect.trident.netapp.io/protection-state` (`Failed`), `protect.trident.netapp.io/protection-state-at` (time) and `protect.trident.netapp.io/protection-state-msg` (the full error, naming the failed backup). In the same example `status.protectionState` still read `Partial` with the detail "Scheduled backup unavailable", so the annotations are the better place to look:

```bash
kubectl get application <app_name> -n <namespace> -o yaml | yq '.metadata.annotations'
```

After fixing the cause, you don't have to wait for the next scheduled run. Create an on-demand backup with the CBS data mover (Backup and Recovery supports only that one), taking the app vault name from `tridentctl-protect get appvault`:

```bash
tridentctl-protect create backup --app <app_name> --appvault <appvault_name> --data-mover CBS -n <namespace>
```

Tested 2026-11-17 with the AWS disk-to-object policy after the failure above: once the ONTAP system was reachable again, the on-demand backup completed, objects appeared in the S3 bucket, and the `protection-state` annotation changed from `Failed` to `Protected` without waiting for the next scheduled run.

### Follow the progress on the cluster

For policies with replication or object copies, the Trident Protect custom resources show which part is still running:

```bash
kubectl -n <namespace> get schedules,snapshots,backups,cbsvolumebackups,cbsrelationship,replicatesnapshots
```

- `snapshots`, `backups`: the local snapshot and the backup of the application.
- `cbsvolumebackups`, `cbsrelationship`: the copy to the object store (policy types with object storage). `cbsrelationship` shows `CLOUDBASELINE` as bytes transferred, for example `272063/573440 Bytes (47.4%)`.
- `replicatesnapshots`: the replication to the secondary ONTAP system (`disk-to-disk`, `3-2-1-fanout`); `cbsrelationship` also shows `REPLBASELINE`.

Example, S3-compatible target (OVH) with a 3-2-1 fan-out policy, tested 2026-11-18: the snapshot was `Completed` after about 2 minutes, the replication baseline reached 100% while the cloud baseline was at 47%, and the backup and the `cbsrelationship` were `Completed` after about 8.5 minutes. The Application CR kept `protectionState: Partial` ("Scheduled backup unavailable") without `protection-state` annotations until then; at completion the annotations changed to `Protected`.

## Stop protection and delete an application

There is no API example for this in this folder; the steps below use the Console and `kubectl` (observed 2026-11-16 with Trident Protect 100.2610.1):

1. **Unprotect the application.** In the Console, or with the annotation `protect.trident.netapp.io/protection-command="unprotect"` on the Application CR (`--overwrite` if a `protect` annotation exists). The schedules are removed. Existing snapshots and backups stay (the scheduled backups have reclaim policy `Retain`).
2. **Delete the application in the Console.** The delete action is disabled (grayed out) while the application is protected, so step 1 comes first. The dialog states that deleting the application deletes all its snapshots and backups, can't be undone, and asks you to tick "Delete snapshots and backups" and to type the application name. With the box ticked, the application, its snapshot and backup CRs and the backup objects in the Azure container were removed. Whether the dialog allows keeping the backups was not tested.

Delete a protection policy only after no application uses it. Deleting policies in the Console worked; whether the server refuses to delete a policy that is still assigned was not tested.
