---
name: stage-review
description: >-
  Stage-boundary review for the reference host's long autonomous build runs — the
  middle cadence between per-commit RoboRev (the microscope) and the session-end
  closeout (the horizon). Run this whenever you finish a stage of a multi-stage
  plan (a coherent group of cycles/commits, e.g. "Stage 3: prompt assembly,
  R3–P7") and before you start the next stage. It spins up a subagent that reads
  the stage's whole diff against the binding docs and contracts and reports two
  things at once: (1) discipline drift, and (2) lane-crossing — decisions that
  should have been the domain owner's (the operator's) call. Use it proactively at
  EVERY stage boundary during a long build, not only when asked. It is the net
  that catches the executor quietly crossing into vision-shaped decisions over a
  long unattended run — something RoboRev, which sees one commit at a time,
  structurally cannot.
---

# Stage review

## Why this exists

The reference host runs three review cadences, at three altitudes:

- **Per-commit: RoboRev (microscope).** One commit's diff, in isolation, at commit time. Advisory. Cannot see across commits; does not read the plan or the roadmap.
- **Per-stage: this skill (telescope).** A *whole stage's* work as a unit, at the stage boundary, against the binding docs and contracts.
- **Per-session: the closeout (horizon).** The whole session at the end (see `AGENTS.md` `<closeout>`).

The telescope catches what the microscope cannot: drift that only appears across several commits, and — the load-bearing reason this skill exists — **lane-crossing.** Over a long run the executing agent builds with momentum, and momentum is exactly when an agent resolves a vision-shaped fork without noticing it should have surfaced to the operator. RoboRev can't catch that (one diff, no plan, no roadmap). The closeout would, but only at session end, by which point a wrong decision may have rippled through more stages. The stage review pulls that catch *forward* to the boundary where the decision was made, while it is still cheap to reverse.

It is also a **re-grounding point:** the subagent reads the binding docs *fresh, full text, clean context* every time, so even if the main agent's memory of the principles has fuzzed under compaction, the review still judges against the true docs.

## How it's triggered: the plan carries it

This is a **judgment-invoked skill, not a hook** — "a stage just finished" is a *semantic* event a mechanical hook can't detect, and stages aren't equal-sized, so a commit-counter would fire at the wrong granularity and review a blurry half-stage. The trigger lives in the **plan**:

- When you build a multi-stage plan, end each stage with an explicit step: **"← STAGE BOUNDARY: run stage-review before the next stage."** The agent works the plan top-to-bottom and checks off steps, so it reaches the review at every boundary because it is a step like any other — no reliance on memory.
- **Record each stage's START when it begins** — a git tag (`stage-<n>-start`) or a line in the plan capturing HEAD. The review reads that recorded SHA as its base. Do not reconstruct the range from memory; a compaction will have fuzzed it.
- A "stage" is whatever the plan names as a coherent unit (e.g. "Stage 3: prompt assembly, R3–P7"). Size it so reviewing it as a whole adds something over RoboRev's per-commit view — a coherent slice, not every commit.

