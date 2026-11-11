# Credentials and targets

Add the credentials Backup and Recovery needs to reach a backup target. Run these after [authentication](../00-authentication/README.md) and [account discovery](../01-account-discovery/README.md).

| Target | Guide | Status |
| ------ | ----- | ------ |
| Azure Blob | [azure.md](azure.md) | Tested 2026-11-11 |
| AWS S3 | [aws-s3.md](aws-s3.md) | Script untested |
| ONTAP S3 | [ontap-s3.md](ontap-s3.md) | — |
| S3-compatible | [s3-compatible.md](s3-compatible.md) | Tested 2026-10-28 |
| StorageGRID | [storagegrid.md](storagegrid.md) | Untested |

Azure and AWS credentials are added through the `occm/api/accounts` endpoints. [`scripts/create-azure-credential.sh`](scripts/create-azure-credential.sh) and [`scripts/create-aws-credential.sh`](scripts/create-aws-credential.sh) cover them (Azure tested 2026-11-11, AWS untested). ONTAP S3, StorageGRID and S3-compatible credentials are added through the Backup and Recovery API and the call returns a job ID. [`scripts/create-s3-credential.sh`](scripts/create-s3-credential.sh) covers these three; run it with `--help` for all options and `--dry-run` to preview the request.

Next step: [create the backup target](../04-create-backup-target/README.md) (bucket or storage account), then [protection policies](../06-protection-policies/README.md).
