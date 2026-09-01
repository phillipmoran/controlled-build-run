# reviews.md — the review layers beyond the advisory per-commit pass

Part of `cbr-core`, the provider-neutral CBR law. Per-commit review (RoboRev,
advisory since the 2026-08-31 cadence move) and the PR-boundary loop that
replaced commit-time close-discipline live in `build-loop.md`; the merge
review gate is the wall that collects that homework. This file carries the
layers around them: the golden sample, the phase checkpoint, and the
plan-review gate.

## Golden samples — eyeball what a reader will read

When the work produces an artifact a human or an LLM will _read_ — a prompt,
a report, a generated document — render a full, realistic sample and
actually look at it. Unit tests check that the structure is present; they do
**not** tell you whether it reads well, leaks an internal id, double-renders,
or drops something that should be there. A throwaway script that builds real
domain objects and prints the output is the cheapest way to catch these (do
not commit the script). When the format is human- or hero-facing, review the
sample _with the human_ — format is their call, and a missing requirement
(something that should be in the output but no test demands) is exactly what
eyeballing catches and TDD cannot.

## Checkpoint review — at every phase boundary

When you mark a phase complete, run a scoped consistency review _before
starting the next phase_. This is the layer that catches a contradiction
_across documents_ — a contract vs the code vs the roadmap — which
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

  | Phase | end_sha   | reviewed    |
  | ----- | --------- | ----------- |
  | 1     | `a1b2c3d` | `a1b2c3d` ✓ |
  | 2     | `e4f5a6b` | pending     |

  When a phase finishes, stamp the table and commit: run
  `git rev-parse HEAD`, write the result as `end_sha`, commit. The recorded
  sha is therefore the **parent of the stamp commit** — the stamp commit is
  outside its own phase by definition, so the table never chases its own
  tail. A stamp commit may touch **only record files** (the checkpoint
  table and the plan/status/progress/findings records) — never a source or
  test file; a reviewer checks a stamp commit against exactly that
  property and nothing else. A phase's start is the previous phase's
  `end_sha`.

- **What to review.** The diff over `<last reviewed sha>..HEAD` — exactly
  this phase's not-yet-reviewed commits (the diff plus the new files). Run
  it as an **independent read-only subagent** (never a self-review — the
  author can't see their own blind spots; model per the leaf's dial). Check
  it against two specs: the phase's **stated goal** in `task_plan.md` and
  the **ratified contract(s)** the diff touches. Anchor it on the success
  behavior, not a role: _the best cross-artifact auditor proves a
  contradiction by quoting both sides, and stays silent when the artifacts
  agree._ Hand it the **contradiction taxonomy** — the cross-document
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
  you stamp `reviewed = end_sha`, those commits are never re-reviewed. The
  previous phase's stamp commit appears in the next phase's scope; it needs
  no line-level review — a STAMP commit (record files only, the diff only
  stamping the table and its status records) is checked against exactly
  that property, nothing more. Any other record change — a plan rewrite, a
  findings entry — gets ordinary review. If a finished phase reopens (more
  commits land on it), only the new delta gets reviewed.

- **Fix load-bearing FINDINGS before starting the next phase.** Minors and
  INTERPRETATIONS are the human's call (or yours, logged in the plan).

## Review economics — what a review may stop a commit for (ratified 2026-08-29)

Two rules, and both exist because review is not free. Every blocking round
costs a full commit → review → fix lap, and the laps are spent from the same
budget whether they buy a real defect or a better sentence.

**A review blocks only on substance.** Substance is code, tests, and claims
that are factually false — an enforcement narrower than its stated contract, a
guard that does not bite, a comment or a record asserting something the tree
does not do. Findings about **prose** — wording, tone, ordering, a heading, two
records phrased differently, a sentence that could be clearer — are ADVISORY:
they are surfaced, and they never hold a commit. This is not a claim that
prose does not matter. It is a claim about where the cost lands: a wording
round trip costs the same lap as a real bug, and a build that pays it at the
same rate stops paying attention to either.

Advisory-versus-blocking is decided at the **review-config seam** (the host's
review guidelines / review config), not in the reviewer's head and not by the
builder arguing it afterwards. A control plane whose reviewer has not been told this
will keep producing blocking wording findings, and the builder will keep
paying them.

**The finding surface is the class, not the instance.** The 3-TOTAL round
cap in `build-loop.md` counts review-fix commits in the merge range, and
every wording or consistency finding raised against a record set is ONE
surface — not one per file, not one per sentence. Three reviews that each
rename the same idea in a different record are the same surface on its
second and third lap, and the judgment budget for it has already been
spent. The rule that makes this operational: when a finding names a class of
occurrences, fix the class once and record the decision; further instances
of that class are not new rounds, and re-litigating them is the loop the cap
exists to stop. Past the cap, the exits are the judgment decline or the
escalation ruling (`build-loop.md`) — the ruling is where honest new-defect
rounds are told apart from re-litigation.

What none of this waives: a **false** statement in prose is substance. A record
that says a gate is armed when it is not, or a comment describing behaviour the
code does not have, blocks — because the defect is the claim, not the wording.

## The plan-review gate — review the plan before its builder runs

A plan executed faithfully by a frontier builder is the most expensive
artifact in this flow, so a _bad plan_ is the costliest failure — review the
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
  constraint and every rejected alternative's _why_ written out, taste gates
  named, dates and SHAs absolute. A dangling reference to a conversation is
  the one plan defect that is invisible to its author and fatal to its
  builder.
- A **multi-model panel** (see `judgment.md`) additionally reviews the
  design-weighty plans (a real "how should this work" fork) — never a
  notch-drawing plan; match review weight to risk. The reviewing tier is the
  synthesizer (the dispatching orchestrator; the human for fleet plans), and
  an isolated panelist has no repo access, so the plan and its context must
  be **inlined** into the panel prompt, never pointed at by path.
- **One fleet-level review** before ANY launch: one subagent reads all
  stream plans _together_ and checks the graph itself — the dependency
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
