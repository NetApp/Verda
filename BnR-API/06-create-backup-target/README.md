# Create a backup target (bucket)

Create the object-storage bucket that Backup and Recovery uses as an offsite backup target. The bucket is the destination for the disk-to-object and 3-2-1 fan-out [protection policies](../04-protection-policies/README.md).

| Target | Script | Status |
| ------ | ------ | ------ |
| ONTAP S3 | [`create-ontap-s3-bucket.sh`](create-ontap-s3-bucket.sh) | Tested 2026-10-27 (create) and 2026-10-28 (`--wait`) without object lock: bucket created and listed by `object-storage`. Object lock untested |
| AWS S3 | [`create-aws-s3-bucket.sh`](create-aws-s3-bucket.sh) | Tested 2026-10-28 with default encryption, no object lock and no tags: account-name lookup, create and `--wait`. `--tag` was tested 2026-10-30: the request was accepted and the bucket listed, but the list does not show tags, so check them in the Console or AWS. Object lock and customer-managed KMS keys are not yet tested |
| Azure Blob | [`create-azure-storage-account.sh`](create-azure-storage-account.sh) | Tested 2026-10-28: resource-group lookup, create and `--wait`, with and without `--object-lock` (the request is accepted and the account is listed). The list does not show the lock state, so check it in the Console or the Azure portal |
| StorageGRID | [`create-storagegrid-bucket.sh`](create-storagegrid-bucket.sh) | Not yet tested against StorageGRID |
| S3-compatible | [`create-s3-compatible-bucket.sh`](create-s3-compatible-bucket.sh) | Tested 2026-10-28 without object lock: bucket created and listed. Object lock untested. Needs a Backup and Recovery version with S3-compatible support |

## Prerequisites

1. [Authentication](../00-authentication/README.md) and [account discovery](../01-account-discovery/README.md) completed.
2. For ONTAP S3, StorageGRID and S3-compatible: a credential in Backup and Recovery, see [ONTAP S3](../02-credentials-and-targets/ontap-s3.md), [StorageGRID](../02-credentials-and-targets/storagegrid.md) and [S3-compatible](../02-credentials-and-targets/s3-compatible.md). The scripts look it up by name.
3. For AWS S3: an AWS credential added to the Console, see [AWS S3 credentials](../02-credentials-and-targets/aws-s3.md). The bucket is created in that AWS account.

## Required variables

```bash
export ACCESS_TOKEN="<access_token>"       # BEARER_TOKEN is accepted as an alias
export ACCOUNT_ID="<account_public_id>"    # ORG_ID is accepted as an alias
export AGENT_ID="<console_agent_id>"
export CONSOLE_API="https://cloudmanager.cloud.netapp.com"   # API_HOST is accepted as an alias
```

Optional: `WORKSPACE_ID`, sent by the AWS script as `x-netapp-workspace-id`, as the Console UI does.

Every script supports `--dry-run` (prints the request body, no API call) and `--help`.

Every create call returns a job ID, so the bucket may not exist yet when the script exits. Add `--wait` to poll the `object-storage` list every 5 seconds until the new bucket appears (up to `--timeout` seconds, default 120). The script exits 0 when the bucket is listed and 1 on timeout, so it can be chained into the next step, for example creating a protection policy in [04-protection-policies](../04-protection-policies/README.md). No job-status call is documented here, so "listed" is the signal. The AWS and Azure list calls need extra query parameters (`aws-account-id`, or `subscription` and `resource-group`), so those two scripts poll with the values you passed. The polling is the `wait_for_object_store` function in [`lib/bnr-common.sh`](../lib/bnr-common.sh).

## ONTAP S3

```bash
./create-ontap-s3-bucket.sh --list-credentials    # name, id and server of the ONTAP S3 credentials
./create-ontap-s3-bucket.sh --bucket "<bucket_name>" --credential-name "<credential_name>" --dry-run
./create-ontap-s3-bucket.sh --bucket "<bucket_name>" --credential-name "<credential_name>"
```

With `--credential-id` instead of `--credential-name`, the credential lookup is skipped. Add `--object-lock` to enable object lock.

## AWS S3

List the regions and KMS keys the Console offers, then create the bucket:

```bash
./create-aws-s3-bucket.sh --list-aws-accounts
./create-aws-s3-bucket.sh --list-regions
./create-aws-s3-bucket.sh --list-kms-keys --aws-account-name "<aws_credential_name>" --region "<region_code>"

./create-aws-s3-bucket.sh --bucket "<bucket_name>" --region "<region_code>" \
  --aws-account-name "<aws_credential_name>" --dry-run
./create-aws-s3-bucket.sh --bucket "<bucket_name>" --region "<region_code>" \
  --aws-account-name "<aws_credential_name>"
```

Use `--aws-account-id` instead of `--aws-account-name` if you already know the 12-digit AWS account ID. The name is the credential name shown in the Console, and the script resolves it with `GET /occm/api/accounts/cloud-providers`.

`--kms-key-id` is empty by default, which is what the UI sends for default encryption.

For a bucket with object lock, add `--object-lock-mode COMPLIANCE` or `GOVERNANCE`. Object lock modes and tags are not yet tested. The UI sends no versioning field, so the Console appears to enable versioning together with object lock. Add `--tag KEY=VALUE` once per AWS tag:

```bash
./create-aws-s3-bucket.sh --bucket "<bucket_name>" --region "<region_code>" \
  --aws-account-name "<aws_credential_name>" \
  --object-lock-mode COMPLIANCE --tag type=test
```

