# Add an ONTAP cluster to the canvas

Add an on-premises ONTAP cluster to the NetApp Console storage canvas. This is a prerequisite when the cluster should act as a secondary target (disk-to-disk, 3-2-1 fan-out) for [protection policies](../06-protection-policies/README.md).

**Check the canvas first.** If the cluster is already on the canvas, for example because you added it earlier or it hosts your ONTAP S3 server, skip this section: a system can't be added a second time, and the existing system can serve as the secondary target (see `--list-secondary-targets` in [protection policies](../06-protection-policies/README.md)).

Script: [`add-ontap-cluster-to-canvas.sh`](scripts/add-ontap-cluster-to-canvas.sh). Status: `--dry-run` verified 2026-11-13 (the request body is built correctly and the password is redacted); the live add was not repeated in that run because the test cluster was already on the canvas.

Run the commands below from this section's `scripts/` folder (`cd scripts`).

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

The API response is saved to `RESPONSE_FILE` (default: a new private temporary file; the path is printed). HTTP 2xx means the request was accepted, not that discovery has finished.

## Verify

Open the Console canvas and check that the cluster appears and reaches a healthy state. Run `./add-ontap-cluster-to-canvas.sh --help` for all options.
