#!/usr/bin/env bash
# PreToolUse guard (matcher: AskUserQuestion). A builder runs headless as a
# `claude --bg` session: an interactive AskUserQuestion prompt has no human
# watching it and FREEZES the session (a builder once sat ~16 min on one, and
# the orchestrator cannot answer an app-modal dialog from outside). Deny it on
# builder branches only, using the same stream/* signal as the push firewall;
# the orchestrator (integration/*) and any normal checkout are untouched.
branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
case "$branch" in
  stream/*)
    cat >&2 <<'MSG'
BLOCKED: AskUserQuestion is disabled on builder (stream/*) branches — as a headless
--bg session you would FREEZE on it (no human is watching your prompt, and the
orchestrator cannot answer an app-modal dialog). Do NOT ask interactively. Instead:
  1. Append the question + your proposed default to your plan's "## Open with the operator".
  2. Drop ASK-ORCH.md at your worktree root stating: the question, which phase it
     touches, BLOCKING or PROCEEDING-ON-DEFAULT, and the default you will assume if
     it goes unanswered.
  3. Keep building everything else (or proceed on that default) — do not stop.
The orchestrator polls ASK-ORCH.md every watch tick and answers back via ORCH-ANSWER.md
at your worktree root plus your plan's decision log. This is the builder->orchestrator
question channel; use it instead of an interactive prompt.
MSG
    exit 2 ;;
  *)
    exit 0 ;;
esac
