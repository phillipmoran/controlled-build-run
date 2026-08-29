#!/usr/bin/env bash
# post-compact-reground.sh — PORTABLE TEMPLATE (controlled-build-run-kit).
#
# After a context compaction, re-inject this repo's grounding docs + the build
# skill + the CBR core law files (role-aware) + (if a build is running) the TDD
# and cyclomatic-complexity skills and the active plan trio, WHOLE, into
# context. A compaction summarizes
# the conversation, which fuzzes the verbatim rules the agent read at boot; over
# a long run the agent drifts. This hook is the lifeline that re-grounds it.
# Fails open: any trouble exits silent.
#
# The payload is COMPOSED from the leaf's references/ tree: core law files by
# role (workstream vs orchestrator, read from the plan's **Run type:** line),
# plus the provider adapter (references/claude.md). Files that do not exist yet
# are skipped, so the hook is safe both before and after the SKILL.md slimming.
# Wire it as a SessionStart hook with matcher "compact" (NOT a PostCompact
# hook — PostCompact is log-only and cannot inject context).
#
# ============================ PORTING — EDIT THESE ============================
# Point these at YOUR repo's binding docs (leave any empty to skip it):
PRINCIPLE_DOCS=("CONSTITUTION.md" "ENGINEERING.md" "VISION.md")         # short "how we build" docs, injected whole
VOCAB_DOC=""                                          # canonical vocabulary (optional)
ROUTING_DOC="AGENTS.md"                               # top-level routing / mental-model doc
SKILL_REL="skills/claude-controlled-build-run/SKILL.md"      # where THIS kit's skill landed in the repo
TDD_REL="skills/test-driven-development/SKILL.md"      # the TDD skill (injected only mid-build)
COMPLEXITY_REL="skills/cyclomatic-complexity/SKILL.md"  # the complexity skill (injected only mid-build)
# Set HANDOFF_GUARD=1 only if your repo's boot ritual reads a "newest handoff"
# that the injected routing doc would otherwise pull a mid-run agent back onto.
HANDOFF_GUARD=0
# =============================================================================

set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0

skill="$root/$SKILL_REL"; tdd="$root/$TDD_REL"; complexity="$root/$COMPLEXITY_REL"
refs="$(dirname "$skill")/references"; core="$refs/core"
plan="$root/task_plan.md"; findings="$root/findings.md"; prog="$root/progress.md"

note="Context was just compacted. Re-grounding to this repo's core docs, the build skill, and the CBR core law files below (and, if a build is in progress, the TDD and complexity skills and the active plan trio) — a summary fuzzes the verbatim rules, so here they are again, whole. You have ALREADY booted AND already set up the harness: do NOT re-run the boot ritual, and do NOT re-verify or re-wire the harness (the hooks, Probity, RoboRev, pre-commit) — both were done before this compaction and are still active. If a plan is shown below, it is your current source of truth — continue from its current phase."

if [ "${HANDOFF_GUARD:-0}" = "1" ]; then
  note="$note Do NOT go read the newest handoff and switch to its priorities (that handoff is from a prior session; the plan supersedes it for this run). Before any contract-shaped decision, re-read the relevant binding file(s) (those are pointed at, not pasted here)."
fi

inject() {  # $1 = section label, $2 = absolute path
  [ -f "$2" ] && note="$note

=== $1 ===
$(cat "$2")"
  return 0
}

# bash 3.2 (macOS /bin/bash) errors on "${arr[@]}" when the array is empty under
# `set -u`; ${arr[@]+...} expands to nothing in that case instead of tripping.
for d in ${PRINCIPLE_DOCS[@]+"${PRINCIPLE_DOCS[@]}"}; do [ -n "$d" ] && inject "$d" "$root/$d"; done
[ -n "${VOCAB_DOC:-}" ]   && inject "$VOCAB_DOC (canonical vocabulary — injected whole so terms stay exact when drift spikes)" "$root/$VOCAB_DOC"
[ -n "${ROUTING_DOC:-}" ] && inject "$ROUTING_DOC (top-level — the routing aid and mental model)" "$root/$ROUTING_DOC"

# The build skill is pasted UNCONDITIONALLY: a builder session needs its loop, and
# an orchestrator session needs the same file for its monitoring, dispatch, and
# merge-gate rules. (Post-slimming this is the router; the law detail rides in
# the composed core sections below.)
[ -f "$skill" ] && note="$note

=== claude-controlled-build-run SKILL.md (the build process — re-grounded whole so the loop survives the compaction; do NOT re-run its harness setup) ===
$(cat "$skill")"

# The core law files + adapter + TDD/complexity skills + plan trio are conditional — they
# only matter when this session is itself running a build (a plan is present).
if [ -f "$plan" ]; then
  # Role from the plan's **Run type:** line; workstream when absent/unknown.
  role="$(sed -nE 's/.*\*\*Run type:\*\*[[:space:]]*(orchestrator|workstream).*/\1/p' "$plan" | head -1)"
  [ "$role" = "orchestrator" ] || role="workstream"

  inject "CBR core policy" "$core/policy.md"
  inject "CBR core strand" "$core/strand.md"
  inject "CBR core reviews" "$core/reviews.md"
  inject "CBR core judgment" "$core/judgment.md"
  inject "CBR core glossary (the harness's own words — use them exactly)" "$core/GLOSSARY.md"
  if [ "$role" = "orchestrator" ]; then
    inject "CBR core fleet mode (role-specific)" "$core/modes/fleet.md"
    inject "CBR core captain mode (role-specific)" "$core/modes/captain.md"
  else
    inject "CBR core build loop (role-specific)" "$core/build-loop.md"
    inject "CBR core solo mode (role-specific)" "$core/modes/solo.md"
  fi
  inject "Claude leaf mechanisms (references/claude.md)" "$refs/claude.md"

  [ -f "$tdd" ] && note="$note

=== test-driven-development SKILL.md (this build is TDD — every stage is watched-fail test FIRST, then code, then green; re-grounded whole so the iron law stays verbatim. NOTE: Probity's enforceTdd reads only the LIVE transcript, so a refactor resumed past this compaction can be falsely blocked — re-establish a green baseline in-session to unblock; never weaken the gate.) ===
$(cat "$tdd")"
  [ -f "$complexity" ] && note="$note

=== cyclomatic-complexity SKILL.md (the complexity ceiling is a DETERMINISTIC pre-commit gate, so it stops the commit rather than advising you; re-grounded whole, like the TDD skill, because the gate fires at commit time and that is the worst moment to first meet the rule. Over the bar you have exactly two moves, each ending the block in one step — refactor under it, or exempt with a one-line reason.) ===
$(cat "$complexity")"
  inject "ACTIVE PLAN (task_plan.md) — an autonomous build is in progress; re-read this and continue from the current phase" "$plan"
  inject "DURABLE FINDINGS (findings.md)" "$findings"
  inject "SESSION PROGRESS (progress.md — the session log; exactly where you left off)" "$prog"
fi

# The payload goes to jq via STDIN (-Rs), never as an argument — a composed
# note with the plan trio can exceed the OS per-argument limit, and a hook that
# dies there emits no re-ground at all (the one failure this lifeline can't have).
printf '%s' "$note" | jq -Rs \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: .}}'
exit 0
