#!/usr/bin/env bash
# Stop hook. Translation only: read this provider's payload, ask the shared
# core predicate, speak this provider's verdict. The rule itself — which facts
# release a builder and which do not — lives in
# references/core/scripts/stop-predicate.sh and is written exactly once.
#
# This leaf pins NEEDS-OPERATOR.md as the operator park file, because that is the
# name every dispatch, watcher, and runbook in this repo tells a human to look
# for. The other leaf pins a different name; the predicate takes it as an
# argument rather than guessing.
set -uo pipefail

payload="$(cat 2>/dev/null || true)"
root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Every path that lets a stop through WITHOUT a terminal fact leaves this
# behind. The gate cannot always hold — it must not hold a session that has
# already been refused once, and it must not hold one whose predicate is
# broken — but a bypass nobody can see is the same blind spot the gate exists
# to close, one level up. Both watchers latch this file.
unguarded() { # unguarded <reason>
  printf '%s\n%s — %s\n' \
    "$(git -C "$root" branch --show-current 2>/dev/null || echo unknown-branch)" \
    "$(date -u +%FT%TZ)" "$1" > "$root/STOP-UNGUARDED.marker" 2>/dev/null || true
  echo "builder-stop-check: STOPPING UNGUARDED — $1" >&2
  # stderr from a hook that exits 0 is discarded, and a --bg builder has no
  # human on its transcript, so the reason also goes out through the channel
  # the transcript actually shows.
  python3 - "$1" <<'PY' 2>/dev/null || true
import json, sys
print(json.dumps({"systemMessage": "stop gate disarmed: " + sys.argv[1]
                  + " — STOP-UNGUARDED.marker written; the outside watcher will fire on it."}))
PY
  exit 0
}

pred="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../references/core/scripts/stop-predicate.sh"
[ -f "$pred" ] || pred="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../cbr-core/scripts/stop-predicate.sh"
[ -f "$pred" ] || pred="$root/.claude/skills/claude-controlled-build-run/references/core/scripts/stop-predicate.sh"
[ -f "$pred" ] || pred="$root/skills/claude-controlled-build-run/references/core/scripts/stop-predicate.sh"
[ -f "$pred" ] || pred="$root/skills/cbr-core/scripts/stop-predicate.sh"

# Fails OPEN when the predicate cannot answer, and this one is deliberate
# against the usual rule for an enforcement guard. Every release the gate
# honours is read BY the predicate, so failing closed without it would refuse
# the stop AND refuse every way out of it — an unescapable session, worse than
# the drift the gate exists to catch.
[ -f "$pred" ] || unguarded "the shared stop predicate is missing ($pred); repair the control plane"

reason="$(bash "$pred" --worktree "$root" --park-file NEEDS-OPERATOR.md 2>&1)"; rc=$?

# rc 2 and up means the predicate could not decide — called wrong, or its own
# infra is broken. Translating that as "block" is the same trap as failing
# closed on a missing predicate: the session cannot stop, and writing the park
# file would not help because the predicate never gets far enough to read it.
[ "$rc" -ge 2 ] && unguarded "the stop predicate could not decide (rc=$rc): $reason"
[ "$rc" -eq 0 ] && exit 0

# Already blocking. Re-blocking here is the infinite loop: the session cannot
# stop, cannot proceed, and burns tokens until something outside kills it. So
# the second stop is allowed — and recorded, because a builder going quiet with
# its plan open is exactly the event the fleet must not miss.
if printf '%s' "$payload" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
  unguarded "stopped past the gate's refusal with the plan unfinished"
fi

python3 - "$reason" <<'PY' 2>/dev/null || printf '{"decision":"block","reason":"Stop refused by the shared stop predicate; run it directly to read why."}\n'
import json, sys
print(json.dumps({"decision": "block", "reason": sys.argv[1]}))
PY
