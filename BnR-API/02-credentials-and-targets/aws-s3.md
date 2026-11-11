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

## Use the script (untested)

[`scripts/create-aws-credential.sh`](scripts/create-aws-credential.sh) makes the same call. It reads the three variables above, keeps the keys off the command line, and redacts them in `--dry-run`. Run it from the `scripts/` folder (`cd scripts`):

```bash
./create-aws-credential.sh --name "$AWS_ACCOUNT_NAME" --dry-run
./create-aws-credential.sh --name "$AWS_ACCOUNT_NAME" --wait
```

`AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are also the variables the AWS CLI reads, so check the access key shown in the summary (first four characters) before you send the request. With `--wait` the script polls the credential list until the new name appears under `awsAccounts` (up to `--timeout` seconds, default 120). `--list` prints the AWS credentials of the agent. The script has not been run against a live system yet.

## Verify

```bash
curl -sS -X GET --location "${CONSOLE_API}/occm/api/accounts/cloud-providers" \
  -H "x-agent-id: ${AGENT_ID}" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" | jq
```

The new credentials appear in the `awsAccounts` list.
