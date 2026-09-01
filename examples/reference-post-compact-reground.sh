#!/usr/bin/env bash
# After a context compaction, re-inject the reference host's grounding docs into context.
# A compaction summarizes the conversation, which fuzzes the verbatim rules the
# agent read at boot — so over a long run the agent drifts from the precise
# principles. CONSTITUTION and ENGINEERING are short and ARE the principles, and
# AGENTS.md is the routing/mental-model doc; re-injecting all three whole is
# cheap and keeps them verbatim exactly when drift spikes (right after a
# compaction). GLOSSARY's short vocabulary is injected too — its acronyms
# (MAD/RAD/RNG/EP/MP/HP) and core terms are exactly what drifting work touches,
# and it is tiny. Contracts are pointed at, not injected. Fails open: any
# trouble exits silent.
#
# It ALSO re-injects the active planning-with-files plan (task_plan.md) whole
# when one exists, and points at progress.md. A compaction is exactly when an
# autonomous build run loses track of which phase it is on; the grounding docs
# keep the agent honest, the plan keeps it on-task. The plan is pasted (not just
# pointed at) because it is the volatile working memory most likely to be lost.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
con="$root/CONSTITUTION.md"
eng="$root/ENGINEERING.md"
agents="$root/AGENTS.md"
glo="$root/GLOSSARY.md"
skill="$root/skills/controlled-build-run/SKILL.md"
tdd="$root/skills/test-driven-development/SKILL.md"
[ -f "$con" ] && [ -f "$eng" ] || exit 0

note="Context was just compacted. Re-grounding to the reference host's core docs and the build skill below (and, if a build is in progress, the TDD skill and the active plan) — a summary fuzzes the verbatim rules, so here they are again, whole. You have ALREADY booted AND already set up the control plane: do NOT re-run AGENTS.md's boot ritual, and do NOT re-verify or re-wire the control plane (the hooks, Probity, RoboRev, pre-commit) — both were done before this compaction and are still active. If a plan is shown below, it is your current source of truth — continue from its current phase, and do NOT go read the newest handoff and switch to its priorities (that handoff is from a prior session; the plan supersedes it for this run). Before any contract-shaped decision, also re-read the relevant file(s) under contracts/ (those are pointed at, not pasted here).

=== CONSTITUTION.md ===
$(cat "$con")

=== ENGINEERING.md ===
$(cat "$eng")"

if [ -f "$glo" ]; then
  note="$note

=== GLOSSARY.md (the reference host's canonical vocabulary — acronyms like MAD/RAD/RNG/EP/MP/HP and core terms; injected whole so they stay exact when drift spikes) ===
$(cat "$glo")"
fi

if [ -f "$agents" ]; then
  note="$note

=== AGENTS.md (top-level — the routing aid and mental model) ===
$(cat "$agents")"
fi

# The build skill is pasted UNCONDITIONALLY: a builder session needs its loop, and an
# orchestrator session (no plan at root) needs the same file for its monitoring checklist,
# dispatch rules, and merge-gate duties (operator-ratified 2026-06-11). The TDD skill and the plan
# stay conditional — they only matter when this session is itself building.
[ -f "$skill" ] && note="$note

=== controlled-build-run SKILL.md (the build process — re-grounded whole so the loop survives the compaction. Building off a plan: continue its phases; do NOT re-run Phase 1 control-plane setup. Orchestrating dispatched builders: this skill's dispatch, monitoring, surfacing-cadence, and merge-gate rules bind you) ===
$(cat "$skill")"

plan="$root/task_plan.md"
prog="$root/progress.md"
if [ -f "$plan" ]; then
  [ -f "$tdd" ] && note="$note

=== test-driven-development SKILL.md (this build is TDD — every stage is watched-fail test FIRST, then code, then green; re-grounded whole so the iron law stays verbatim across the compaction. Load the companion skills/test-driven-development/testing-anti-patterns.md on demand when shaping a fake or mock. NOTE: Probity's enforceTdd reads only the LIVE transcript, so a refactor resumed past this compaction can be falsely blocked — re-establish a green baseline in-session to unblock; never weaken the gate.) ===
$(cat "$tdd")"
  note="$note

=== ACTIVE PLAN (task_plan.md) — an autonomous build is in progress; re-read this and continue from the current phase ===
$(cat "$plan")"
  [ -f "$prog" ] && note="$note

(Also re-read progress.md at the repo root for the session log and exactly where you left off.)"
fi

jq -n --arg ctx "$note" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
exit 0
