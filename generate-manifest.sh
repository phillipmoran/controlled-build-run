#!/usr/bin/env bash
# Regenerates MANIFEST.sha256 from the current contents of this directory.
# Run this after any edit under kit/, then commit the updated manifest.
set -euo pipefail

kit_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$kit_dir"

sha_tool=(sha256sum)
if ! command -v sha256sum >/dev/null 2>&1; then
  sha_tool=(shasum -a 256)
fi

# .git is pruned because this script also runs at the root of the standalone
# package repo, where hashing repository internals would make the manifest
# stale on every commit. Both forms matter: a directory in a normal clone,
# a gitdir-pointer FILE in a linked worktree.
# MANIFEST.ignore (optional, one glob per line, # comments) names files that
# live in the repo but do not ship — README, CI, plugin wrapper. The manifest
# is the fingerprint of the ARTIFACT, not of repo housekeeping, so editing a
# doc must not stale it. Absent the file (the kit directory), everything ships.
patterns=()
if [ -f MANIFEST.ignore ]; then
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue;; esac
    patterns+=("$line")
  done < MANIFEST.ignore
fi
shipped() {
  local f="$1" p
  for p in "${patterns[@]+"${patterns[@]}"}"; do
    case "$f" in $p) return 1;; esac
  done
  return 0
}
shipped_files() {
  find . -type f ! -name 'MANIFEST.sha256' ! -path './.git' ! -path './.git/*' | sed 's|^\./||' | sort \
    | while IFS= read -r f; do shipped "$f" && printf '%s\n' "$f"; done
}
# --list prints the shipped path set and stops. The drift gate (export.sh
# --check) uses it so generation and validation share ONE discovery rule.
if [ "${1:-}" = "--list" ]; then
  shipped_files
  exit 0
fi
shipped_files | xargs "${sha_tool[@]}" > MANIFEST.sha256
