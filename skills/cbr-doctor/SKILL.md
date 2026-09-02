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
2. **The package doctor:** run the leaf's `scripts/cbr.sh doctor` from the
   repo root and report its PASS/FAIL/WARN lines verbatim. It grades hook
   wiring and executability, hook bodies against their templates, the
   control-plane guard, `merge.ff`, both commit-stage git hooks, the push
   firewall, `EDIT ME` markers left in the configs, the sibling skills, the
   RoboRev daemon and an agent round-trip (an expired login), the compaction
   settings, and the vendored package's manifest.
3. **Runtime deps:** are the tools the filled configs name actually on PATH
   (test runner, linter, `gitleaks` where configured)? The package doctor
   checks its own tools, not yours.
4. **Plan state:** does `task_plan.md` exist, and do its `**Branch:**` line
   and checkboxes match reality (see the `/cbr` router's freshness tells)?

## How to report

A short table: check → PASS / FAIL / WARN / SKIPPED, then one line of
verdict: armed, partially armed (name the dead gates), or not armed. For
each FAIL, name the fix but do not apply it — repairs go through
`/cbr-setup`, which carries the propose-ratify-prove discipline this skill
deliberately lacks. A green doctor proves the files are present and wired;
only the live probes in `/cbr-setup` prove a gate bites.
