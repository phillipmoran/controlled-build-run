# task_plan.md — <STREAM NAME>

**Branch:** stream/<slug> · **Worktree:** ../<repo>-<slug> · **Run type:** workstream (builder)

## Scope (locked with the orchestrator before dispatch)

<what this stream builds; what is explicitly OUT>

## Probity-exempt zones (ratified at dispatch — builders may NOT widen this list)

<!-- Every zone needs its substitute proof named. No section = no exemptions. -->
<!-- e.g.:  pixi/** — verified by e2e stills + eyeball                        -->
<!--        e2e/**  — the Playwright run IS its failing-test discipline       -->

- (none)

## Build steps

<!-- Altitude (see SKILL.md "Plan altitude"): decision-dense, implementation-sparse.
     Each step = observable outcome + the watched-fail test that proves it + the
     decisions already locked (event/field/threshold/color/seed/file:line) + files
     owned + verify command — then stop; the implementation is the builder's. No
     unresolved design fork starts here — resolve it or park it in "Open with the operator". -->

- [ ] P0 — control-plane operability probe (prove-NO blocked / prove-YES ok)
- [ ] P1 — <first watched-fail TDD cycle>
- [ ] ...

## Verification commands

<typecheck / test / lint commands for THIS repo>

## Status file

Update `<worktree>/STATUS.md` (build name, phase, state, blocked-on) on every
phase transition — the orchestrator and the cockpit watch that file, not this plan.

## Open with the operator

<!-- A headless session cannot ask questions. Park human-only decisions here
     and keep building everything else. -->

## Decision log (in-flight)

| When | Decision | Why |
| ---- | -------- | --- |
