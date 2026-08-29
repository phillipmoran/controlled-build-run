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

if [ "${count:-0}" -eq 0 ] 2>/dev/null; then
  jq -n --arg msg "$msg" '{systemMessage: $msg}'
  exit 0
fi

ctx="RoboRev session sweep — ${count} open FAIL review(s) need a response and close, or explicit escalation:\n\n${fails}"
jq -n --arg msg "$msg" --arg ctx "$ctx" \
  '{systemMessage: $msg, hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
exit 0
