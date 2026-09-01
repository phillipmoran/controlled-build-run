# Composing CBR with an external planning methodology

CBR's plan format is a **compilation target**, not an authoring format. If
you plan with something richer — Wayfinder, a PRD process, a design-doc
review — keep doing that. `cbr-plan` compiles the output into the contract
the gates can type-check; it does not replace the methodology that produced
it.

## The pipeline

```
Wayfinder session (or PRD, or design review)
        │  produces: goal, decisions, ordered milestones, risks
        ▼
cbr-plan  — compile, don't re-derive
        │  produces: task_plan.md in contract shape
        ▼
CBR gates — type-check and enforce
           (branch header vs checked-out branch, checkbox honesty,
            stop-before-DONE, merge review wall)
```

## Worked example

Suppose a Wayfinder-style session ends with this (abridged):

> **Destination:** users can export their dashboard as PDF.
> **Route:** (1) server-side render endpoint, (2) queue + retry for slow
> exports, (3) UI affordance with progress. **Hazard:** the render library
> pins an old headless-chrome; isolate it behind a worker.

`cbr-plan` compiles that into `task_plan.md`:

```markdown
# Dashboard PDF export

**Run type:** stream
**Branch:** stream/pdf-export

## Goal

Users can export their dashboard as PDF (ratified: Wayfinder session
2026-09-01; hazard noted: render library isolated behind a worker).

## Work

- [ ] P1 — Render endpoint returns a PDF for a fixed dashboard fixture
  (test: `test/export/render.test.ts`, watched to fail first).
- [ ] P2 — Slow exports queue and retry; a killed worker leaves the job
  re-runnable (test: `test/export/queue.test.ts`).
- [ ] P3 — UI export button with progress; e2e covers the happy path
  (test: `e2e/export.spec.ts`).

## Locked decisions

- Render library runs only inside the worker (headless-chrome pin).
```

What compilation preserved: the ratified goal, the ordering, the hazard as
a locked decision. What it added: the contract shape the gates check —
`**Branch:**` header, verifiable per-phase tests, checkboxes that start
unchecked.

## Why bother

The external methodology is judgment; the contract is enforcement. The
gates can't check whether your route was wise, but once compiled they CAN
check that the plan matches the branch, that boxes only get checked after
verification, and that the session can't end silently with work open. Each
layer does what it's good at.
