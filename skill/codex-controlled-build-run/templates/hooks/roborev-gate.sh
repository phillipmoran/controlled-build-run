#!/usr/bin/env bash
# PostToolUse feedback: wait for a just-created commit's review and feed a real
# FAIL back to Codex. Optional surfacing fails open; pre-commit remains the hard gate.
set -uo pipefail

payload="$(cat)"
command_text="$(printf '%s' "$payload" | python3 -c '
import json, sys
try:
    print((json.load(sys.stdin).get("tool_input") or {}).get("command", ""))
except Exception:
    pass
' 2>/dev/null || true)"
case "$command_text" in *"git commit"*) ;; *) exit 0 ;; esac

command -v roborev >/dev/null 2>&1 || exit 0
git_dir="$(git rev-parse --git-dir 2>/dev/null)" || exit 0
head_sha="$(git rev-parse HEAD 2>/dev/null)" || exit 0
state="$git_dir/roborev-codex-gate-last-sha"
[ "$(cat "$state" 2>/dev/null || true)" = "$head_sha" ] && exit 0

if roborev wait -q "$head_sha" >/dev/null 2>&1; then
  show="$(roborev show "$head_sha" 2>/dev/null || true)"
  first="$(printf '%s\n' "$show" | head -1)"
  if [ -n "$show" ] && ! printf '%s\n' "$first" | grep -qiE '^error:|no review found'; then
    printf '%s' "$head_sha" > "$state"
    exit 0
  fi
fi

review="$(roborev show "$head_sha" 2>/dev/null || true)"
first="$(printf '%s\n' "$review" | head -1)"
if [ -z "$review" ] || printf '%s\n' "$first" | grep -qiE '^error:|no review found'; then
  exit 0
fi

printf '%s' "$head_sha" > "$state"
cat >&2 <<MSG
RoboRev returned a FAIL for $head_sha. Handle the finding, then before the next
commit run: roborev respond <job> -m '<what you did and why>' && roborev close <job>.
A fix commit does not close the review. Leave no ambiguous open review. Max two
finding/fix rounds before escalation.

$review
MSG
exit 2
