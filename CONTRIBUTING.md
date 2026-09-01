# Contributing

This repository is the public home of the Controlled-Build-Run (CBR) control
plane. What is canonical where:

- **Package content** (`skill/`, `sibling-skills/`, `control-plane/`,
  `verify/`, `SETUP.md`, `MANIFEST.md`) is exported from an upstream source
  repo. PRs against these files are welcome as bug reports with a proposed
  fix — they get applied upstream and flow back in the next export, so your
  change may land slightly reshaped.
- **Repo-native files** (this file, `README.md`, `skills/` — the Claude Code
  plugin layer, `.claude-plugin/`, `examples/`, `.github/`) are canonical
  HERE. PRs land directly.
- **Third-party harness adapters** are canonical here too — this is the
  contribution we most want. An adapter is about 30 files; start from
  `skill/claude-controlled-build-run/PORTING.md` (Claude) or
  `skill/codex-controlled-build-run/references/porting.md` (Codex) and mirror
  the structure for your harness.

Rules that keep the package coherent:

- **Core law vs leaf mechanics.** The provider-neutral process law lives in
  the core snapshots (`skill/claude-controlled-build-run/references/core/`
  and `skill/codex-controlled-build-run/references/cbr-core/`). They are
  byte-identical by contract — apply every core change to BOTH and run
  `verify/core-mirrors.test.sh`. Harness-specific mechanisms belong in the
  leaf files, never in core.
- **Guards get fixtures.** A changed hook, gate, or script ships with a
  behavioral test under `verify/` proving it fires AND proving it can fail
  (sensitivity). A guard whose failure mode is silence is not done until a
  fixture would catch that silence.
- **Deterministic facts may gate; fallible judgment may only surface.**
  If your check can be wrong, it reports; only checks that cannot be wrong
  get to block.
- **Why-comments only.** Comments state constraints the code can't show.
  No narration, no history — history belongs in commit messages.
- **Person-neutral.** The human role is the **operator** (see the core
  glossary). No personal names, machine paths, or private project names.
- **Vocabulary.** CBR is a *control plane*. A *harness* is an agent runtime
  (Claude Code, Codex) that CBR plugs into. Keep the two words apart.
- **The manifest refreshes itself.** Run `pre-commit install` once; the
  hook regenerates `MANIFEST.sha256` on every commit and stops the commit
  once if it changed so you can stage it. Docs and the plugin wrapper are
  in `MANIFEST.ignore` and never stale it. CI verifies the manifest at HEAD
  regardless.
- **Run the suite.** `for t in verify/*.test.sh; do bash "$t" || exit 1; done`
  before opening a PR (one test takes ~2 minutes; that's normal).
