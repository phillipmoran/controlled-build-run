#!/usr/bin/env bash
set -uo pipefail

command -v roborev >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0
branch="$(git branch --show-current 2>/dev/null || true)"
[ -n "$branch" ] || exit 0

fails="$(roborev list --open --json --branch "$branch" 2>/dev/null \
  | jq -r '(. // []) | [.[] | select(.verdict == "F")][:10][] | "Job #\(.id)  \(.git_ref[0:7])  \(.commit_subject)"' 2>/dev/null || true)"
count="$(printf '%s' "$fails" | grep -c . || true)"
msg="RoboRev gate armed for $branch. Open FAIL reviews: ${count}."

# PORTING: repo-relative path to the core tripwires script ([ -f ]-guarded —
# a port that hasn't installed it still sweeps cleanly)
TRIPWIRES_REL="skills/cbr-core/scripts/tripwires.sh"
trips=""
[ -f "$TRIPWIRES_REL" ] && \
  trips="$(CBR_TRIPWIRE_NOTIFY=echo bash "$TRIPWIRES_REL" 2>/dev/null || true)"
[ -n "$trips" ] && msg="$msg Process tripwires FIRED — see context."

if [ "${count:-0}" -eq 0 ] 2>/dev/null && [ -z "$trips" ]; then
  jq -n --arg msg "$msg" '{systemMessage: $msg}'
  exit 0
fi

ctx=""
[ "${count:-0}" -gt 0 ] 2>/dev/null && \
  ctx="RoboRev session sweep — ${count} open FAIL review(s) need a response and close, or explicit escalation:\n\n${fails}"
[ -n "$trips" ] && \
  ctx="${ctx:+${ctx}\n\n}Process-health tripwires (recorder event log) — investigate and surface the cause; thresholds live in skills/cbr-core/scripts/tripwires.sh:\n\n${trips}"
jq -n --arg msg "$msg" --arg ctx "$ctx" \
  '{systemMessage: $msg, hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
exit 0
