#!/usr/bin/env bash
set -uo pipefail

branch="$(git branch --show-current 2>/dev/null || true)"
case "$branch" in
  stream/*)
    cat >&2 <<'MSG'
BLOCKED: interactive questions are disabled for a headless stream/* Codex builder.
Write ASK-ORCH.md at the worktree root with the question, phase, BLOCKING or
PROCEEDING-ON-DEFAULT, and the proposed default. Add it to the plan's Open with
human section, then keep working on independent work. The orchestrator answers
through ORCH-ANSWER.md and the decision log.
MSG
    exit 2
    ;;
esac
exit 0
