# For agents working in this repository

Route by intent — read only what the task needs:

- **Use CBR on a project** → you're in the wrong repo; CBR gets vendored
  into the target repo. `README.md` → "How to use CBR", then `SETUP.md`.
- **Arm THIS repo's tooling** → don't. This repo is the package itself; it
  is deliberately not armed (the verify suite covers it instead).
- **Edit the package** (`skill/`, `sibling-skills/`, `control-plane/`,
  `verify/`, `SETUP.md`, `MANIFEST.md`) → these are exported from an
  upstream source repo; see `CONTRIBUTING.md` before touching them.
- **Edit the plugin layer** (`skills/`, `.claude-plugin/`) → repo-native,
  edit directly. Keep skill bodies thin: they route into the package, they
  don't duplicate its law.
- **Port to a new harness** → `skill/claude-controlled-build-run/PORTING.md`
  or `skill/codex-controlled-build-run/references/porting.md`.
- **Verify anything** → `verify/smoke.sh` (static), then the full suite:
  `for t in verify/*.test.sh; do bash "$t" || exit 1; done`.

Invariants (checked by CI, cheaper to honor than to discover):

- Regenerate `MANIFEST.sha256` (`./generate-manifest.sh`) in the same commit
  as any content change.
- The two core snapshots stay byte-identical (`verify/core-mirrors.test.sh`).
- Person-neutral text: the human is the **operator**; no personal names,
  machine paths, or private project names.
- CBR is a control plane; a harness is the agent runtime it plugs into.
