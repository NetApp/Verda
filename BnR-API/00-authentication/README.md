# Authentication

Every API call needs an access token. You create it from a long-lived refresh token.
See also the [NetApp Console automation documentation](https://docs.netapp.com/us-en/console-automation/).

## Set the Console API URL

```bash
export CONSOLE_API=https://cloudmanager.cloud.netapp.com
```

## Generate a refresh token

1. Open the [Refresh Token Generator](https://services.cloud.netapp.com/refresh-token) and generate a token for your Console account.
2. Store it in `REFRESH_TOKEN`. **Treat the refresh token like a password.**

```bash
export REFRESH_TOKEN="<refresh_token>"
```

## Exchange the refresh token for an access token

This call goes to the Auth0 authentication service, not to the Console API. The client identifier in the JSON input is the same constant value for all customers and is also listed in the official documentation.

```bash
export ACCESS_TOKEN=$(
curl -s -X POST "https://netapp-cloud-account.auth0.com/oauth/token" \
  -H "Content-Type: application/json" \
  -d "{
    \"grant_type\": \"refresh_token\",
    \"refresh_token\": \"${REFRESH_TOKEN}\",
    \"client_id\": \"Mu0V1ywgYteI6w1MbD15fKfVIUrNXGWC\"
  }" | jq -r .access_token
)
```

Verify that the token is set (prints the number of characters, not the token):

```bash
echo "${#ACCESS_TOKEN} characters"
```

The access token expires. If calls start returning `401`, run the exchange again.

## Environment variable summary

After completing [account discovery](../01-account-discovery/README.md), these variables are set. A template is in [`env.sh.example`](env.sh.example).

```bash
export CONSOLE_API="https://cloudmanager.cloud.netapp.com"
export REFRESH_TOKEN="<refresh_token>"
export ACCOUNT_ID="<accountPublicId>"
export WORKSPACE_ID="<workspacePublicId>"
export AGENT_ID="<agentID>"
export AGENT_IP="<agentIP>"
export AGENT_URL="https://${AGENT_IP}"
```
