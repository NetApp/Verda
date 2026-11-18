#!/usr/bin/env bash
# Copy the scripts and docs each skill needs from the numbered sections of BnR-API
# into the skill folders, so every skill is self-contained and can be packaged.
#
# Usage:  ./sync.sh           copy everything
#         ./sync.sh -h        show this help
#
# The numbered sections (00-authentication ... 07-create-app, lib) are the source of
# truth. The copies inside the skill folders are generated: never edit them, edit the
# source and run this script again. The same goes for skills/_shared, which is copied
# to <skill>/references/.
#
# The folder layout inside a skill mirrors BnR-API, so the scripts find
# lib/bnr-common.sh with the same relative path (../../lib) as in the repository.
set -euo pipefail

case "${1:-}" in
  "") ;;
  -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "ERROR: unknown option $1" >&2; exit 1 ;;
esac

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="$(cd "$here/.." && pwd)"

# copy_item <skill> <path relative to BnR-API>: replace the copy inside the skill folder.
copy_item() {
  local skill=$1 rel=$2
  case "$skill" in ""|*/*|*..*) echo "ERROR: bad skill name '$skill'" >&2; exit 1 ;; esac
  case "$rel" in ""|/*|*..*) echo "ERROR: bad path '$rel'" >&2; exit 1 ;; esac
  [ -e "$src/$rel" ] || { echo "ERROR: $rel does not exist in BnR-API" >&2; exit 1; }
  [ -d "$here/$skill" ] || { echo "ERROR: skill folder $skill does not exist" >&2; exit 1; }
  mkdir -p "$(dirname "$here/$skill/$rel")"
  rm -rf "${here:?}/${skill:?}/${rel:?}"
  cp -Rp "$src/$rel" "$here/$skill/$rel"
}

# Items every skill needs: shared helpers, authentication and account discovery.
common_items() {
  local skill=$1
  copy_item "$skill" lib
  copy_item "$skill" 00-authentication/README.md
  copy_item "$skill" 00-authentication/env.sh.example
  copy_item "$skill" 01-account-discovery
}

sync_skill() {
  local skill=$1
  common_items "$skill"
  case "$skill" in
    bnr-k8s-setup)
      copy_item "$skill" 02-credentials-and-targets
      copy_item "$skill" 03-add-ontap-to-canvas
      copy_item "$skill" 04-create-backup-target
      copy_item "$skill" 05-cluster-onboarding
      ;;
    bnr-k8s-policies)
      copy_item "$skill" 04-create-backup-target/scripts/list-buckets.sh
      copy_item "$skill" 06-protection-policies
      ;;
    bnr-k8s-protect)
      copy_item "$skill" 05-cluster-onboarding/scripts/list-clusters.sh
      copy_item "$skill" 06-protection-policies/scripts/list-k8s-policies.sh
      copy_item "$skill" 07-create-app
      ;;
    *) echo "ERROR: unknown skill $skill" >&2; exit 1 ;;
  esac

  # Shared references (generated copies).
  mkdir -p "$here/$skill/references"
  cp -p "$here/_shared/conventions.md" "$here/$skill/references/conventions.md"
  cp -p "$here/_shared/tested-status.md" "$here/$skill/references/tested-status.md"

  find "$here/$skill" -name .DS_Store -delete 2>/dev/null || true
}

for skill in bnr-k8s-setup bnr-k8s-policies bnr-k8s-protect; do
  sync_skill "$skill"
  scripts=$(find "$here/$skill" -name '*.sh' | wc -l | tr -d ' ')
  files=$(find "$here/$skill" -type f | wc -l | tr -d ' ')
  echo "$skill: $files files ($scripts scripts)"
done
