#!/usr/bin/env bash
# Diet re-injection after a PostCompact marker: identity note, house rules,
# the active contract, the ledger tail, and POINTERS to the law files — not
# the law files themselves (the v1 whole-file payload spent most of the fresh
# window re-pasting stable on-disk text). Fail-open.
set -uo pipefail

HANDOFF_GUARD=0
LEDGER_TAIL_LINES=80          # how much of progress.md rides along
REGROUND_BUDGET_BYTES=49152   # stated diet budget for a realistic payload

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
[ -d "$core" ] || core="$root/skills/cbr-core"
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

note="Context was compacted. Re-grounding: the house rules, the active contract, and the ledger tail are below, whole; the law files are POINTED AT, not pasted — re-read the relevant one from disk before any contract-shaped decision (review cadence, merge gate, scope, TDD sequencing). You have ALREADY booted and the control plane is ALREADY armed: do not rerun boot, arm, doctor, or a file-reading orientation ritual merely because compaction occurred. Continue the active plan from its current phase; the write-time and commit-time gates fire regardless of what you remember."
if [ "${HANDOFF_GUARD:-0}" = "1" ]; then
  note="$note Do not switch to a newest handoff from a prior session; the active plan supersedes it for this run."
fi

inject() {
  [ -f "$2" ] || return 0
  note="$note

=== $1 ===
$(cat "$2")"
}

# House rules: the SHORT binding docs, whole. reinjectionDocs (when set) is
# the port's own short list; the default is constitution + routing map only.
if [ -f "$config" ] && jq -e '.reinjectionDocs' "$config" >/dev/null 2>&1; then
  while IFS= read -r doc; do
    [ -n "$doc" ] && inject "$doc (house rules — binding, injected whole)" "$root/$doc"
  done < <(jq -r '.reinjectionDocs[]? // empty' "$config" 2>/dev/null)
else
  for doc in CONSTITUTION.md AGENTS.md; do
    inject "$doc (house rules — binding, injected whole)" "$root/$doc"
  done
fi

pointers=""
add_ptr() { # $1 = absolute path, $2 = one-line why
  [ -f "$1" ] && pointers="$pointers
- ${1#$root/} — $2"
  return 0
}
add_ptr "$root/ENGINEERING.md" "binding principles"
add_ptr "$root/VISION.md" "binding principles"
add_ptr "$skill" "the build process router"

role=""
if [ -f "$plan" ]; then
  role="$(sed -nE 's/.*\*\*Run type:\*\*[[:space:]]*(orchestrator|workstream).*/\1/p' "$plan" | head -1)"
  add_ptr "$core/policy.md" "control-plane law"
  add_ptr "$core/strand.md" "strand law"
  add_ptr "$core/reviews.md" "review cadence law"
  add_ptr "$core/judgment.md" "decision routing"
  add_ptr "$core/GLOSSARY.md" "the control plane's exact vocabulary"
  case "$role" in
    orchestrator)
      add_ptr "$core/modes/fleet.md" "fleet mode (role-specific)"
      add_ptr "$refs/fleet.md" "provider fleet mechanisms"
      ;;
    *)
      add_ptr "$core/build-loop.md" "build loop (role-specific)"
      branch="$(git -C "$root" branch --show-current 2>/dev/null || true)"
      builder_pattern='^stream/'
      [ -f "$config" ] && builder_pattern="$(jq -r '.builderBranchPattern // "^stream/"' "$config" 2>/dev/null || printf '^stream/')"
      # solo merge law never reaches a fleet builder's branch
      if ! [[ "$branch" =~ $builder_pattern ]]; then
        add_ptr "$core/modes/solo.md" "solo mode (role-specific)"
      fi
      add_ptr "$refs/build-loop.md" "provider workstream mechanisms"
      ;;
  esac
  add_ptr "$complexity" "the complexity ceiling (deterministic commit gate)"
  inject "ACTIVE CONTRACT ($plan_rel) — an autonomous build is in progress; re-read this and continue from the current phase" "$plan"
  inject "DURABLE FINDINGS ($(dirname "$plan_rel")/findings.md)" "$plan_dir/findings.md"
  [ -f "$plan_dir/progress.md" ] && note="$note

=== LEDGER TAIL ($(dirname "$plan_rel")/progress.md, last $LEDGER_TAIL_LINES lines — exactly where you left off) ===
$(tail -n "$LEDGER_TAIL_LINES" "$plan_dir/progress.md")"
fi

[ -n "$pointers" ] && note="$note

=== LAW FILE POINTERS (re-read from disk before contract-shaped decisions; deliberately not pasted) ===$pointers"

# payload via STDIN, never as an argument — an oversized findings.md must not
# hit the OS per-argument limit and kill the one lifeline this hook is
printf '%s' "$note" | jq -Rs --arg event "$event" \
  '{hookSpecificOutput: {hookEventName: $event, additionalContext: .}}' || exit 0
rm -f "$marker"
exit 0
