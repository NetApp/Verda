# What has been tested

Status as of 2026-11-18, from live tests against a NetApp Console account with an OpenShift cluster (`pu-ocp1`), Trident Protect `100.2610.1-console`, an ONTAP S3 server, an Azure storage account and an AWS account. "Live" means run against the real Console API. The section READMEs hold the details and dates.

Update this file (in `skills/_shared/`, then run `skills/sync.sh`) when a test result changes.

## Setup (skill `bnr-k8s-setup`)

| Area | Status |
| --- | --- |
| Refresh token to access token, `bnr_renew_token` | Live |
| Account discovery (`discover.sh`) | Live. Accounts with non-UUID IDs (`account-xxxx`) untested for Backup and Recovery |
| Credential: ONTAP S3 | Live (`create-s3-credential.sh`, returns a job ID) |
| Credential: Azure | Live (2026-11-11) |
| Credential: AWS | Live (2026-11-17, HTTP 200, no job ID). `--wait` not run |
| Credential: S3-compatible | Live (2026-10-28) |
| Credential: StorageGRID | Untested |
| Deleting credentials | No API example; use the Console UI |
| Add ONTAP cluster to canvas | `--dry-run` only (2026-11-13); live add not repeated |
| Bucket: ONTAP S3 | Live (2026-11-13). The call creates the bucket on the ONTAP S3 server |
| Bucket: AWS S3 | Live (2026-11-17 and 2026-11-18 with the `netapp-backup-` prefix); tags tested 2026-10-30 |
| Storage account: Azure | Live (2026-10-28, not retested) |
| Bucket: S3-compatible | Live (2026-10-28, not retested) |
| Bucket: StorageGRID | Untested |
| Object lock (any provider), customer-managed KMS keys | Untested |
| OCCM credential, Trident Protect install, cluster `connected` | Live (2026-11-16). Install can fail on a leftover webhook configuration (see section 05 README) |

## Policies (skill `bnr-k8s-policies`)

| Area | Status |
| --- | --- |
| ONTAP S3: local-snapshot, disk-to-object, disk-to-disk, 3-2-1-fanout | Live (2026-11-16) |
| AWS: all four types | Live (2026-11-17). Secondary-system types were created while the secondary ONTAP was unreachable: creation does not check reachability |
| Azure: all four types | Live (2026-10-29), not retested with Trident Protect 100.2610.1 |
| StorageGRID: all four types | Untested |
| Weekly and monthly schedules, `--secondary-target`, `--partial-backup` | Untested |
| Listing policies (`list-k8s-policies.sh`) | Mocked API only; the underlying call is live-tested |
| Deleting a policy that no application uses (`delete-k8s-policy.sh`) | Live (2026-11-17, HTTP 204) |
| Deleting a policy that is still assigned to an application | Untested; delete or unprotect the applications first |

## Applications (skill `bnr-k8s-protect`)

| Area | Status |
| --- | --- |
| Create and protect in one run (`create-app-API.sh`) | Live (Azure and AWS policies, 2026-11-16 and 2026-11-17) |
| Create without a policy, protect later by POST `/protect` | Live (2026-11-16) |
| Annotations `protection-command` (`protect`, `unprotect`) and `protection-policy-name` on an API-created app | Live (2026-11-16) |
| Create app with the Trident protect CLI and annotations | Tested in a NetApp Community post (March 2026) |
| Verify first backup via CR annotations (`Protected`, `Failed`) | Live (2026-11-17) |
| On-demand backup with `tridentctl-protect create backup ... --data-mover CBS` | Live (2026-11-17) |
| Unprotect and delete an application in the Console | Observed (2026-11-17): delete is disabled while protected; deleting removes snapshots, backups and bucket objects |
| Several applications on one namespace | Accepted |
| Label selectors, VM apps (`virtual-machine-label-selector`), `--site-prefix` / `--policy-file` | Untested |
| Restore operations | Untested; not covered by these skills |
| Deleting an application through the API | No example; use the Console |
