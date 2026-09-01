# Fusion plan-review — using `/fusion-gpt5.5` to review a plan before dispatch

The plan-review gate (see SKILL.md *"Every stream plan passes a plan-review gate BEFORE
its builder launches"*) calls for a `/fusion-gpt5.5` panel on design-weighty plans. This
is the *how*. Fusion is its own skill (`~/.claude/skills/fusion`); this note is the
CBR-specific usage: reviewing a `task_plan.md` before it goes into implementation.

## What it is
`/fusion-gpt5.5` = a two-model panel: **one GPT-5.5 panelist (via the `codex` CLI) + one
Opus 4.8 panelist (an Agent subagent)**, answering the *same* review task independently and
blind, then **the Opus session running the panel judges and synthesizes** their answers.
The diversity is harvested, not manufactured — no assigned lenses; both get the task verbatim.

## Who is the synthesizer (the answer: the tier running the review)
Fusion's hard rule is that **the Opus session driving the panel is always the judge — it
can't be delegated to a panelist.** So the synthesizer is whoever runs the review over the
plan:
- **Builder (stream) plans → the ORCHESTRATOR synthesizes.** It authored the fleet, it
  dispatches the builder, it owns the merge — so it judges the panel on each stream plan.
- **Orchestrator (fleet) plans → the HUMAN is the synthesis seam.** The tier above reviews the
  tier below's plan. (For its own fleet plan the orchestrator self-reviews the
  same way — a panel still beats one pass.)
Each tier fusion-reviews the plans it is about to dispatch. The synthesizer stays *separate*
from the panelists — never paste one panelist's output into another's prompt.

## The one gotcha: GPT-5.5 starts in an empty sandbox
`scripts/run_codex.sh` runs the GPT-5.5 panelist with `--cd <throwaway-scratch-dir>`, **not
in the repo**. It has web + bash but **cannot read repo files by path**, and it has none of
your conversation context. So its prompt must be **fully self-contained — inline everything**:
1. **What CBR / the product is** (a short paragraph — it's cold).
2. **Why the plan exists** (the audit finding / the human ask it answers).
3. **The plan itself, inlined verbatim** (the `task_plan.md` text — not a path).
4. **The review criteria** (below).
The Opus panelist (an Agent subagent) *can* read the repo, so it may be pointed at the file
path as well — but give both the *same task* so their answers are comparable.

## How to run it (the steps)
1. `bash ~/.claude/skills/fusion/scripts/detect_panel.sh` → confirms `codex` is present
   (`SLUG=opus4.8-gpt5.5`). Missing `codex` → fall back to `opus4.8-4.8` (two blind Opus runs).
2. Build ONE self-contained review prompt (the four inlined pieces above + the criteria).
3. Launch **both panelists in one turn** so they run concurrently:
   - GPT-5.5: `bash ~/.claude/skills/fusion/scripts/run_codex.sh <prompt-file> <out-file> medium`
     (background — read the out-file when it finishes).
   - Opus 4.8: an `Agent` (`general-purpose`) with the same task; it may read the repo files.
4. When both return, **synthesize as judge — this is a Track B (analysis) merge**, not code:
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
