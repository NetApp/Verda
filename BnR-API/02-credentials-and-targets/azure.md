# Add Azure credentials

With Backup and Recovery you can back up ONTAP volume data to Azure Blob. For that, the Console agent needs Azure credentials.

You need a service principal with the [required permissions](https://docs.netapp.com/us-en/console-setup-admin/reference-permissions-azure.html#how-azure-permissions-are-used) in your Azure account.

## Required variables

| Variable | Meaning |
| -------- | ------- |
| `AZURE_CREDENTIAL_NAME` | Name that distinguishes these credentials from others |
| `AZURE_CLIENT_ID` | Application (client) ID of the service principal |
| `AZURE_CLIENT_SECRET` | Client secret value of the service principal |
| `AZURE_TENANT_ID` | Directory (tenant) ID |

```bash
export AZURE_CREDENTIAL_NAME="<credential_name>"
export AZURE_CLIENT_ID="<application_client_id>"
export AZURE_CLIENT_SECRET="<client_secret>"
export AZURE_TENANT_ID="<directory_tenant_id>"
```

## Add the credentials

```bash
curl --request POST --location "${CONSOLE_API}/occm/api/accounts/azure" \
  --header "x-agent-id: ${AGENT_ID}" \
  --header "Authorization: Bearer ${ACCESS_TOKEN}" \
  --header "Content-Type: application/json" \
  --data "$(jq -n \
    --arg accountName "$AZURE_CREDENTIAL_NAME" \
    --arg applicationId "$AZURE_CLIENT_ID" \
    --arg applicationKey "$AZURE_CLIENT_SECRET" \
    --arg tenantId "$AZURE_TENANT_ID" \
    '{
      accountName: $accountName,
      providerKeys: {
        applicationId: $applicationId,
        applicationKey: $applicationKey,
        tenantId: $tenantId
      }
    }')"
```

## Verify

List the cloud provider credentials tied to the agent:

```bash
curl -sS -X GET --location "${CONSOLE_API}/occm/api/accounts/cloud-providers" \
  -H "x-agent-id: ${AGENT_ID}" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" | jq
```

You can now discover existing and create new Azure backup destinations. See the [documentation](https://docs.netapp.com/us-en/data-services-backup-recovery/br-start-setup.html#prepare-the-backup-destination).
