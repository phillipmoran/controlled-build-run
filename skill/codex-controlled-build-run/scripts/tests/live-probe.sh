#!/usr/bin/env bash
# Model-backed disposable Probity probe. Uses real Codex/Probity/RoboRev CLIs.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL="$(cd "$HERE/../.." && pwd -P)"
CBR="$SKILL/scripts/cbr-codex.sh"
SOURCE_REPO="$(git -C "$SKILL" rev-parse --show-toplevel)"
TMP="$(mktemp -d /private/tmp/cbr-codex-live.XXXXXX)"
REPO="$TMP/repo"
cleanup() {
  rc=$?
  if [ "$rc" -eq 0 ] && [ "${CBR_LIVE_KEEP:-0}" != 1 ]; then rm -rf "$TMP"; else echo "LIVE-PROBE-KEPT $TMP" >&2; fi
}
trap cleanup EXIT

mkdir -p "$REPO/packages"
git -C "$REPO" init -q -b main
printf '# live CBR probe fixture\n' >"$REPO/README.md"
git -C "$REPO" add README.md
git -C "$REPO" -c user.name='CBR Probe' -c user.email='cbr@example.invalid' commit -qm init
ln -s "$SOURCE_REPO/node_modules" "$REPO/node_modules"

"$CBR" arm "$REPO"
python3 - "$REPO/.cbr-codex.json" "$REPO/.pre-commit-config.yaml" <<'PY'
import json, sys
config, gate = sys.argv[1:]
data=json.load(open(config)); data['worktreePrefix']='fixture-'; data['toolchainProbe']='node --version'; data['verificationCommands']=['true']; data['liveSmokeCommand']='true'; json.dump(data,open(config,'w'),indent=2)
text=open(gate).read()
text=text.replace("entry: >-\n          sh -c 'echo \"EDIT .pre-commit-config.yaml: wire static checks\" >&2; exit 1'", 'entry: "true"')
text=text.replace("entry: >-\n          sh -c 'echo \"EDIT .pre-commit-config.yaml: wire tests\" >&2; exit 1'", 'entry: "true"')
open(gate,'w').write(text)
PY
"$CBR" sync-models "$REPO"
"$CBR" record-hook-trust "$REPO"
"$CBR" doctor "$REPO"
"$CBR" probe "$REPO"

if git -C "$REPO" status --short | grep -E 'probe_(untested|scratch)|probe-scratch'; then
  echo "LIVE-PROBE-FAIL probe artifact remains" >&2
  exit 1
fi
echo "LIVE-PROBE-PASS repo=$REPO"
