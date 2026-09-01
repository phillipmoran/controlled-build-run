---
name: cbr-plan
description: >-
  Compile a plan into a gated CBR contract. Use when work needs a task_plan.md:
  after a design discussion, from a PRD or Wayfinder output, or when the cbr
  router found no plan. Compiles what exists — does not re-derive it.
---

# cbr-plan — compile, don't re-derive

A CBR plan is a compilation target, not an authoring format. If planning
already happened — a design conversation in this session, a Wayfinder run, a
PRD, an issue thread — your job is to compile that material into the contract
shape. Re-deriving the plan from scratch discards decisions the operator
already made.

## The contract shape

Follow the plan law in the vendored package
(`controlled-build-run/skill/claude-controlled-build-run/SKILL.md` and its
plan references). The non-negotiables:

- `task_plan.md` at the worktree root, with `**Run type:**` and
  `**Branch:**` header lines.
- A goal the operator ratified, stated in one paragraph.
- Phases as checkboxes, each independently verifiable, each small enough
  that a checked box means something. All boxes start `[ ]` — a checkbox
  that leads the code lies about state.
- Zero-context legibility: a fresh session reading only this file knows
  what to do next. Names, paths, and commands spelled out; no pointers into
  a conversation that will be gone.
- Decisions the operator ratified go in a locked-decisions section, so a
  later session cannot relitigate them by accident.

## Altitude

Plan at the altitude of verifiable outcomes, not keystrokes. "P2 — parser
rejects malformed headers (test: `test/parse.test.ts`)" is a phase;
"P2 — edit parse.ts" is not.

## Handoff

Show the operator the compiled plan and get a yes before committing it.
Then commit it to the strand's branch — an uncommitted plan is invisible to
every gate and watcher CBR runs. Building starts through `/cbr-build`, not
here.
