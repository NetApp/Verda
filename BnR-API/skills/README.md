# AI skills for Backup and Recovery for Kubernetes

> **Experimental.** These skills are still experimental. They drive scripts that create and delete real cloud resources. Use a test account or non-production resources first, review every dry run, and see `_shared/tested-status.md` for what has been verified.

Three skills built on the scripts and docs of the numbered BnR-API sections:

| Skill | Covers |
| --- | --- |
| `bnr-k8s-setup` | Sections 00-05: authentication, discovery, credentials, backup targets, ONTAP on the canvas, cluster onboarding |
| `bnr-k8s-policies` | Section 06: list, create and delete protection policies |
| `bnr-k8s-protect` | Section 07 and annotations: create/protect applications, verify, unprotect |

## Layout

```
skills/
  _shared/          conventions.md, tested-status.md (source of truth)
  sync.sh           copies scripts and docs into the skill folders
  bnr-k8s-*/        SKILL.md (hand-written) + generated copies
```

Inside each skill folder the layout mirrors BnR-API (`lib/`, `00-authentication/`, `06-protection-policies/scripts/`, ...), so the scripts find `lib/bnr-common.sh` the same way as in the repository. `references/` holds copies of `_shared/`.

## Maintaining

Never edit the generated copies. Edit the numbered sections (or `_shared/`), then run:

```bash
./sync.sh
```

Only each `SKILL.md` is edited by hand. Update `_shared/tested-status.md` when test results change.

## Install

Package each skill folder as a `.skill` file (zip with the folder at its root) and add it in Claude, or copy the folders to the skills directory of Claude Code.

## Safety

The skills create real cloud resources. They follow the protocol in `_shared/conventions.md`: look up, dry run, explicit yes, run, verify. They were not evaluated against the live API with automated runs.
