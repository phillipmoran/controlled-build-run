#!/usr/bin/env bash
# RoboRev session-start sweep. At session boot: surface any OPEN FAIL reviews
# (verdict F, not yet closed) so cross-session stragglers are not forgotten,
# and emit a one-line liveness note to the user. The note's presence each
# boot confirms the hook system — and thus the per-commit gate, loaded from
# the same settings file — is armed. Fails open: any trouble exits silent.
set -uo pipefail

command -v roborev >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

fails="$(roborev list --open --json --limit 50 2>/dev/null \
  | jq -r '[.[] | select(.verdict=="F")][:10][] | "Job #\(.id)  \(.git_ref[0:7])  \(.commit_subject)"' 2>/dev/null || true)"

count="$(printf '%s' "$fails" | grep -c . || true)"

liveness="RoboRev gate armed. Open FAIL reviews: ${count}."

if [ "${count:-0}" -eq 0 ] 2>/dev/null; then
  jq -n --arg msg "$liveness" '{systemMessage: $msg}'
  exit 0
fi

ctx="RoboRev session sweep — ${count} open FAIL review(s) still need action (fix / close-with-reason via 'roborev respond' + 'roborev close' / surface to the operator):

${fails}"

jq -n --arg msg "$liveness" --arg ctx "$ctx" \
  '{systemMessage: $msg, hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
exit 0
