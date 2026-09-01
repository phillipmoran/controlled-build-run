---
name: cbr
description: >-
  Run the work under the CBR control plane. Use when the user says "per CBR",
  "per the CBR control plane", "with controlled-build-run", "run CBR on this",
  or wants a plan-driven, gate-guarded build. Routes to setup, plan, or build
  based on the repo's current state.
---

# cbr — the front door

You are entering a Controlled-Build-Run. Work through these state checks in
order. Do not skip ahead; each step's outcome decides the next.

## 1. Is the control plane armed here?

Look for the vendored package (a `controlled-build-run/` folder at the repo
root, or `skill/claude-controlled-build-run/` if this repo IS the package)
and run its doctor / static check (`verify/smoke.sh` from the package, or the
leaf's `cbr.sh doctor`). Read the PASS/FAIL lines yourself.

- **Not armed:** stop and offer `/cbr-setup`. Do NOT run setup silently —
  it is heavy (stack detection, config adaptation, live probes) and its
  ratify step needs the operator. Ask: run it now, or in a fresh session?
- **Armed:** continue.

## 2. Is there a plan, and is it the right one?

Read `task_plan.md` at the worktree root.

- **No plan:** invoke `/cbr-plan`. The conversation that led here (a design
  discussion, a Wayfinder session, a PRD) is its input — compile it, do not
  re-derive it.
- **Plan exists:** check freshness before trusting it:
  - `**Branch:**` line does not match the checked-out branch → wrong or
    stale plan. Surface it; never build on it silently.
  - Every phase checked → a finished plan that was not archived. Surface it;
    the work is done or the closeout was skipped.
  - Unchecked phases remain → a resume candidate. Confirm with the user in
    one line ("continuing <plan title> from phase N?") and proceed.

## 3. Build

Invoke `/cbr-build` against the confirmed plan.

That's the whole router. The law lives in the package
(`skill/claude-controlled-build-run/SKILL.md` and its references); read the
piece you need when you need it rather than loading everything now.
