# Add ONTAP S3 credentials

To use ONTAP S3 buckets as backup destinations you need the FQDN of the storage server (the ONTAP S3 server) and the access and secret keys.

Unlike cloud credentials, ONTAP S3 credentials are added through the Backup and Recovery API and the call returns a **job ID**.

## Required variables

```bash
export ACCESSKEY="<access_key>"
export SECRETKEY="<secret_key>"
export STORAGE_SERVER="<ontap_s3_server_FQDN>"
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
    --arg access_key "${ACCESSKEY}" \
    --arg secret_password "${SECRETKEY}" \
    '{
      provider: $provider,
      credential_name: $name,
      storage_server_name: $server,
      port: 80,
      access_key: $access_key,
      secret_password: $secret_password
    }')"
```

Change `port` if your ONTAP S3 server listens on a different port (for example 443 with TLS).

## Verify

List the ONTAP S3 credentials tied to the agent:

```bash
curl -sS --get "${CONSOLE_API}/backup-recovery/organizations/${ACCOUNT_ID}/v1/credentials" \
  --header "Authorization: Bearer ${ACCESS_TOKEN}" \
  --header "Accept: application/json" \
  --header "X-Agent-Id: ${AGENT_ID}" \
  --data-urlencode "provider=ONTAP_S3" | jq
```
