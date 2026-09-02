# Changelog

## 0.13.0 — 2026-09-02

Fixes from the first external review of the public package.

- **One installer for Claude Code.** `cbr.sh arm` is the install path;
  `SETUP-claude-code.md` is now the procedure around it. The separate
  `control-plane/` folder and `verify/smoke.sh` are gone: they installed a
  weaker control plane than `doctor` required (three of five hooks, no push
  firewall, no record gate, a settings block missing two hook events) and
  smoke.sh verified none of it.
- **Fast-forward merges no longer bypass the merge review wall.** A
  fast-forward merge creates no commit and fires no hook. Both installers
  set `merge.ff=false`; both doctors fail when it is not set.
- **Control-plane guard.** A new PreToolUse hook denies the agent's own
  edits to the session hooks and their wiring, `.git/`, and the gate
  scripts, and the git bypass idioms (`--no-verify`, `core.hooksPath`,
  `merge.ff`). Operator unlock: `CBR_CONTROL_PLANE_UNLOCK=1` in the session
  environment. A bar against the casual disarm, not a vault; the README says
  so. Claude Code leaf only (Codex parity is on the roadmap).
- **Doctor grades liveness, not presence.** Fails on `EDIT ME` markers left
  in `probity.config.ts` or `.roborev.toml`, on a missing TDD sibling skill,
  on `merge.ff` unset, and on a missing or disabled compaction setting;
  warns (rather than fails) when the compaction numbers merely differ from
  the reference values, and when an installed hook body drifts from its
  template.
- `arm` installs the sibling skills the re-ground hook points at
  (`test-driven-development` required, `cyclomatic-complexity` and
  `planning-with-files` optional) and takes `--model <id>` to pin the
  orchestrator model on the fresh settings file.
- Probity pin unified at `@nizos/probity@1.10.0` across the template, the
  spec, and the manifest.
- `roborev-gate.sh` and `upstream-issues.md` now agree on `roborev wait -q`
  returning 0 when no job exists.
- MANIFEST rewritten to describe the shipped tree (no `control-plane/`
  section, no exporter claim, VERBATIM rows true by exporter contract);
  `PORTING.md` names the re-ground hook's real knobs; the cyclomatic skill
  and `policy.md` agree that the complexity ceiling is optional and gates
  only where wired.
- Tests: `merge-ff-guard.test.sh`, `control-plane-guard.test.sh` (new);
  `tool-staleness.test.sh` no longer fails when the network is present;
  the suite's dependencies (`jq`, `lsof`, `python3`) are declared in
  CONTRIBUTING.

## 0.12.0 — 2026-09-01

First public-shaped release of the package.

- Post-delta-v2 package content: two harness leaves (Claude Code, Codex)
  over one provider-neutral core, sibling skills, repo-level hook set
  (`control-plane/`), and the behavioral verify suite (14 tests).
- Control-plane vocabulary throughout: CBR is a control plane; "harness"
  now means only the agent runtime it plugs into.
- Person-neutral text: the human role is the operator.
- Claude Code plugin layer: `.claude-plugin/` metadata and five skills —
  `/cbr` (router), `/cbr-setup`, `/cbr-doctor`, `/cbr-plan`, `/cbr-build`.
- New positioning README, contributor docs, CI (verify suite, manifest,
  secrets, de-personalization).

Earlier history lives in the upstream source repo and predates this
changelog.
