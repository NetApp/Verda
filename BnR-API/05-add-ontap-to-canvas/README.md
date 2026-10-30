# Add an ONTAP cluster to the canvas

Add an on-premises ONTAP cluster to the NetApp Console storage canvas. This is a prerequisite when the cluster should act as a secondary target (disk-to-disk, 3-2-1 fan-out) for [protection policies](../04-protection-policies/README.md).

Script: [`add-ontap-cluster-to-canvas.sh`](add-ontap-cluster-to-canvas.sh)

## Required variables

Set up [authentication](../00-authentication/README.md) and [account discovery](../01-account-discovery/README.md) first. The Console agent must be associated with a workspace/project and must be able to reach the cluster-management address.

```bash
export ACCESS_TOKEN="<access_token>"       # BEARER_TOKEN is accepted as an alias
export ACCOUNT_ID="<account_public_id>"    # ORG_ID is accepted as an alias
export AGENT_ID="<console_agent_id>"
export CONSOLE_API="https://cloudmanager.cloud.netapp.com"   # API_HOST is accepted as an alias
export CLUSTER_PASSWORD="<cluster_password>"                  # avoid --cluster-password: visible in ps
```

Optional: `WORKSPACE_ID` (aliases `TENANT_ID`, `PROJECT_ID`) or `PROJECT_NAME`. If neither is set, the script looks for the one workspace the agent is associated with.

## Preview the request

```bash
./add-ontap-cluster-to-canvas.sh --cluster-address "<cluster_mgmt_address>" --dry-run
```

The password is redacted in the output and no API call is made.

## Add the cluster

```bash
./add-ontap-cluster-to-canvas.sh --cluster-address "<cluster_mgmt_address>" \
  --cluster-user-name admin --name "<canvas_name>"
```

The API response is saved to `RESPONSE_FILE` (default `/tmp/netapp_add_ontap_cluster_response.json`). HTTP 2xx means the request was accepted, not that discovery has finished.

## Verify

Open the Console canvas and check that the cluster appears and reaches a healthy state. Run `./add-ontap-cluster-to-canvas.sh --help` for all options.
