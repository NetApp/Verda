# Automating NetApp Backup and Recovery with the API

Community examples for automating NetApp Backup and Recovery operations through the NetApp Console API with `curl` and `jq`.

> **Support:** These examples are provided as-is under **Community Support** and are not officially supported by NetApp. The NetApp Console API can change. Always check the [official API documentation](https://docs.netapp.com/us-en/console-automation/) and test in a non-production environment first.

## Prerequisites

- A NetApp Console account with a deployed Console agent
- `bash`, `curl` and [`jq`](https://jqlang.github.io/jq/)
- For cluster onboarding: `kubectl` and `helm`

## How to use this folder

Work through the sections in order the first time. Later sections assume the environment variables set up in the earlier ones.

| Section | What it covers |
| ------- | -------------- |
| [00-authentication](00-authentication/README.md) | Refresh token → access token, environment variable summary |
| [01-account-discovery](01-account-discovery/README.md) | Find account (organization) ID, workspace/project ID, agent ID; check agent association |
| [02-credentials-and-targets](02-credentials-and-targets/) | Add cloud and object storage credentials: [Azure](02-credentials-and-targets/azure.md), [AWS S3](02-credentials-and-targets/aws-s3.md), [ONTAP S3](02-credentials-and-targets/ontap-s3.md), [StorageGRID](02-credentials-and-targets/storagegrid.md) (untested) |
| [03-cluster-onboarding](03-cluster-onboarding/README.md) | Create an OCCM credential, install Trident Protect, list discovered Kubernetes clusters |
| [lib](lib/bnr-common.sh) | Shared shell helpers used by the scripts |

## Conventions

- Every example uses environment variables (`CONSOLE_API`, `ACCOUNT_ID`, `AGENT_ID`, `ACCESS_TOKEN`, ...). Nothing is hard-coded.
- All IDs, hostnames, keys and secrets are **placeholders**. Never commit real values.
- Each topic follows the same structure: purpose, required variables, command, verification. Example output is intentionally not included; it differs per environment.
- Copy `00-authentication/env.sh.example` to `env.sh`, fill it in, and `source` it. `env.sh` is git-ignored.
- Treat refresh tokens, access tokens, client secrets and cloud keys like passwords.

## Contributing

See the [Contribution Guide](../README.md#contribution-guide) in the main README. For API examples, please also:

1. Follow the topic structure above and use placeholders only.
2. Note the date and Console/Trident Protect version you tested with.
3. Mark untested commands clearly with "Untested" in the title.
4. Run `shellcheck` on any `.sh` file.
