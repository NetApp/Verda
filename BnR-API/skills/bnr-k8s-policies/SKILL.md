---
name: bnr-k8s-policies
description: Create, list and delete NetApp Backup and Recovery for Kubernetes protection policies through the NetApp Console API. Covers policy types local-snapshot, disk-to-object, disk-to-disk and 3-2-1-fanout, backup targets Azure, AWS, ONTAP S3 and StorageGRID, hourly/daily/weekly/monthly schedules, retention, and choosing the secondary ONTAP system. Use this skill whenever the user wants a Kubernetes backup or protection policy, mentions create-k8s-policy.sh, policyId, SECONDARY_TARGET, snapshot/backup schedules or retention for Trident Protect, or wants to list or delete policies, even if they just say "make a policy for hourly snapshots and backups to S3".
---

# Backup and Recovery for Kubernetes: protection policies

**Experimental.** This skill is still experimental. Tell the user so at the start of a session, and recommend a test account or non-production resources first.

Bundled bash scripts in `06-protection-policies/scripts/`. The backup target (credential plus bucket or storage account) must already exist; if not, use `bnr-k8s-setup`. Applications are attached to policies with `bnr-k8s-protect`.

Read `references/conventions.md` first (secrets, protocol, naming) and check `references/tested-status.md` for what is proven. Full option list: `06-protection-policies/README.md`.

Run from `06-protection-policies/scripts/`. Needs `ACCOUNT_ID`, `AGENT_ID`, `ACCESS_TOKEN` (renew with `bnr_renew_token` on 401).

## Workflow

1. **List existing policies**: `./list-k8s-policies.sh` (`--json` for full objects). Check the name is free. This script was tested with a mocked API only; the underlying call is live-tested.
2. **Choose** target (`azure | aws | ontap-s3 | sgws`) and type:
   - `local-snapshot`: snapshots on the cluster only
   - `disk-to-object`: snapshots plus backups to object storage
   - `disk-to-disk`: snapshots plus replication to a secondary ONTAP system
   - `3-2-1-fanout`: all of the above
   If the user is unsure, ask what they need to survive (cluster loss means object or secondary copy).
3. **See the needed variables**: `./create-k8s-policy.sh <target> <type> --vars`. Target variables: azure `AZURE_SUBSCRIPTION_ID`, `AZURE_RG`, `AZURE_STORAGE_ACCOUNT`; aws `AWS_ACCOUNT_ID`, `AWS_BACKUP_TARGET` (bucket); ontap-s3 `ONTAP_CRED_NAME`, `ONTAP_BUCKET_NAME`; sgws `SGWS_CRED_NAME`, `SGWS_BUCKET_NAME`. Get real bucket and storage account names with `../../04-create-backup-target/scripts/list-buckets.sh`. Leave `ONTAP_S3_SERVER_URL` unset normally (looked up from the credential).
4. **Secondary system** (disk-to-disk, 3-2-1-fanout): set `TARGET_SYSTEM_NAME` if it has one SVM and aggregate; otherwise run `./create-k8s-policy.sh --list-secondary-targets` and set `SECONDARY_TARGET="system | svm | aggregate"` (or `--secondary-target`). Creation does not check reachability: warn that an unreachable secondary only fails at the first backup.
5. **Dry run**: `./create-k8s-policy.sh <target> <type> --policy-name <name> --dry-run`. Show the body (schedules, retention) and the defaults being used (hourly keep 3, daily 00:00 keep 3).
6. **Confirm, then create** without `--dry-run`. Report the returned `policyId`.
7. **Verify**: `./list-k8s-policies.sh` shows the new policy.

Schedule and retention flags: `--hourly-every/--hourly-retention`, `--daily-at/--daily-retention`, `--weekly` (+ `--weekly-day/-at/-retention`), `--monthly` (+ `--monthly-day/-at/-retention`), `--secondary-<period>-retention`, `--object-<period>-retention`, `--replica-<period>-retention`, `--retry-count`, `--retry-after`, `--partial-backup`. Weekly, monthly, `--secondary-target` and `--partial-backup` are untested live: say so and dry-run first. StorageGRID policies are untested.

## Deleting

`./delete-k8s-policy.sh <policyId>` (asks for confirmation; `--dry-run` previews; `--yes` skips the prompt, use only after the user confirmed in chat). Look up the `policyId` with the list script and show the name before deleting. Only delete a policy no application uses; deleting an assigned policy is untested, so unprotect or remove those applications first. Deleting cannot be undone.

## Guardrails

- Never delete a policy the user didn't name.
- Policy names: lowercase letters, digits, hyphens, no angle brackets.
- Never describe untested options as working.
