# Create and protect an application

Create an application in Backup and Recovery for Kubernetes and assign a protection policy to it.

Script: [`create-app-API.sh`](create-app-API.sh)

## Prerequisites

- [Authentication](../00-authentication/README.md) and [account discovery](../01-account-discovery/README.md) completed.
- A discovered cluster, see [cluster onboarding](../03-cluster-onboarding/README.md).
- A protection policy, see [protection policies](../04-protection-policies/README.md).

## Required variables

```bash
export ACCESS_TOKEN="<access_token>"       # BEARER_TOKEN is accepted as an alias
export ACCOUNT_ID="<account_public_id>"    # ORG_ID is accepted as an alias
export AGENT_ID="<console_agent_id>"
export CONSOLE_API="https://cloudmanager.cloud.netapp.com"   # API_HOST is accepted as an alias
```

## Create the application

```bash
./create-app-API.sh --cluster-name "<cluster_name>" --app-name "<app_name>" \
  --namespaces "<namespace>" --policy-name "<policy_name>"
```

Further options: `--label-selectors`, `--app-type virtual-machine-label-selector` with the VM freeze flags, and `--site-prefix` with `--policy-file` to look up several policies by prefixed name. Run `./create-app-API.sh --help` for all options.

The API response is saved to `RESPONSE_FILE` (default `/tmp/netapp_create_app_response.json`).

## Verify

Check in the Console, under Backup and Recovery for Kubernetes, that the application is listed with its policy.
