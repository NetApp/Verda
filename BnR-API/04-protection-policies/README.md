# Protection policies

Create Backup and Recovery for Kubernetes **protection policies** through the NetApp Console API instead of the Console UI.

Prerequisites: [authentication](../00-authentication/README.md) and [account discovery](../01-account-discovery/README.md) completed. The backup target (credential, bucket or storage account) must already exist, see [credentials and targets](../02-credentials-and-targets/). `ACCOUNT_ID` must be the organization ID (a UUID).

## Policy types and targets

| Policy type | What it creates |
| ----------- | --------------- |
| `local-snapshot` | Snapshots on the cluster's primary storage only |
| `disk-to-object` | Snapshots plus backups to object storage |
| `disk-to-disk` | Snapshots plus replication to a secondary ONTAP system |
| `3-2-1-fanout` | Snapshots, replication to a secondary ONTAP system and backups to object storage |

Backup targets: `azure`, `aws`, `ontap-s3`, `sgws` (StorageGRID).

## Quick start

```bash
cd scripts

# Show the variables a combination needs
./create-k8s-policy.sh azure 3-2-1-fanout --vars

export AZURE_SUBSCRIPTION_ID="<subscription_id>"
export AZURE_RG="<resource_group>"
export AZURE_STORAGE_ACCOUNT="<storage_account>"
export TARGET_SYSTEM_NAME="<secondary_ontap_system_name>"

./create-k8s-policy.sh azure 3-2-1-fanout --policy-name "<policy_name>"
```

Only `--policy-name` is mandatory on the command line. Everything else comes from environment variables or optional flags. Run `./create-k8s-policy.sh -h` for all options.

## Required variables

All combinations need `CONSOLE_API` (optional, defaults to `https://api.bluexp.netapp.com`), `ACCOUNT_ID`, `AGENT_ID` and `ACCESS_TOKEN`. In addition:

| Target | Variables |
| ------ | --------- |
| `azure` | `AZURE_SUBSCRIPTION_ID`, `AZURE_RG`, `AZURE_STORAGE_ACCOUNT` |
| `aws` | `AWS_ACCOUNT_ID`, `AWS_BACKUP_TARGET` (bucket name) |
| `ontap-s3` | `ONTAP_CRED_NAME`, `ONTAP_BUCKET_NAME` (credential and server address are looked up) |
| `sgws` | `SGWS_CRED_NAME`, `SGWS_BUCKET_NAME` (credential ID and server address are looked up) |
| `disk-to-disk`, `3-2-1-fanout` | `TARGET_SYSTEM_NAME`, or `SECONDARY_TARGET` (see below) |

## Schedules and retention

Defaults match the Console UI: hourly (every hour, keep 3) and daily (00:00, keep 3). Weekly and monthly schedules are optional.

```bash
./create-k8s-policy.sh aws disk-to-object --policy-name "<policy_name>" \
  --hourly-retention 6 --daily-at 02:00 --weekly --weekly-retention 8
```

Retention of replicas and object store copies can be set separately (`--secondary-*-retention`, `--object-*-retention`) or together (`--replica-*-retention`).

## Choosing the secondary ONTAP system

For `disk-to-disk` and `3-2-1-fanout`, the scripts look up the system, SVM and aggregate. Set `TARGET_SYSTEM_NAME` for the common case. If the system has more than one SVM or aggregate, list the choices and copy one entry exactly as the Console drop-down shows it:

```bash
./create-k8s-policy.sh azure 3-2-1-fanout --list-secondary-targets
export SECONDARY_TARGET="<system> | <svm> | <aggregate>"
```

## Scripts

| Script | Purpose |
| ------ | ------- |
| [`create-k8s-policy.sh`](scripts/create-k8s-policy.sh) | Wrapper: picks the right script for target and type, validates options |
| `<target>-<n>-<type>.sh` | One script per target and policy type, usable on its own with `--policy-name` |
| [`delete-k8s-policy.sh`](scripts/delete-k8s-policy.sh) | Delete a policy by its `policyId`; asks for confirmation unless `--yes` is given |

Each script documents its variables in its header and stops with a list of any that are missing.

## Delete a policy

```bash
./delete-k8s-policy.sh <policyId>
```

The server may refuse to delete a policy that is still assigned to protected applications.

## Verify

```bash
curl -sS "${CONSOLE_API}/backup-recovery/organizations/${ACCOUNT_ID}/v1/workloads/k8s/kubernetes/policies" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "X-Account-Id: ${ACCOUNT_ID}" \
  | jq '.[] | {policyId, policyName, backupArchitectureType}'
```

The call returns an array of all policies. The create call returns the new `policyId`, which you can also use with `delete-k8s-policy.sh`. The policy also appears in the Console under Backup and Recovery, Kubernetes, Policies.

## Tested with

Console date: 2026-10-22, Trident Protect v26.09.0-console.

| Target | local-snapshot | disk-to-object | disk-to-disk | 3-2-1-fanout |
| ------ | -------------- | -------------- | ------------ | ------------ |
| azure | Tested | Tested | Tested | Tested |
| aws | Tested | Tested | Tested | Tested |
| ontap-s3 | Tested | Tested | Tested | Tested |
| sgws | Untested | Untested | Untested | Untested |

Request bodies for all combinations were compared with the payloads the Console UI sends. Weekly and monthly schedules, `--secondary-target` and `--partial-backup` are untested against a live system.
