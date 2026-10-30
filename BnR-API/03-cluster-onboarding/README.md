# Cluster onboarding

Automate discovery of a new Kubernetes cluster in NetApp Backup and Recovery without using the Console UI.

Prerequisites: [authentication](../00-authentication/README.md) and [account discovery](../01-account-discovery/README.md) completed, `kubectl` and `helm` configured for the target cluster, and the Trident Protect Helm repository added.

## OCCM credentials

OCCM credentials authenticate Trident Protect on the cluster against the Console. They must exist **before** you install Trident Protect.

### Create an OCCM credential

```bash
export OCCM_NAME="<occm_name>"

curl --no-progress-meter -X POST \
  "${CONSOLE_API}/account/${ACCOUNT_ID}/providers/cloudmanager_occmauth/api/v0.1/services" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "X-Account-Id: ${ACCOUNT_ID}" \
  -H "x-agent-id: ${AGENT_ID}" \
  -d "$(jq -n --arg name "$OCCM_NAME" '{name: $name}')" | jq .
```

Save `OCCM_ID`, `CLIENT_ID` and `CLIENT_SECRET` for later use. **The client secret is only shown once.**

```bash
export OCCM_ID="<occm_id>"
export CLIENT_ID="<clientID>"
export CLIENT_SECRET="<clientSecret>"
```

This variant stores the result directly in environment variables:

```bash
export OCCM_NAME="<occm_name>"

RESPONSE=$(curl --no-progress-meter --fail-with-body -X POST \
  "${CONSOLE_API}/account/${ACCOUNT_ID}/providers/cloudmanager_occmauth/api/v0.1/services" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "X-Account-Id: ${ACCOUNT_ID}" \
  -H "x-agent-id: ${AGENT_ID}" \
  -d "$(jq -n --arg name "$OCCM_NAME" '{name: $name}')")

if jq -e '.statusCode >= 400' <<< "$RESPONSE" >/dev/null 2>&1; then
  echo "Request failed:" >&2
  jq . <<< "$RESPONSE" >&2
else
  export OCCM_ID=$(jq -r '.id' <<< "$RESPONSE")
  export CLIENT_ID=$(jq -r '.clientId' <<< "$RESPONSE")
  export CLIENT_SECRET=$(jq -r '.clientSecret' <<< "$RESPONSE")
  echo "OCCM_ID=$OCCM_ID"
  echo "CLIENT_ID=$CLIENT_ID"
  echo "CLIENT_SECRET stored (${#CLIENT_SECRET} chars)"
fi
```

Or use the script [`create-occm-credential.sh`](scripts/create-occm-credential.sh):

```bash
eval "$(./scripts/create-occm-credential.sh "${OCCM_NAME}")"
```

### List existing OCCM credentials

```bash
curl --get "${CONSOLE_API}/account/${ACCOUNT_ID}/providers/cloudmanager_occmauth/api/v0.1/services" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "X-Account-Id: ${ACCOUNT_ID}" \
  -H "x-agent-id: ${AGENT_ID}" | jq
```

### Delete an OCCM credential

Delete the credential when it is no longer needed:

```bash
curl -i -X DELETE \
  "${CONSOLE_API}/account/${ACCOUNT_ID}/providers/cloudmanager_occmauth/api/v0.1/services/${OCCM_ID}" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "X-Account-Id: ${ACCOUNT_ID}" \
  -H "x-agent-id: ${AGENT_ID}"
```

## Install Trident Protect and connect to Backup and Recovery

Create the `trident-protect` namespace and the `occmauthcreds` secret from the credential created above:

```bash
kubectl create ns trident-protect

kubectl create secret generic occmauthcreds \
  --namespace=trident-protect \
  --from-literal=client_id=${CLIENT_ID} \
  --from-literal=client_secret=${CLIENT_SECRET}
```

Set the Trident Protect version (for example `100.2609.0-console`; use the version you want to deploy) and the cluster name, then run the Helm install:

```bash
export TP_VERSION="100.2609.0-console"
export CLUSTER_NAME="<cluster_name>"

helm upgrade --install trident-protect \
  netapp-trident-protect/trident-protect-console \
  --version ${TP_VERSION} \
  --namespace trident-protect \
  --set clusterName=${CLUSTER_NAME} \
  --set trident-protect.cbs.accountID=${ACCOUNT_ID} \
  --set trident-protect.cbs.agentID=${AGENT_ID} \
  --set trident-protect.cbs.proxySecretName=occmauthcreds \
  --set trident-protect.cbs.proxyHostIP=${AGENT_URL}
```

See the [Trident Protect documentation](https://docs.netapp.com/us-en/trident/trident-protect/) for supported versions.

## List discovered clusters

```bash
curl -sS --location \
  "${CONSOLE_API}/backup-recovery/organizations/${ACCOUNT_ID}/v1/workloads/k8s/clusters" \
  -H "x-agent-id: ${AGENT_ID}" \
  -H "x-account-id: ${ACCOUNT_ID}" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | jq '.items[] | {id, name, state}'
```

Or use [`list-clusters.sh`](scripts/list-clusters.sh).

A newly onboarded cluster should report the state `connected` shortly after the Helm install finishes.
