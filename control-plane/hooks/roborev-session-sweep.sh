#!/usr/bin/env bash
# RoboRev session-start sweep. At session boot: surface any OPEN FAIL reviews
# (verdict F, not yet closed) so cross-session stragglers are not forgotten,
# and emit a one-line liveness note to the user. The note's presence each
# boot confirms the hook system — and thus the per-commit gate, loaded from
# the same settings file — is armed. Also surfaces any tripped process-health
# wires from the recorder log. Fails open: any trouble exits silent.
set -uo pipefail

command -v roborev >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

fails="$(roborev list --open --json --limit 50 2>/dev/null \
  | jq -r '[.[] | select(.verdict=="F")][:10][] | "Job #\(.id)  \(.git_ref[0:7])  \(.commit_subject)"' 2>/dev/null || true)"

count="$(printf '%s' "$fails" | grep -c . || true)"

# PORTING: repo-relative path to the core tripwires script ([ -f ]-guarded —
# a port that hasn't installed it still sweeps cleanly)
TRIPWIRES_REL="skills/cbr-core/scripts/tripwires.sh"
trips=""
[ -f "$TRIPWIRES_REL" ] && \
  trips="$(CBR_TRIPWIRE_NOTIFY=echo bash "$TRIPWIRES_REL" 2>/dev/null || true)"

liveness="RoboRev gate armed. Open FAIL reviews: ${count}."
[ -n "$trips" ] && liveness="$liveness Process tripwires FIRED — see context."

ctx=""
if [ "${count:-0}" -gt 0 ] 2>/dev/null; then
  ctx="RoboRev session sweep — ${count} open FAIL review(s) still need action (fix / close-with-reason via 'roborev respond' + 'roborev close' / surface to the operator):

${fails}"
fi
if [ -n "$trips" ]; then
  [ -n "$ctx" ] && ctx="$ctx

"
  ctx="${ctx}Process-health tripwires (recorder event log) — investigate the cause and surface it to the operator; thresholds live in skills/cbr-core/scripts/tripwires.sh:

${trips}"
fi

if [ -z "$ctx" ]; then
  jq -n --arg msg "$liveness" '{systemMessage: $msg}'
  exit 0
fi

jq -n --arg msg "$liveness" --arg ctx "$ctx" \
  '{systemMessage: $msg, hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
exit 0
