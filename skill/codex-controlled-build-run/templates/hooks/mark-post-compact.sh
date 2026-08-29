#!/usr/bin/env bash
# PostCompact cannot emit additionalContext. Leave a worktree-scoped marker
# for the next context-bearing UserPromptSubmit or SessionStart(resume) hook.
set -uo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
input="$(cat 2>/dev/null || true)"
thread="$(printf '%s' "$input" | jq -r '.session_id // .thread_id // .conversation_id // .sessionId // .threadId // .conversationId // empty' 2>/dev/null || true)"
[ -n "$thread" ] || thread="${CODEX_THREAD_ID:-}"
case "$thread" in ""|*[!A-Za-z0-9_-]*) exit 0;; esac
marker="$(git -C "$root" rev-parse --git-path "cbr-codex-post-compact.$thread.pending" 2>/dev/null)" || exit 0
case "$marker" in /*) ;; *) marker="$root/$marker";; esac
mkdir -p "$(dirname "$marker")" || exit 0
printf '%s\n' "$thread" >"$marker"
exit 0
