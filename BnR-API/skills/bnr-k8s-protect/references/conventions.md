# Conventions for the Backup and Recovery for Kubernetes skills

**These skills are still experimental.** Say so to the user at the start of a session and recommend test or non-production resources first.

These rules apply to all three skills (`bnr-k8s-setup`, `bnr-k8s-policies`, `bnr-k8s-protect`). They exist because the scripts change real cloud resources: credentials, buckets, policies, schedules and backups that cost money and cannot always be undone.

## Where commands run

The scripts are bash with `curl` and `jq`. They call the NetApp Console API (`https://cloudmanager.cloud.netapp.com`). Some steps also use `kubectl`, `helm` or `tridentctl-protect` against the Kubernetes cluster.

- Run a script only if the shell you have can reach the API (and, for cluster steps, the cluster). If it can't, don't improvise with other tools. Give the user the exact command to run in their own terminal, and ask them to paste the output with secrets removed.
- Some shells start every command in a fresh environment, so variables set in one command are gone in the next. Source the user's environment file in the same command: `source <env file> && ./script.sh ...`.
- Scripts are meant to be run from their own `scripts/` folder (`cd` there first). They find `lib/bnr-common.sh` relative to themselves.

## Secrets

- Never ask the user to paste a refresh token, access token, client secret, cloud access key or password into the chat. Ask them to set it in their shell or env file, and check only that it is set (for example `echo "${#ACCESS_TOKEN} characters"`).
- Never print `ACCESS_TOKEN`, `REFRESH_TOKEN`, `CLIENT_SECRET`, `SECRETKEY`, `AWS_SECRET_ACCESS_KEY`, `CLUSTER_PASSWORD`. Scripts redact secrets in `--dry-run`; keep it that way and don't work around it.
- List calls return access key IDs in full (ONTAP S3 credentials, AWS credentials). Mask them when you summarize ("GYTW...") and don't repeat them in files.
- `ACCESS_TOKEN` expires. On a 401 run `bnr_renew_token` (defined in the user's env file, see `00-authentication/env.sh.example`) and retry once.

## Environment variables

| Variable | Meaning |
| --- | --- |
| `CONSOLE_API` | API host, default `https://cloudmanager.cloud.netapp.com` (alias `API_HOST`) |
| `ACCOUNT_ID` | Console organization ID, a UUID (alias `ORG_ID`) |
| `WORKSPACE_ID` | Workspace, shown as "Project" in the newer UI (aliases `TENANT_ID`, `PROJECT_ID`) |
| `AGENT_ID` | Console agent ID |
| `AGENT_IP`, `AGENT_URL` | Agent address (not discoverable through the API) |
| `ACCESS_TOKEN` | Bearer token from `REFRESH_TOKEN` (alias `BEARER_TOKEN`) |

Never guess an ID. If the user has several accounts, workspaces or agents, list them (`01-account-discovery/scripts/discover.sh`) and ask which one. A workspace can have several agents. Account IDs such as `account-xxxxxxxx` (not a UUID) are untested for Backup and Recovery; warn the user.

## Protocol for anything that creates, changes or deletes

1. **Look up first** with the read-only lookups and list calls of the scripts (`--list...`, `list-*.sh`). This catches wrong names and duplicates.
2. **Dry run** with `--dry-run`. Show the user the request body, or a short summary of it.
3. **Get an explicit yes** for the real call. Say what will be created or deleted and where (account, cluster, bucket, policy).
4. **Run it**, then **verify** with a list call. An HTTP 2xx means the request was accepted, not that the work is finished. Several calls return a job ID and the object appears later; the scripts' `--wait` polls for it.
5. **Report honestly**: what ran, what the verification showed, and anything not verified.

Deleting is the part to be strictest about. Say what disappears with it and that it can't be undone. Never delete something the user did not create in this session or name explicitly.

## Naming

- Use plain names with lowercase letters, digits and hyphens. Angle brackets from README placeholders (`<credential_name>`) end up literally in the name if copied: don't.
- AWS S3 bucket names for backup targets start with `netapp-backup-` (the Console UI requires it, the API does not). The script refuses other names unless `--skip-prefix-check` is given. Names have at most 63 characters.
- For tests, prefix names with something recognizable (`pu-test-...`) so they are easy to find and clean up.

## Untested paths

`references/tested-status.md` lists what has been run against a live system and what hasn't. Check it before using an option the user relies on. For an untested path, say so, use `--dry-run`, and prefer a non-production target. Never describe an untested path as working.

## Reading output

API responses are long. Summarize the few fields that matter (IDs, names, state, error) instead of pasting everything. When a call fails, show the server's error text; it is usually specific ("expected exactly one ONTAP S3 credential named ... Available credentials: ...").
