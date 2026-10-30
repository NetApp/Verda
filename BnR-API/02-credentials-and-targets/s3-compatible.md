# Add S3-compatible credentials

> **Tested 2026-10-28** with [`scripts/create-s3-credential.sh`](scripts/create-s3-credential.sh): the credential was accepted and appeared in the credential list. S3-compatible storage needs a Backup and Recovery version that supports it.

To use a third-party S3-compatible object store as a backup destination you need the endpoint FQDN of the storage server, its port and the access and secret keys.

Like ONTAP S3, the credentials are added through the Backup and Recovery API and the call returns a **job ID**.

## Required variables

```bash
export ACCESSKEY="<access_key>"
export SECRETKEY="<secret_key>"
export STORAGE_SERVER="<s3_endpoint_FQDN>"
export STORAGE_PORT=443   # the port the endpoint listens on
```

## Add the credentials

```bash
curl --request POST "${CONSOLE_API}/backup-recovery/organizations/${ACCOUNT_ID}/v1/credentials" \
  --header "Authorization: Bearer ${ACCESS_TOKEN}" \
  --header "X-Agent-Id: ${AGENT_ID}" \
  --header "Content-Type: application/json" \
  --data "$(jq -n \
    --arg provider "S3_COMPATIBLE" \
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

Set `STORAGE_PORT` to the port your endpoint listens on (443 for TLS). The response contains a `job_id` and the message "Credential registration in progress". The credential is usable once that job has finished.

Script alternative: `./scripts/create-s3-credential.sh --provider S3_COMPATIBLE --name "<credential_name>" --server "${STORAGE_SERVER}" --port "${STORAGE_PORT}"`, see [`scripts/create-s3-credential.sh`](scripts/create-s3-credential.sh).

## Verify

List the S3-compatible credentials tied to the agent:

```bash
curl -sS --get "${CONSOLE_API}/backup-recovery/organizations/${ACCOUNT_ID}/v1/credentials" \
  --header "Authorization: Bearer ${ACCESS_TOKEN}" \
  --header "Accept: application/json" \
  --header "X-Agent-Id: ${AGENT_ID}" \
  --data-urlencode "provider=S3_COMPATIBLE" | jq
```

Next: [create the bucket](../06-create-backup-target/README.md#s3-compatible).
