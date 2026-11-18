---
name: bnr-k8s-setup
description: Set up NetApp Backup and Recovery for Kubernetes through the NetApp Console API, step by step - authentication and access token, account/workspace/agent discovery, cloud or ONTAP S3 credentials, backup targets (AWS S3 bucket, Azure storage account, ONTAP S3 bucket, StorageGRID, S3-compatible), adding an ONTAP cluster to the canvas, and onboarding a Kubernetes cluster (OCCM credential, Trident Protect install, cluster "connected"). Use this skill whenever the user wants to prepare Backup and Recovery for K8s, Trident Protect, or Console backup targets by script or API instead of the UI, mentions ACCOUNT_ID, AGENT_ID, ACCESS_TOKEN, bnr_renew_token, cloudmanager.cloud.netapp.com, netapp-backup- buckets, or onboarding an OpenShift/Kubernetes cluster to the NetApp Console, even if they don't say "skill" or "API".
---

# Backup and Recovery for Kubernetes: setup

**Experimental.** This skill is still experimental. Tell the user so at the start of a session, and recommend a test account or non-production resources first.

Bundled bash scripts that prepare everything needed before policies and applications: access, credentials, backup targets and the cluster. Policies are the job of `bnr-k8s-policies`, protecting applications of `bnr-k8s-protect`.

Read `references/conventions.md` first. It holds the rules for secrets, the lookup, dry-run, confirm, run, verify protocol, and naming. Read `references/tested-status.md` before using an option the user depends on, and say so when a path is untested.

Folders mirror the BnR-API repository: each `NN-section/` has a `README.md` with full details and a `scripts/` folder. Run scripts from their own `scripts/` folder. Every script has `--help` and, where it changes something, `--dry-run`.

## Workflow

Work in this order. Skip steps the user has already done (verify with the list calls).

1. **Authentication** (`00-authentication/`). The user keeps a private env file based on `env.sh.example` (never in chat). It defines `bnr_renew_token`, which turns the refresh token into `ACCESS_TOKEN`. Check only that variables are set. A token that is `null` or a 401 means renew it.
2. **Discovery** (`01-account-discovery/scripts/discover.sh`). Lists accounts, workspaces and agents. Never guess IDs; if several exist, ask which. Use `--exports` to print `export` lines for the user to run.
3. **Credential** (`02-credentials-and-targets/`). One script per provider: `create-s3-credential.sh` (ONTAP S3, S3-compatible), `create-azure-credential.sh`, `create-aws-credential.sh`. Each has `--list` to see existing credentials and `--dry-run`. Provider details in `ontap-s3.md`, `azure.md`, `aws-s3.md`, `s3-compatible.md`, `storagegrid.md`. Secrets come from environment variables, not flags. Deleting a credential has no API example: use the Console UI.
4. **ONTAP on the canvas** (`03-add-ontap-to-canvas/`), only if an on-prem ONTAP system is needed (ONTAP S3 target or secondary system for disk-to-disk). Check the canvas first; a system already there cannot be added twice. Live add was not repeated, so lead with `--dry-run`.
5. **Backup target** (`04-create-backup-target/scripts/`). `list-buckets.sh` first, then the matching script: `create-aws-s3-bucket.sh`, `create-azure-storage-account.sh` (has `--list-subscriptions`, `--list-resource-groups`), `create-ontap-s3-bucket.sh` (the call creates the bucket on the ONTAP S3 server), `create-s3-compatible-bucket.sh`, `create-storagegrid-bucket.sh` (untested). AWS bucket names must start with `netapp-backup-` and have at most 63 characters; the script enforces it. Use `--wait` to poll until the target appears. Object lock and KMS options are untested.
6. **Cluster onboarding** (`05-cluster-onboarding/`). `list-clusters.sh` shows clusters and their state. `create-occm-credential.sh` creates the credential, then Trident Protect is installed with `helm` (steps in the README) and the cluster should reach `connected` (about 2 minutes). If the install fails with "Apply failed with N conflicts", a leftover webhook configuration from an earlier installation is the cause; the README has the `kubectl delete validatingwebhookconfiguration` fix. Confirm before deleting it.

## Guardrails

- Creating credentials and targets costs money or changes cloud resources. Dry run, show, get a yes, then run, then verify with the list call.
- Never ask for or print secrets (see conventions).
- Do not delete credentials, buckets or storage accounts with these scripts; they don't exist for that. Point to the Console or the cloud provider.
- When finished, tell the user the next step: policies (`bnr-k8s-policies`), then applications (`bnr-k8s-protect`).
