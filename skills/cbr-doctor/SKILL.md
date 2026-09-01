---
name: cbr-doctor
description: >-
  Check what CBR has armed in this repo and what it hasn't. Read-only: reports
  gate health, never installs or repairs. Use for "is CBR working here",
  "cbr doctor", or before trusting the gates on a new machine.
---

# cbr-doctor — read-only health check

Report the state of the control plane in this repo. Change nothing — a doctor
that repairs while it diagnoses hides which gates were actually live when the
operator asked.

## What to check

1. **Leaf present?** Look for `claude-controlled-build-run/` under
   `controlled-build-run/skill/` (vendored), `skills/` (source copy), or
   `skill/` (this repo is the package). Missing → report "not armed" and
   stop; suggest `/cbr-setup`.
2. **Static suite:** run the package's `verify/smoke.sh` and report its
   PASS/FAIL lines verbatim. This checks hooks installed, configs present,
   templates unmodified where they must match.
3. **Live wiring:** does `.claude/settings.json` in this repo declare the
   CBR hooks (Stop gate, re-ground)? Are the git hooks (`pre-commit`,
   `pre-push`) present and executable?
4. **Runtime deps:** are the tools the configs name actually on PATH
   (test runner, linter, `roborev`, `gitleaks` where configured)?
5. **Plan state:** does `task_plan.md` exist, and do its `**Branch:**` line
   and checkboxes match reality (see the `/cbr` router's freshness tells)?

## How to report

A short table: check → PASS / FAIL / SKIPPED, then one line of verdict:
armed, partially armed (name the dead gates), or not armed. For each FAIL,
name the fix but do not apply it — repairs go through `/cbr-setup`, which
carries the propose-ratify-prove discipline this skill deliberately lacks.
