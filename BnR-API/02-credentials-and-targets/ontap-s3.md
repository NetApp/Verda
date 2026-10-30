# Add ONTAP S3 credentials

To use ONTAP S3 buckets as backup destinations you need the FQDN of the storage server (the ONTAP S3 server) and the access and secret keys.

Unlike cloud credentials, ONTAP S3 credentials are added through the Backup and Recovery API and the call returns a **job ID**.

Script alternative: [`scripts/create-s3-credential.sh`](scripts/create-s3-credential.sh) with `--provider ONTAP_S3` makes the same call, see [Use the script](#use-the-script) below.

## Required variables

```bash
export ACCESSKEY="<access_key>"
export SECRETKEY="<secret_key>"
export STORAGE_SERVER="<ontap_s3_server_FQDN>"
export STORAGE_PORT=80   # the port the ONTAP S3 server listens on, for example 443 with TLS
```

## Add the credentials

```bash
curl --request POST "${CONSOLE_API}/backup-recovery/organizations/${ACCOUNT_ID}/v1/credentials" \
  --header "Authorization: Bearer ${ACCESS_TOKEN}" \
  --header "X-Agent-Id: ${AGENT_ID}" \
  --header "Content-Type: application/json" \
  --data "$(jq -n \
    --arg provider "ONTAP_S3" \
    --arg name "<credential_name>" \
    --arg server "${STORAGE_SERVER}" \
    --argjson port "${STORAGE_PORT}" \
    --arg access_key "${ACCESSKEY}" \
    --arg secret_password "${SECRETKEY}" \
    '{
      provider: $provider,
      credential_name: $name,
      storage_server_name: $server,
      port: $port,
      access_key: $access_key,
      secret_password: $secret_password
    }')"
```

Set `STORAGE_PORT` to the port your ONTAP S3 server listens on, for example 443 with TLS. The Console UI asks for the same value.

## Use the script

[`scripts/create-s3-credential.sh`](scripts/create-s3-credential.sh) does the same call for ONTAP S3, StorageGRID and S3-compatible. It reads `ACCESSKEY`, `SECRETKEY`, `STORAGE_SERVER` and `STORAGE_PORT`, redacts the secret in `--dry-run`, and keeps the keys off the command line.

```bash
./scripts/create-s3-credential.sh --provider ONTAP_S3 --name "<credential_name>" \
  --server "${STORAGE_SERVER}" --port "${STORAGE_PORT}" --dry-run
./scripts/create-s3-credential.sh --provider ONTAP_S3 --name "<credential_name>" \
  --server "${STORAGE_SERVER}" --port "${STORAGE_PORT}" --wait
```

The call returns a job ID. With `--wait` the script polls the credential list every 5 seconds until the new name appears (up to `--timeout` seconds, default 120) and exits 0, or exits 1 on timeout. It treats "listed" as registered, because no job-status call is documented here. Use it to chain the next step:

```bash
./scripts/create-s3-credential.sh --provider ONTAP_S3 --name "<credential_name>" \
  --server "${STORAGE_SERVER}" --port "${STORAGE_PORT}" --wait \
  && ../06-create-backup-target/create-ontap-s3-bucket.sh --bucket "<bucket_name>" --credential-name "<credential_name>"
```

## Verify

List the ONTAP S3 credentials tied to the agent:

```bash
curl -sS --get "${CONSOLE_API}/backup-recovery/organizations/${ACCOUNT_ID}/v1/credentials" \
  --header "Authorization: Bearer ${ACCESS_TOKEN}" \
  --header "Accept: application/json" \
  --header "X-Agent-Id: ${AGENT_ID}" \
  --data-urlencode "provider=ONTAP_S3" | jq
```
