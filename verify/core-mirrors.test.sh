#!/usr/bin/env bash
# The two leaves each ship a snapshot of the provider-neutral core law, and a
# lesson landing in one snapshot but not the other is exactly how harnesses
# drift apart — so byte-identity between them is a gate, not a convention.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
a="$root/skill/claude-controlled-build-run/references/core"
b="$root/skill/codex-controlled-build-run/references/cbr-core"

[ -d "$a" ] || { echo "core-mirrors.test FAIL: missing $a" >&2; exit 1; }
[ -d "$b" ] || { echo "core-mirrors.test FAIL: missing $b" >&2; exit 1; }

if ! diff -r "$a" "$b" >&2; then
  echo "core-mirrors.test FAIL: the Claude and Codex core snapshots differ — apply the same change to both" >&2
  exit 1
fi

echo "core-mirrors.test OK: both core snapshots are byte-identical"
