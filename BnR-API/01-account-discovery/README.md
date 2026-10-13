# Account discovery

Find the IDs that the later API calls need. Requires `ACCESS_TOKEN` from [authentication](../00-authentication/README.md).

## Find the account ID

List the accounts available to your user:

```bash
curl -sS "${CONSOLE_API}/tenancy/account" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Accept: application/json" | jq
```

Store the `accountPublicId` of the account you work with:

```bash
export ACCOUNT_ID="<accountPublicId>"
```

Alternatively, in the Console UI go to **Administration → Identity and access → Organization** and copy the **Organization ID**.

## Find the workspace ID

> **Note:** In the newer Console UI, what the API still calls a *workspace* is shown as a **Project**. The association is managed under **Identity and access → Resources → Projects**, not from the agent's `...` menu.

List the workspaces (projects) of the account in tabular form:

```bash
curl -sS -X GET "${CONSOLE_API}/tenancy/account/${ACCOUNT_ID}/workspace" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Accept: application/json" | jq -r '
    if type == "array" then .[]
    else (.workspaces // .data // .items // []) | .[]
    end
    | [ (.workspaceName // .name // "unknown-name"),
        (.publicId // .workspacePublicId // .id // "unknown-id") ]
    | @tsv'
```

```bash
export WORKSPACE_ID="<workspacePublicId>"
```

## Find the agent address

In the Console UI, open the agent overview (or the agent's local UI) to find its IP address.

```bash
export AGENT_IP="<agentIP>"
export AGENT_URL="https://${AGENT_IP}"
```

## Find the agent ID

In the Console UI go to **Administration → Agents**, open the agent's action menu, and copy the **Agent ID**.

```bash
export AGENT_ID="<agentID>"
```

## Check that the agent is associated with a workspace/project

The following steps only work if the agent is associated with a workspace/project. List workspaces together with their associated agents:

```bash
curl -sS "${CONSOLE_API}/tenancy/account/${ACCOUNT_ID}/workspace" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Accept: application/json" | jq
```

This confirms which agent is associated with which workspace. Your `AGENT_ID` should appear in `associatedAgents` of the workspace you use. If it doesn't, fix it in the Console UI: **Administration → Identity and access → Agents** (Console UI as of October 2026), open the agent's action menu, choose **Associate to folder or project**, and select the right project.
