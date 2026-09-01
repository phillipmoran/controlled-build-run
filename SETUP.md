# SETUP — pick your harness

CBR is vendored into a repo once, then armed per harness. Each harness has
its own installer because each one wires session hooks differently:

- **Claude Code** → [`SETUP-claude-code.md`](SETUP-claude-code.md)
- **Codex** → [`skill/codex-controlled-build-run/SETUP.md`](skill/codex-controlled-build-run/SETUP.md)

What the installers share and what they don't:

- **Shared, written once:** the repo-level gates — the pre-commit wall
  (`.pre-commit-config.yaml`), the review config (`.roborev.toml`), and the
  Probity config (`probity.config.ts`). Whichever installer runs first
  writes them; the second merges into what is already there.
- **Per harness, installed by each:** the session hooks (Claude Code's
  `.claude/settings.json`; Codex's `.cbr-codex.json` plus hook approval in
  the Codex TUI), the skill copy the re-ground hook re-injects, and the live
  proof — that harness's `doctor` and its prove-NO / prove-YES probe.

A repo that will host both harnesses runs both installers. A repo armed for
one harness is NOT armed for the other, and the other's `doctor` will say so.

Adding a harness? Start from `skill/claude-controlled-build-run/PORTING.md`.