COMPLIANCE object lock protects data in a way that even the AWS root user cannot undo. Check retention settings before using it on a bucket with real backups.

The Console creates the bucket in AWS and returns a job ID. HTTP 2xx means the request was accepted, not that the bucket is ready.

## Azure Blob

List the subscriptions and resource groups the Console sees, then create the storage account:

```bash
./create-azure-storage-account.sh --list-subscriptions
./create-azure-storage-account.sh --list-resource-groups --subscription-name "<subscription_name>"

./create-azure-storage-account.sh --name "<storage_account_name>" \
  --subscription-name "<subscription_name>" --resource-group "<resource_group>" \
  --region "<azure_region>" --object-lock --dry-run
./create-azure-storage-account.sh --name "<storage_account_name>" \
  --subscription-name "<subscription_name>" --resource-group "<resource_group>" \
  --region "<azure_region>" --object-lock
```

Use `--subscription-id` instead of `--subscription-name` if you already know the subscription GUID. The resource group must already exist, and the Azure credential you added to the Console (see [Azure credentials](../02-credentials-and-targets/azure.md)) must have access to the subscription. `--region` is the region of the storage account and can differ from the resource group's region.

The name becomes the storage account name, so use 3-24 lowercase letters and digits. The UI sends no encryption or lock-mode field for Azure, so the script has none. Azure encrypts data at rest by default. Like AWS, the call returns a job ID.

## StorageGRID (untested)

```bash
./create-storagegrid-bucket.sh --list-credentials
./create-storagegrid-bucket.sh --bucket "<bucket_name>" --credential-name "<credential_name>" --object-lock --dry-run
./create-storagegrid-bucket.sh --bucket "<bucket_name>" --credential-name "<credential_name>" --object-lock
```

The Console API calls StorageGRID `SGWS`. The credential must exist first, see [StorageGRID credentials](../02-credentials-and-targets/storagegrid.md). With `--credential-id` instead of `--credential-name`, the lookup is skipped. The call returns a job ID, like AWS and Azure.

## S3-compatible

For third-party S3-compatible object storage. This needs a Backup and Recovery version that supports S3-compatible storage.

```bash
./create-s3-compatible-bucket.sh --list-credentials
./create-s3-compatible-bucket.sh --bucket "<bucket_name>" --credential-name "<credential_name>" --object-lock --dry-run
./create-s3-compatible-bucket.sh --bucket "<bucket_name>" --credential-name "<credential_name>" --object-lock
```

The Console API calls this provider `S3_COMPATIBLE`. The credential, with the S3 endpoint and the access and secret keys, must exist first, see [S3-compatible credentials](../02-credentials-and-targets/s3-compatible.md). With `--credential-id` instead of `--credential-name`, the lookup is skipped. The call returns a job ID.

## List existing buckets

[`list-buckets.sh`](list-buckets.sh) is read-only and lists the buckets that already exist in Backup and Recovery, per provider:

```bash
./list-buckets.sh                       # all providers
./list-buckets.sh --provider ONTAP_S3   # one provider: AWS, AZURE, ONTAP_S3, SGWS or S3_COMPATIBLE
./list-buckets.sh --json | jq '.[] | {provider, credential, buckets: (.buckets | length)}'
```

ONTAP S3, StorageGRID and S3-compatible are queried once per credential (the `provider` plus `credential-id` query that the bucket scripts use for `--wait`), so the output shows which credential each bucket belongs to. AWS is queried once per AWS account known to the Console with `provider=AWS&aws-account-id=<aws account id>` (the call the Console UI makes), or for one account with `--aws-account-id`. The AWS list shows the S3 buckets of the AWS account that the Console can see, including buckets that were never used as backup targets, and the response carries no region. Azure needs the subscription and the resource group (the API answers "AZURE resource-group and subscription query parameters are required to list Azure storage accounts"), so pass `--subscription-id` (or `--subscription-name`) and `--resource-group`, for example `./list-buckets.sh --provider AZURE --subscription-name "<name>" --resource-group "<rg>"` (tested 2026-10-28). Use `create-azure-storage-account.sh --list-subscriptions` and `--list-resource-groups` to find the values, and `--debug` to print each request URL. The text output shows the bucket name, region and creation time (`-` when the API does not return a field). An object-lock column appears only for providers whose list response carries an `object_lock` field. The Azure response does not (it returns `object_store_name`, `creation_time`, `region`, `provider`, `resource_group` and `subscription`), so the list cannot tell you whether an Azure bucket has object lock. `--json` prints the raw bucket objects. A provider that fails, for example because the Backup and Recovery version does not support it yet, is reported on its own line and does not stop the others.

## Verify

```bash
curl -sS --get "${CONSOLE_API}/backup-recovery/organizations/${ACCOUNT_ID}/v1/object-storage" \
  --header "Authorization: Bearer ${ACCESS_TOKEN}" \
  --header "X-Agent-Id: ${AGENT_ID}" \
  --data-urlencode "provider=<ONTAP_S3|AWS|AZURE|SGWS|S3_COMPATIBLE>" \
  --data-urlencode "credential-id=<credential_id>" | jq '.[].object_store_name'
```

The `credential-id` filter applies to ONTAP S3. I have not confirmed which filter parameters AWS accepts. The summary call `GET .../v1/object-storage-summary` shows bucket counts per provider.
