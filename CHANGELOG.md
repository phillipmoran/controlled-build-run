# Changelog

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
