# reviews.md — the review layers beyond the per-commit pass

Part of `cbr-core`, the provider-neutral CBR law. Per-commit review (RoboRev)
and its close-discipline live in `build-loop.md`; this file carries the
layers around it: the golden sample, the phase checkpoint, and the
plan-review gate.

## Golden samples — eyeball what a reader will read

When the work produces an artifact a human or an LLM will *read* — a prompt,
a report, a generated document — render a full, realistic sample and
actually look at it. Unit tests check that the structure is present; they do
**not** tell you whether it reads well, leaks an internal id, double-renders,
or drops something that should be there. A throwaway script that builds real
domain objects and prints the output is the cheapest way to catch these (do
not commit the script). When the format is human- or hero-facing, review the
sample *with the human* — format is their call, and a missing requirement
(something that should be in the output but no test demands) is exactly what
eyeballing catches and TDD cannot.

## Checkpoint review — at every phase boundary

When you mark a phase complete, run a scoped consistency review *before
starting the next phase*. This is the layer that catches a contradiction
*across documents* — a contract vs the code vs the roadmap — which
per-commit review structurally cannot see, while the batch is still small
and the context is hot.

**"Phase" here = a `task_plan.md` work unit** — one of the plan's phases you
mark `pending → in_progress → complete` (a build may label these "Stage
1/2/3" instead — same thing; the checkpoint fires per unit either way). It
does **NOT** mean a roadmap-level milestone, which spans many sessions — you
do not checkpoint-review at those. The checkpoint fires every time you
complete one of the plan's build steps.

Mechanics:

- Keep a **phase-checkpoint table** in `task_plan.md`:

  | Phase | end_sha | reviewed |
  |-------|---------|----------|
  | 1 | `a1b2c3d` | `a1b2c3d` ✓ |
  | 2 | `e4f5a6b` | pending |

  When a phase finishes, stamp `end_sha = git rev-parse HEAD`. A phase's
  start is the previous phase's `end_sha`.

- **What to review.** The diff over `<last reviewed sha>..HEAD` — exactly
  this phase's not-yet-reviewed commits (the diff plus the new files). Run
  it as an **independent read-only subagent** (never a self-review — the
  author can't see their own blind spots; model per the leaf's dial). Check
  it against two specs: the phase's **stated goal** in `task_plan.md` and
  the **ratified contract(s)** the diff touches. Anchor it on the success
  behavior, not a role: *the best cross-artifact auditor proves a
  contradiction by quoting both sides, and stays silent when the artifacts
  agree.* Hand it the **contradiction taxonomy** — the cross-document
  failures a single-diff view structurally cannot see:

  1. **Behavior without a rule** — code does something no contract rule
     sanctions.
  2. **Rule without a test** — a contract rule the diff touches gains no
     enforcing test.
  3. **Ratified-text drift** — a ratify-step contract edit's wording
     diverged from what the human ratified.
  4. **Homeless concept** — a new concept with no glossary/contract home, or
     a reserved word reused.
  5. **Second implementation** — the diff re-implements a concept that
     already exists (single-implementation breach).
  6. **Goal miss** — the diff doesn't actually deliver the phase's stated
     goal.

  **Calibration:** most phases are consistent; a clean phase with **zero
  findings is the expected, correct outcome**. Surface a contradiction ONLY
  if you can prove it; never invent work; do not redo the per-commit
  reviewer's line-level bug pass.

  **Output — one block per item, nothing unproven:** `severity`
  (**load-bearing** = a taxonomy contradiction | **minor** =
  wording/style/nit); `label` (**FINDING** = a demonstrable contradiction,
  REQUIRES both sides quoted | **INTERPRETATION** = a judgment call — only
  evidence-backed FINDINGS bind, interpretations advise); `evidence` (for a
  FINDING, quote BOTH artifacts that disagree with `file:line` — the
  contract clause AND the code that violates it; no quotes → it is at most
  an INTERPRETATION); `contradiction` (one line — what disagrees);
  `resolution` (a concrete fix, or **needs-human** for a vision/contract
  call).

- **Dedup:** the review scope is always `<last reviewed sha>..HEAD`. Once
  you stamp `reviewed = HEAD`, those commits are never re-reviewed. If a
  finished phase reopens (more commits land on it), only the new delta gets
  reviewed.

- **Fix load-bearing FINDINGS before starting the next phase.** Minors and
  INTERPRETATIONS are the human's call (or yours, logged in the plan).

## The plan-review gate — review the plan before its builder runs

A plan executed faithfully by a frontier builder is the most expensive
artifact in this flow, so a *bad plan* is the costliest failure — review the
plan, not only the code it later produces (the phase-checkpoint and closeout
reviews are downstream of this; they review built code). Every stream plan
passes this gate BEFORE its builder launches. The gate:

- An **independent read-only subagent** (model per the leaf's dial) checks
  the mechanical criteria — each a deterministic fact, so the gate BLOCKS
  launch on a miss: `**Branch:**` line present and matching; every build
  step test-drivable (no shape-only step Probity will reject — see the
  gotchas in `build-loop.md`); dependency order honest (no step reads a
  field an earlier stream hasn't merged); files-owned declared and free of
  collision with a live stream; for any fog-bound view, the exact
  perceivable fields named with the binding rule cited; any contract edit
  isolated as a ratify step; verification commands present;
  phase-checkpoint table seeded; scope locked; **Probity-exempt zones
  declared** (absent section means "no exemptions"; an exempt zone with no
  named substitute proof is a BLOCK — see the exempt-zone law below).
- The same subagent reports, as **judgment that surfaces and never blocks**,
  whether the plan is **zero-context** (`strand.md`): does it stand up for a
  reader with repo access and no chat history — no "as we discussed", every
  constraint and every rejected alternative's *why* written out, taste gates
  named, dates and SHAs absolute. A dangling reference to a conversation is
  the one plan defect that is invisible to its author and fatal to its
  builder.
- A **multi-model panel** (see `judgment.md`) additionally reviews the
  design-weighty plans (a real "how should this work" fork) — never a
  notch-drawing plan; match review weight to risk. The reviewing tier is the
  synthesizer (orchestrator for stream plans, captain for fleet plans), and
  an isolated panelist has no repo access, so the plan and its context must
  be **inlined** into the panel prompt, never pointed at by path.
- **One fleet-level review** before ANY launch: one subagent reads all
  stream plans *together* and checks the graph itself — the dependency
  edges, the file-collision matrix, the merge order, and that every decision
  already taken has a durable home in `findings.md`.
- Capped at **2 rounds**; a plan that won't converge is telling you the view
  is under-specified — surface it to the human, don't loop.

## The exempt-zone law (ratified 2026-07-03)

Every stream plan MUST declare its Probity-exempt path zones up front, each
with its substitute proof named — e.g. a pure-visual tree verified by
end-to-end stills + eyeball, or an e2e suite whose run IS its failing-test
discipline. The orchestrator ratifies the list at dispatch (it is a
mechanical criterion of the plan-review gate above); builders may NOT widen
it mid-run — a zone a builder wants added goes to the plan's open-questions
section (or the orchestrator) like any other judgment call. The point: "this
code isn't TDD'd" is always a DECISION with a named replacement check, never
a drift the builder talked itself into at 4am. Probity spend on non-logic
writes is real waste and declaring the zone up front eliminates it — but an
undeclared exemption is how untested logic sneaks into the tree, so the
declaration is the price of the exemption.
