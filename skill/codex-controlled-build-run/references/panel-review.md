# Codex panel review — reviewing a plan before dispatch

The plan-review gate (see SKILL.md *"Every stream plan passes a plan-review gate BEFORE
its builder launches"*) calls for an independent panel on design-weighty plans.
This is the *how*: reviewing a `task_plan.md` before it goes into implementation.

## What it is
A panel = **at least two independent blind panelists**, answering the *same*
review task, followed by **the orchestrator running the panel judging and
synthesizing** their answers. Use a strong Codex read-only subagent/session plus a
different model family when the repository's ratified tooling makes one available;
do not pretend two prompts to one shared context are independent diversity. The
diversity is harvested, not manufactured — no assigned lenses; all panelists get
the task verbatim.

## Who is the synthesizer (the answer: the tier running the review)
The hard rule is that **the tier driving the panel is always the judge — synthesis
cannot be delegated to a panelist.** So the synthesizer is whoever runs the review
over the plan:
- **Builder (stream) plans → the ORCHESTRATOR synthesizes.** It authored the fleet, it
  dispatches the builder, it owns the merge — so it judges the panel on each stream plan.
- **Orchestrator (fleet) plans → the HUMAN is the synthesis seam.** The tier above reviews the tier
  below's plan. (For its OWN fleet plan the orchestrator self-reviews the
  same way — a panel still beats one pass.)
Each tier panel-reviews the plans it is about to dispatch. The synthesizer stays *separate*
from the panelists — never paste one panelist's output into another's prompt.

## The one gotcha: an isolated panelist starts cold
An external or scratch Codex panelist may start in a throwaway read-only directory,
**not in the repo**. It cannot read repo files by path, and it has none of your
conversation context. So its prompt must be **fully self-contained — inline everything**:
1. **What CBR / the product is** (a short paragraph — it's cold).
2. **Why the plan exists** (the audit finding / the human ask it answers).
3. **The plan itself, inlined verbatim** (the `task_plan.md` text — not a path).
4. **The review criteria** (below).
A worktree-rooted Codex review subagent *can* read the repo, so it may be pointed
at the file path as well — but give every panelist the *same task* so their answers
are comparable.

## How to run it (the steps)
1. Confirm every selected panelist/runtime is available before spending the review.
   A dropped panelist is **absent**, never silent agreement.
2. Build ONE self-contained review prompt (the four inlined pieces above + the criteria).
3. Launch **all panelists in one turn** so they run concurrently. Use Codex
   read-only subagents/sessions for repo-aware panelists and the repository's
   ratified external-family runner for diversity. Never let a panelist edit.
4. When all return, **synthesize as judge — this is an analysis merge**, not code:
   the five sections — **Consensus / Contradictions / Partial coverage / Unique insights /
   Blind spots**. Weight a panelist that read the primary source (the actual code) over one
   reasoning from memory. A dropped panelist is **absent**, never silent agreement.
5. Turn the synthesis into **concrete plan edits** (resolve a fork, tighten an under-specified
   step, fix a dependency-order error, add a missing exempt zone). Re-gate the mechanical
   criteria after edits. Then dispatch.

## The review criteria (what to ask the panel about a plan)
Is the **decomposition** the right cut (streams, file-ownership, collision matrix)? Is the
**sequencing / dependency order** honest? Is every step **test-drivable** at the right
**altitude** (see SKILL.md *"Plan altitude"* — decision-dense, implementation-sparse)? What is
**under-specified** (a builder would guess) or **over-specified**? What **design forks** are
still open that must be resolved before building? Biggest **risks and blind spots** not visible
from inside the plan? Anything **architecturally wrong**.

## When to use it (match weight to risk)
Design-weighty plans — a real "how should this work" fork — get the panel: fleet plans and the
builder stream plans, before implementation. A notch-drawing plan (mechanical, no design fork)
does not — the mechanical plan-review subagent is enough. A panel costs ~N× the tokens and runs
as slow as its slowest panelist; spend it where being confidently wrong about a plan is
expensive, which — since a builder executes the plan faithfully — is most non-trivial plans.
