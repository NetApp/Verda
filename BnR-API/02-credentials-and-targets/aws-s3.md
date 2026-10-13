# Add AWS S3 credentials

With the credentials of an AWS IAM user that has the [required permissions](https://docs.netapp.com/us-en/data-services-backup-recovery/br-start-setup.html#set-up-s3-permissions), you can define AWS S3 buckets as backup destinations.

## Required variables

```bash
export AWS_ACCOUNT_NAME="<your_aws_account_name>"
export AWS_ACCESS_KEY_ID="<access_key_id>"
export AWS_SECRET_ACCESS_KEY="<secret_access_key>"
```

## Add the credentials

```bash
curl -sS --request POST --location "${CONSOLE_API}/occm/api/accounts/aws" \
  --header "x-agent-id: ${AGENT_ID}" \
  --header "Authorization: Bearer ${ACCESS_TOKEN}" \
  --header "Content-Type: application/json" \
  --data "$(jq -n \
    --arg accountName "$AWS_ACCOUNT_NAME" \
    --arg accessKey "$AWS_ACCESS_KEY_ID" \
    --arg secretKey "$AWS_SECRET_ACCESS_KEY" \
    '{
      accountName: $accountName,
      providerKeys: {
        awsAccessKeys: {
          accessKey: $accessKey,
          secretKey: $secretKey
        }
      }
    }')" | jq
```

## Verify

```bash
curl -sS -X GET --location "${CONSOLE_API}/occm/api/accounts/cloud-providers" \
  -H "x-agent-id: ${AGENT_ID}" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" | jq
```

The new credentials appear in the `awsAccounts` list.
