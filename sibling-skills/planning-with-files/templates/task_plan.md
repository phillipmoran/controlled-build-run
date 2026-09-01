# [Name] — contract
<!--
  WHAT: The plan is a CONTRACT, not a script — it fixes decisions and the
  acceptance bar, and leaves implementation to the build loop.
  WHY: After 50+ tool calls (or a compaction), this file IS your memory.
  WHEN: Create FIRST. Update the ledger and decision log as you go.
-->

**Run type:** workstream
<!--
  This template shapes a WORKSTREAM (one builder, one strand). An
  orchestrator run carries the full fleet lifecycle — dependency/collision
  graph, merged-build smoke, cleanup — which this skeleton does not:
  write fleet plans to the contract in skills/cbr-core/modes/fleet.md.
-->
**Branch:** [branch]
<!-- Confirm the live branch matches this line at every session start. -->

## Goal
<!-- One paragraph: what EXISTS when this is done, stated observably. -->
[What exists when this is done]

## Invariants
<!--
  WHAT: Rules that must stay true for the whole run — the "don't break
  these" list (contracts, gates, conventions this work must respect).
  WHY: A reviewer cites these by name; a builder checks against them.
-->
- [Invariant]

## Out of scope
<!--
  WHAT: What this plan deliberately does NOT touch.
  WHY: The cheapest way to kill scope drift and review re-litigation.
-->
- [Not this]

## Locked decisions
<!--
  WHAT: Settled calls, each with a one-line why.
  WHY: Reviews may engage the recorded reasoning — never reopen a locked
  decision by restating it. Findings may not edit this section.
-->
| Decision | Why |
|----------|-----|
|          |     |

## PRs
<!--
  SIZING RULE: one PR = one behavior, ~≤400 lines of product diff, green,
  revertable. A step too big to fit gets split HERE, at planning time —
  not discovered mid-build. Every PR carries the five plan-altitude fields
  (strand.md): outcome, watched-fail test, locked decisions, owned files,
  verification command — then stops.
-->
- [ ] P1 — [one behavior]
  - outcome: [what is observable when this lands]
  - watched-fail: [the test written first, seen red]
  - locked: [decisions already made for this step, or "see Locked decisions"]
  - owns: [files/dirs this PR may touch — collision boundary]
  - verify: `[command]`

## PR ledger
<!--
  WHAT: One row per finished PR: where it ended, what reviewed it, how
  every finding was dispositioned.
  WHY: The audit trail the merge gate and the human read. The gate's
  checkpoint check requires columns 2 and 3 to hold the SAME sha once a
  PR completes: `reviewed` is the end sha again, written only after the
  checkpoint review ran at that tip. Review jobs and finding outcomes go
  in `disposition`.
-->
| PR | end sha | reviewed | disposition |
|----|---------|----------|-------------|
| P1 | pending | pending  |             |

## Acceptance
<!--
  WHAT: The exact commands that prove the whole contract is done.
  WHY: "Done" is a command output, not a feeling.
-->
```
[verification command(s)]
```

## Open with the human
<!--
  WHAT: Design forks only the human may resolve. A builder never starts
  on an unresolved fork.
-->
- [Question]

## Decision log (in-flight)
<!--
  WHAT: Rulings made DURING the run — dated, with whys. Includes declined
  review findings with their recorded reasoning.
  WHY: A declined finding without a written why gets re-litigated forever.
-->
| When | Decision | Why |
|------|----------|-----|
|      |          |     |
