#!/usr/bin/env bash
# Stop hook. Translation only: read this provider's payload, ask the shared
# core predicate, speak this provider's verdict. The rule itself lives in
# references/cbr-core/scripts/stop-predicate.sh and is written exactly once.
#
# This leaf pins NEEDS-HUMAN.md as the operator park file — the name this
# control plane tells its operator to write (references/agent-harness.md, and C12 in
# CODEX-COVERAGE.md). The predicate takes it as an argument rather than
# guessing, because the other leaf pins a different one.
#
# The allow verdict is `{}` and the refusal is {"decision":"block","reason":…},
# per the documented Stop-hook contract in references/agent-harness.md.
set -uo pipefail

payload="$(cat 2>/dev/null || true)"
root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Every path that lets a stop through WITHOUT a terminal fact leaves this
# behind. The gate cannot always hold — not a session already refused once, not
# one whose predicate is broken — but a bypass nobody can see is the same blind
# spot the gate exists to close, one level up. The watcher latches this file.
unguarded() { # unguarded <reason>
  printf '%s\n%s — %s\n' \
    "$(git -C "$root" branch --show-current 2>/dev/null || echo unknown-branch)" \
    "$(date -u +%FT%TZ)" "$1" > "$root/STOP-UNGUARDED.marker" 2>/dev/null || true
  echo "builder-stop-check: STOPPING UNGUARDED — $1" >&2
  printf '{}\n'
  exit 0
}

pred="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../references/cbr-core/scripts/stop-predicate.sh"
[ -f "$pred" ] || pred="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../cbr-core/scripts/stop-predicate.sh"
[ -f "$pred" ] || pred="$root/.agents/skills/codex-controlled-build-run/references/cbr-core/scripts/stop-predicate.sh"
[ -f "$pred" ] || pred="$root/skills/codex-controlled-build-run/references/cbr-core/scripts/stop-predicate.sh"
[ -f "$pred" ] || pred="$root/skills/cbr-core/scripts/stop-predicate.sh"

# Fails OPEN when the predicate cannot answer, deliberately against the usual
# rule for an enforcement guard: every release the gate honours is read BY the
# predicate, so failing closed without it would refuse the stop and refuse
# every way out of it at once.
[ -f "$pred" ] || unguarded "the shared stop predicate is missing ($pred); repair the control plane"

reason="$(bash "$pred" --worktree "$root" --park-file NEEDS-HUMAN.md 2>&1)"; rc=$?

# rc 2 and up is "could not decide", not "must not stop". Translating it as a
# block traps the session exactly the way a missing predicate would.
[ "$rc" -ge 2 ] && unguarded "the stop predicate could not decide (rc=$rc): $reason"
[ "$rc" -eq 0 ] && { printf '{}\n'; exit 0; }

# One continuation at a time: re-blocking a session that is already blocking is
# the infinite loop. The second stop is allowed and RECORDED.
if printf '%s' "$payload" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
  unguarded "stopped past the gate's refusal with the plan unfinished"
fi

python3 - "$reason" <<'PY' 2>/dev/null || printf '{"decision":"block","reason":"Stop refused by the shared stop predicate; run it directly to read why."}\n'
import json, sys
print(json.dumps({"decision": "block", "reason": sys.argv[1]}))
PY
