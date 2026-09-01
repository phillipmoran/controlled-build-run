---
name: cbr-build
description: >-
  Execute the current plan under the CBR loop. Use when a ratified task_plan.md
  exists and the work should proceed under the gates: TDD sequencing, review
  cadence, phase-by-phase records. Decides solo vs fleet from the plan itself.
---

# cbr-build — execute under the loop

Precondition: an armed repo (`/cbr-doctor` if unsure) and a fresh, ratified
`task_plan.md` (`/cbr` router's freshness tells; `/cbr-plan` if there is no
plan). Do not build past a missing precondition — that is the exact failure
mode this control plane exists to stop.

## Solo or fleet — the plan decides

Read the plan's shape, not its word count:

- **Solo** (this session builds): a single strand — one branch, phases that
  depend on each other in order.
- **Fleet** (orchestrate builders): the plan names independent strands that
  can proceed in parallel worktrees. Then this session is the orchestrator
  and the fleet law in the package core
  (`.../references/core/modes/fleet.md`) governs: one strand per
  branch↔plan↔worktree↔session, watchers on terminal markers, stop-before-
  DONE enforced per builder.

## The loop

The build law lives in the vendored package — read
`controlled-build-run/skill/claude-controlled-build-run/SKILL.md` before the
first edit and follow it, not memory. What the loop looks like from the
operator's chair:

- Work one phase at a time, in plan order.
- TDD where the law requires it: watch the test fail before making it pass.
- Check a box only after the phase's verification actually ran — the
  deterministic gates (Probity, pre-commit, the stop gate) will catch some
  lies, but the record's honesty is yours.
- Reviews arrive on the cadence the repo configured (advisory per-commit,
  gate at the merge boundary). Read findings when they land; fix now only
  if a later commit would compound the problem.
- Finish through the closeout the law defines — plan archived, branch
  merged or parked with a reason — never by just stopping. The stop gate
  will refuse an unfinished silent exit anyway; work with it, not around it.
