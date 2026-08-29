#!/usr/bin/env bash
# Whole, role-aware reinjection after a PostCompact marker. Fail-open.
set -uo pipefail

HANDOFF_GUARD=0

command -v jq >/dev/null 2>&1 || exit 0
root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
input="$(cat 2>/dev/null || true)"
thread="$(printf '%s' "$input" | jq -r '.session_id // .thread_id // .conversation_id // .sessionId // .threadId // .conversationId // empty' 2>/dev/null || true)"
[ -n "$thread" ] || thread="${CODEX_THREAD_ID:-}"
case "$thread" in ""|*[!A-Za-z0-9_-]*) exit 0;; esac
marker="$(git -C "$root" rev-parse --git-path "cbr-codex-post-compact.$thread.pending" 2>/dev/null)" || exit 0
case "$marker" in /*) ;; *) marker="$root/$marker";; esac
[ -f "$marker" ] || exit 0
event="${CBR_REGROUND_EVENT:-}"
case "$event" in UserPromptSubmit|SessionStart) ;; *) exit 0;; esac
skill="$root/.agents/skills/codex-controlled-build-run/SKILL.md"
[ -f "$skill" ] || skill="$root/skills/codex-controlled-build-run/SKILL.md"
refs="$(dirname "$skill")/references"
core="$refs/cbr-core"
# Sibling teaching skills, resolved the same two ways the leaf skill is: an
# installed copy first, then a repository source copy. Injected mid-build only.
complexity="$root/.agents/skills/cyclomatic-complexity/SKILL.md"
[ -f "$complexity" ] || complexity="$root/skills/cyclomatic-complexity/SKILL.md"
config="$root/.cbr-codex.json"
plan_rel="task_plan.md"
[ -f "$config" ] && plan_rel="$(jq -r '.activePlanPath // "task_plan.md"' "$config" 2>/dev/null || printf task_plan.md)"
case "$plan_rel" in /*|../*|*/../*) exit 0;; esac
plan="$root/$plan_rel"
plan_dir="$(dirname "$plan")"

note="Context was compacted. The controlled build is being re-grounded automatically from durable files. You have ALREADY booted and the harness is ALREADY armed: do not rerun boot, arm, doctor, or a file-reading orientation ritual merely because compaction occurred. Continue the active plan from its current phase using the complete injected material below."
if [ "${HANDOFF_GUARD:-0}" = "1" ]; then
  note="$note Do not switch to a newest handoff from a prior session; the active plan supersedes it for this run."
fi

inject() {
  [ -f "$2" ] || return 0
  note="$note

=== $1 ===
$(cat "$2")"
}

if [ -f "$config" ]; then
  while IFS= read -r doc; do
    [ -n "$doc" ] && inject "$doc" "$root/$doc"
  done < <(jq -r '.reinjectionDocs[]? // empty' "$config" 2>/dev/null)
else
  for doc in CONSTITUTION.md ENGINEERING.md VISION.md AGENTS.md; do
    inject "$doc" "$root/$doc"
  done
fi
[ -f "$skill" ] && inject "codex-controlled-build-run SKILL.md" "$skill"

role=""
if [ -f "$plan" ]; then
  role="$(sed -nE 's/.*\*\*Run type:\*\*[[:space:]]*(orchestrator|workstream).*/\1/p' "$plan" | head -1)"
  inject "CBR core policy" "$core/policy.md"
  inject "CBR core strand" "$core/strand.md"
  inject "CBR core reviews" "$core/reviews.md"
  inject "CBR core judgment" "$core/judgment.md"
  inject "CBR core glossary (the harness's own words — use them exactly)" "$core/GLOSSARY.md"
  case "$role" in
    orchestrator)
      inject "CBR core fleet mode (role-specific)" "$core/modes/fleet.md"
      inject "Codex fleet mechanisms (role-specific)" "$refs/fleet.md"
      ;;
    workstream)
      inject "CBR core build loop (role-specific)" "$core/build-loop.md"
      branch="$(git -C "$root" branch --show-current 2>/dev/null || true)"
      builder_pattern='^stream/'
      [ -f "$config" ] && builder_pattern="$(jq -r '.builderBranchPattern // "^stream/"' "$config" 2>/dev/null || printf '^stream/')"
      if ! [[ "$branch" =~ $builder_pattern ]]; then
        inject "CBR core solo mode (role-specific)" "$core/modes/solo.md"
      fi
      inject "Codex workstream mechanisms (role-specific)" "$refs/build-loop.md"
      ;;
  esac
  inject "cyclomatic-complexity SKILL.md (the complexity ceiling is a DETERMINISTIC pre-commit gate — it stops the commit rather than advising you. Over the bar you have exactly two moves, each ending the block in one step: refactor under it, or exempt with a one-line reason.)" "$complexity"
  inject "ACTIVE PLAN ($plan_rel)" "$plan"
  inject "DURABLE FINDINGS ($(dirname "$plan_rel")/findings.md)" "$plan_dir/findings.md"
  inject "SESSION PROGRESS ($(dirname "$plan_rel")/progress.md)" "$plan_dir/progress.md"
fi

jq -n --arg ctx "$note" --arg event "$event" \
  '{hookSpecificOutput: {hookEventName: $event, additionalContext: $ctx}}' || exit 0
rm -f "$marker"
exit 0
