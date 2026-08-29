#!/usr/bin/env bash
# Verifies every file in this directory against MANIFEST.sha256.
# Exit 0: kit matches its manifest. Non-zero: something was edited/missing.
set -euo pipefail

kit_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
manifest="$kit_dir/MANIFEST.sha256"

if [[ ! -f "$manifest" ]]; then
  echo "verify-manifest: missing $manifest" >&2
  exit 1
fi

cd "$kit_dir"

if command -v sha256sum >/dev/null 2>&1; then
  sha256sum -c "$manifest"
else
  shasum -a 256 -c "$manifest"
fi
