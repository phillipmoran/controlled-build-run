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

find . -type f ! -name 'MANIFEST.sha256' | sed 's|^\./||' | sort | xargs "${sha_tool[@]}" > MANIFEST.sha256