(Optional future backstop: a hook that every N commits *nudges* "you're N commits past your last review — at a boundary? run it if so." That is a reminder, not the trigger — it can't judge the boundary. Not built; the plan is the primary mechanism.)

## When and how to run it

At each stage boundary, spawn the review. It is a **lightweight checkpoint, not a gate**: you spawn the subagent, wait for its report, and on a clean result continue immediately, no ceremony. It only pauses the run on a real finding (see "Acting on the findings"). Mechanically you do wait for the report — "checkpoint" means cheap-on-clean, not concurrent.

Spawn a subagent of type **`general-purpose`** with **`model: sonnet`** (structured discipline review; Sonnet is cost-effective here; reserve Opus only when a principle is genuinely ambiguous). Do **not** use a limited agent type such as `Explore` — the reviewer must read full files and run `git`.

### What the subagent reads

- The binding docs, in full (no skim): `AGENTS.md`, `CONSTITUTION.md`, `ENGINEERING.md`, `GLOSSARY.md`, `STACK.md`, `ROADMAP.md`, `contracts/AGENTS.md`, and any contract(s) the stage touched.
- If the stage wrote code or tests: `skills/test-driven-development/SKILL.md` and its `testing-anti-patterns.md`.
- The stage's actual work: `git log` and `git diff` for the recorded stage range, plus any new files in full.

It does **NOT** read `docs/_handoffs/` or `spiritual-explorations/` — stale narrative primes interpretation; judge the work against the *binding docs*, not a prior agent's story of intent. It reaches **independent** conclusions: do not feed it RoboRev's per-commit findings — fresh eyes against the docs avoid anchoring on a possibly-wrong prior review.

### The two checks

**Check 1 — Discipline drift.** The closeout's discipline, applied to the stage as a unit: contract-vs-code consistency, rule-vs-description in contract edits, path-addressability and GLOSSARY-vocabulary naming, TDD discipline (behavior-level tests, real/sampled shapes, the Enforcement principle), single-owner / global-vs-per-Place, dead code, size budgets. Each finding cites `file:line` and the principle or contract rule **by name**, with severity **load-bearing / minor / nitpick**.

**Check 2 — Lane-crossing (the differentiator).** Ask: *did any commit make a decision that should have been the domain owner's call?* — a contract edit (or code that sets a rule a contract should own), a new concept/entity name not in `GLOSSARY`, a scope choice against `ROADMAP`, a fork resolved in code without surfacing, a new top-level package. List each with `file:line` and one line on *why it looks domain-owner-shaped*. RoboRev cannot produce this — it never reads the plan, roadmap, or whole stage. This is the unique value.

### Subagent prompt template

```
You are a stage-boundary reviewer for the the reference host repo. Read-only — do not modify anything.

The stage just completed: [STAGE NAME, e.g. "Stage 3 prompt assembly, R3–P7"].
Its commit range is [BASE_SHA..HEAD] (BASE_SHA = the recorded stage-start). The contracts it touched: [list, or "none"].

Step 1 — read in full: AGENTS.md, CONSTITUTION.md, ENGINEERING.md, GLOSSARY.md, STACK.md, ROADMAP.md, contracts/AGENTS.md, the touched contract(s), and (if code/tests changed) skills/test-driven-development/SKILL.md + testing-anti-patterns.md. Do NOT read docs/_handoffs/ or spiritual-explorations/. Reach your own conclusions; do not look at existing RoboRev findings.

Step 2 — review the stage's work: `git log --oneline [BASE_SHA..HEAD]`, `git diff [BASE_SHA..HEAD]`, and read any new files in full.

Step 3 — report two sections:
  A. DISCIPLINE DRIFT — findings with file:line, the principle/contract-rule by name, severity (load-bearing / minor / nitpick).
  B. LANE-CROSSING — any commit that made a decision smelling like the domain owner's call (contract-shaped change, new concept name not in GLOSSARY, scope choice against ROADMAP, a fork resolved without surfacing, a new top-level package). file:line + one line on why.
Then a one-line summary: Aligned / Minor issues / Significant issues / Lane-crossing found.
Keep it under 600 words. If a section is empty, say so plainly — do not invent findings.
```

## Acting on the findings

The findings are **advisory input, not commands** — the subagent is an LLM and can be wrong. Separate the *finding* (a fact: "this violates rule X") from any *interpretation* ("so do Y"); only a fact you verify binds. Then:

- **A discipline finding you verify is real → fix it** (under TDD if it touches code). This is your lane — an engineering-envelope call per the `AGENTS.md` charter: announce it ("I'm fixing X because Y; pushback welcome") and proceed. You do **not** wait for the operator. Load-bearing → fix before the next stage; minor/nitpick → note them, don't grind.
- **A discipline finding you judge is a false positive → dismiss it with a one-line reason.** You are not bound to act on a wrong finding — the reviewer is fallible, you are the judge of its discipline findings.
- **A lane-crossing → STOP and surface to the operator. Do not start the next stage.** (See the next section.)
- **Clean → continue to the next stage immediately.**

The split is the whole point: a discipline finding is checkable against the docs, so resolving it (fix or dismiss-with-reason) is yours. A lane-crossing is a decision the domain owner owns, so you must not resolve it yourself — even "correctly." Acting on a fallible reviewer's *discipline* finding is fine because you verify it first; acting on its *lane-crossing* call is not yours to act on at all.

## The one pause point: lane-crossing

A lane-crossing is the only thing that stops the run. When the review finds one:

1. Pause — do not begin the next stage.
2. Surface it **in-session, where the operator will see it when they return**: name the stage that finished, the specific decision made in code (`file:line`), and why it's their call. Then **end your turn and yield** — do not spin or poll. A simple visible pause is the mechanism; no push notification for now (that can come later).
3. The operator answers when they come back. Resume per their answer:
   - **Ratify** → record the decision where it belongs (usually a contract edit, so it becomes enforced, not just blessed), then continue.
   - **Redirect** → make the change he calls for (under TDD if it touches code), **re-run the stage review** on the corrected work, then continue.
   - **Defer** → note it as an open item; continue only if he says the next stage does not depend on it.

When you pause, state plainly what you are waiting on and what you will do on each branch — so the resume is unambiguous even if context compacted in between.

## Re-run after any fix

After you change anything at a boundary — your own fix of a load-bearing discipline finding, *or* an operator-directed redirect — **re-run the stage review on the corrected work** before continuing. A fix can introduce new drift. Bound it: if the review keeps surfacing issues across ~2 rounds, stop and surface to the operator — repeated churn is a signal something deeper is off, not something to grind on.

## What this is not

- **Not** a replacement for RoboRev (per-commit) or the closeout (session-end). It is the middle cadence; all three are kept.
- **Not** a deterministic gate. It uses a fallible LLM reviewer, so it surfaces (and, for lane-crossings, defers to the operator); it never hard-blocks on its own judgment. Deterministic facts (lint, types, tests) block via the pre-commit gate; fallible judgment does not.
