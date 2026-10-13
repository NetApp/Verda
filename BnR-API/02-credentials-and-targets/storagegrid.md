# Add StorageGRID credentials - Untested

> **Untested.** This follows the ONTAP S3 call with a different provider value. Please verify in your environment and report back.

To use StorageGRID buckets as backup destinations you need the FQDN of the gateway node, the port (443 by default) and the access and secret keys.

## Required variables

```bash
export ACCESSKEY="<access_key>"
export SECRETKEY="<secret_key>"
export STORAGE_SERVER="<gateway_node_FQDN>"
export PORT=443
```

## Add the credentials

Same API call as for [ONTAP S3](ontap-s3.md), with provider `SGWS`:

```bash
curl --request POST "${CONSOLE_API}/backup-recovery/organizations/${ACCOUNT_ID}/v1/credentials" \
  --header "Authorization: Bearer ${ACCESS_TOKEN}" \
  --header "X-Agent-Id: ${AGENT_ID}" \
  --header "Content-Type: application/json" \
  --data "$(jq -n \
    --arg provider "SGWS" \
    --arg name "<sgws-cred-name>" \
    --arg server "${STORAGE_SERVER}" \
    --argjson port "${PORT}" \
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

## Verify

```bash
curl -sS --get "${CONSOLE_API}/backup-recovery/organizations/${ACCOUNT_ID}/v1/credentials" \
  --header "Authorization: Bearer ${ACCESS_TOKEN}" \
  --header "Accept: application/json" \
  --header "X-Agent-Id: ${AGENT_ID}" \
  --data-urlencode "provider=SGWS" | jq
```
