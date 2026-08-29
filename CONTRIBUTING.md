# Contributing

This repository is the canonical source of the controlled-build-run harness.
A few rules keep it coherent:

- **Core law vs leaf mechanics.** The provider-neutral process law lives in
  the two core snapshots (`skill/claude-controlled-build-run/references/core/`
  and `skill/codex-controlled-build-run/references/cbr-core/`). They are
  byte-identical by contract — apply every core change to BOTH, and run
  `verify/core-mirrors.test.sh`. Provider-specific mechanisms belong in the
  leaf files, never in core.
- **Guards get fixtures.** A changed hook, gate, or script ships with a
  behavioral test under `verify/` proving it fires AND proving it can fail
  (sensitivity). A guard whose failure mode is silence is not done until a
  fixture would catch that silence.
- **Why-comments only.** Comments state constraints the code can't show.
  No narration, no history — history belongs in commit messages.
- **Person-neutral.** The human role is the **operator** (see the core
  glossary). No personal names, machine paths, or private project names.
- **Refresh the manifest.** After any edit: `./generate-manifest.sh`, commit
  the updated `MANIFEST.sha256` in the same commit.
- **Run the suite.** `for t in verify/*.test.sh; do "$t" || exit 1; done`
  before opening a PR.

Porting questions are answered in `skill/claude-controlled-build-run/PORTING.md`
(Claude) and `skill/codex-controlled-build-run/references/porting.md` (Codex).
