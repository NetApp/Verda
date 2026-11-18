---
name: bnr-k8s-protect
description: Create and protect Kubernetes applications with NetApp Backup and Recovery for Kubernetes (Trident Protect) through the NetApp Console API or Application CR annotations, verify that the first backup succeeded, run on-demand backups, and unprotect or delete applications. Use this skill whenever the user wants to protect, back up, unprotect or register a Kubernetes/OpenShift namespace or application, mentions create-app-API.sh, protection-policy-name, protection-command annotations, protectionState, Protected/Failed/Partial, tridentctl-protect, or asks "did my backup work", even if they don't mention the API.
---

# Backup and Recovery for Kubernetes: applications

**Experimental.** This skill is still experimental. Tell the user so at the start of a session, and recommend a test account or non-production resources first.

Bundled bash scripts in `07-create-app/scripts/`. Needs a cluster that is `connected` (`05-cluster-onboarding/scripts/list-clusters.sh`) and, to protect, an existing policy (`06-protection-policies/scripts/list-k8s-policies.sh`). If either is missing, use `bnr-k8s-setup` or `bnr-k8s-policies`.

Read `references/conventions.md` first (secrets, protocol, naming) and check `references/tested-status.md`. Full details: `07-create-app/README.md`.

## Workflow

1. **Look up**: `list-clusters.sh` (cluster ID and state) and `list-k8s-policies.sh` (policy name). Never guess the cluster, namespace or policy; ask.
2. **Create**: `./create-app-API.sh --help`, then run with `--dry-run` first. `--policy-name` is optional: with it the application is created and protected in one run; without it the application is only registered and the script prints ways to protect it later. `--site-prefix` and `--policy-file` need `--policy-name` and are untested, as are label selectors and VM applications.
3. **Confirm, then run** for real. The API accepts the request before backups exist.
4. **Protect later** (if created without a policy), three ways: in the Console; POST to the application's `/protect` URL (printed by the script, tested live); or annotate the Application CR on the cluster:

   ```bash
   kubectl annotate application <app> -n <ns> \
     protect.trident.netapp.io/protection-policy-name=<policy> \
     protect.trident.netapp.io/protection-command=protect
   ```

   `tridentctl-protect create application <app> --namespaces <ns> -n <ns> --annotation ...` is the same via CLI (documented in a NetApp Community post, not tested here).
5. **Verify the first backup**. Read the CR annotations: `kubectl get application <app> -n <ns> -o jsonpath='{.metadata.annotations}'`. `protection-state` is `Protected` on success or `Failed` (see `protection-state-msg`). While the first backup runs, `status.protectionState` shows Partial / "Scheduled backup unavailable"; that is normal and takes a few minutes. A failure often names a backup target or secondary system that is unreachable from the agent; report the message as is. To see which part is still running: `kubectl -n <ns> get schedules,snapshots,backups,cbsvolumebackups,cbsrelationship,replicatesnapshots` (`cbsrelationship` shows cloud and replication baseline progress; `replicatesnapshots` is for secondary-system policies). The `protection-state` annotation appears only when the first backup finishes. An on-demand backup: `tridentctl-protect create backup --app <app> --appvault <vault> --data-mover CBS -n <ns>`.
6. **Stop protection**: set `protection-command=unprotect`. Backups are kept. Several applications on one namespace work.
7. **Delete an application**: only in the Console, and only after unprotecting. Deleting with "Delete snapshots and backups" also removes backups and objects in the bucket and cannot be undone. State this and get an explicit yes first; never delete anything the user did not name.

## Guardrails

- Run cluster commands (`kubectl`, `tridentctl-protect`) only when the shell can reach the cluster; otherwise give the user the commands.
- Restore operations are not covered by these scripts.
- Report what verification showed, and what was not verified.
