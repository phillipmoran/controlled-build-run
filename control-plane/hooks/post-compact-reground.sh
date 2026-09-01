#!/usr/bin/env bash
# post-compact-reground.sh — PORTABLE TEMPLATE (controlled-build-run-kit).
#
# After a context compaction, re-inject the DIET payload: an identity note,
# the short house-rules docs, the active contract (task_plan.md), the ledger
# tail (findings + recent progress), and POINTERS to the law files — not the
# law files themselves. A compaction summarizes the conversation, which
# fuzzes what the agent was DOING; the contract and ledger are what restore
# that. The law files are stable on disk and cheap to re-read on demand, so
# pasting them whole (the v1 behavior, ~163KB per compaction) bought little
# and cost most of the fresh window. Fails open: any trouble exits silent.
#
# The payload budget is REGROUND_BUDGET_BYTES; kit/verify/reground-gate.test.sh
# holds a realistically-sized fixture under it. Wire as a SessionStart hook
# with matcher "compact" (NOT a PostCompact hook — PostCompact is log-only
# and cannot inject context).
#
# ============================ PORTING — EDIT THESE ============================
# Short, binding "house rules" docs, injected whole (keep this list SMALL):
HOUSE_DOCS=("CONSTITUTION.md" "AGENTS.md")
# Law files listed as re-read pointers (leave any empty to skip it):
PRINCIPLE_POINTERS=("ENGINEERING.md" "VISION.md")
SKILL_REL="skills/claude-controlled-build-run/SKILL.md"      # where THIS kit's skill landed in the repo
TDD_REL="skills/test-driven-development/SKILL.md"      # the TDD skill (pointer, mid-build only)
COMPLEXITY_REL="skills/cyclomatic-complexity/SKILL.md"  # the complexity skill (pointer, mid-build only)
LEDGER_TAIL_LINES=80          # how much of progress.md rides along
REGROUND_BUDGET_BYTES=49152   # stated diet budget for a realistic payload
# Set HANDOFF_GUARD=1 only if your repo's boot ritual reads a "newest handoff"
# that a re-grounded mid-run agent would otherwise get pulled back onto.
HANDOFF_GUARD=0
# =============================================================================

set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0

skill="$root/$SKILL_REL"
refs="$(dirname "$skill")/references"; core="$refs/core"
[ -d "$core" ] || core="$root/skills/cbr-core"
plan="$root/task_plan.md"; findings="$root/findings.md"; prog="$root/progress.md"

note="Context was just compacted. Re-grounding: the house rules, the active contract, and the ledger tail are below, whole; the law files are POINTED AT, not pasted — re-read the relevant one from disk before any contract-shaped decision (review cadence, merge gate, scope, TDD sequencing). You have ALREADY booted AND already set up the control plane: do NOT re-run the boot ritual, and do NOT re-verify or re-wire the control plane (the hooks, Probity, RoboRev, pre-commit) — both were done before this compaction and are still active. If a contract is shown below, it is your current source of truth — continue from its current phase. The write-time and commit-time gates (TDD, complexity, merge wall) are hooks and fire regardless of what you remember."

if [ "${HANDOFF_GUARD:-0}" = "1" ]; then
  note="$note Do NOT go read the newest handoff and switch to its priorities (that handoff is from a prior session; the plan supersedes it for this run)."
fi

inject() {  # $1 = section label, $2 = absolute path
  [ -f "$2" ] && note="$note

=== $1 ===
$(cat "$2")"
  return 0
}

for d in ${HOUSE_DOCS[@]+"${HOUSE_DOCS[@]}"}; do
  [ -n "$d" ] && inject "$d (house rules — binding, injected whole)" "$root/$d"
done

pointers=""
add_ptr() { # $1 = repo-relative path, $2 = one-line why
  [ -f "$root/$1" ] && pointers="$pointers
- $1 — $2"
  return 0
}
for d in ${PRINCIPLE_POINTERS[@]+"${PRINCIPLE_POINTERS[@]}"}; do
  [ -n "$d" ] && add_ptr "$d" "binding principles"
done
add_ptr "$SKILL_REL" "the build process router"

# The contract, ledger, and law pointers are conditional — they only matter
# when this session is itself running a build (a plan is present).
if [ -f "$plan" ]; then
  # Role from the plan's **Run type:** line; workstream when absent/unknown.
  role="$(sed -nE 's/.*\*\*Run type:\*\*[[:space:]]*(orchestrator|workstream).*/\1/p' "$plan" | head -1)"
  [ "$role" = "orchestrator" ] || role="workstream"

  core_rel="${core#$root/}"
  add_ptr "$core_rel/policy.md" "control-plane law"
  add_ptr "$core_rel/strand.md" "strand law"
  add_ptr "$core_rel/reviews.md" "review cadence law"
  add_ptr "$core_rel/judgment.md" "decision routing"
  add_ptr "$core_rel/GLOSSARY.md" "the control plane's exact vocabulary"
  if [ "$role" = "orchestrator" ]; then
    add_ptr "$core_rel/modes/fleet.md" "fleet mode (role-specific)"
  else
    add_ptr "$core_rel/build-loop.md" "build loop (role-specific)"
    # solo merge law never reaches a fleet builder's branch (stream/*)
    branch="$(git branch --show-current 2>/dev/null || true)"
    case "$branch" in
      stream/*) ;;
      *) add_ptr "$core_rel/modes/solo.md" "solo mode (role-specific)" ;;
    esac
  fi
  add_ptr "${refs#$root/}/claude.md" "provider mechanisms behind the law"
  add_ptr "$TDD_REL" "the TDD iron law (Probity enforces it at write time)"
  add_ptr "$COMPLEXITY_REL" "the complexity ceiling (deterministic commit gate)"

  inject "ACTIVE CONTRACT (task_plan.md) — an autonomous build is in progress; re-read this and continue from the current phase" "$plan"
  inject "DURABLE FINDINGS (findings.md)" "$findings"
  [ -f "$prog" ] && note="$note

=== LEDGER TAIL (progress.md, last $LEDGER_TAIL_LINES lines — exactly where you left off) ===
$(tail -n "$LEDGER_TAIL_LINES" "$prog")"
fi

[ -n "$pointers" ] && note="$note

=== LAW FILE POINTERS (re-read from disk before contract-shaped decisions; deliberately not pasted) ===$pointers"

# The payload goes to jq via STDIN (-Rs), never as an argument — a composed
# note with the contract can exceed the OS per-argument limit, and a hook that
# dies there emits no re-ground at all (the one failure this lifeline can't have).
printf '%s' "$note" | jq -Rs \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: .}}'
exit 0
