# Codex CBR setup

This package is the Codex-native leaf over the provider-neutral CBR law. Its
byte-exact, self-contained core snapshot lives under `references/cbr-core/`;
Codex mechanisms remain in the leaf. Install and validate it from the target
repository root; do not merge its files over an existing hook/config surface
blindly.

## Install

1. Copy this package to `.agents/skills/codex-controlled-build-run/` or retain a
   repository source copy at `skills/codex-controlled-build-run/`.
2. Install the pinned guard and judge SDK in the target repository:

   ```bash
   npm install --save-dev @nizos/probity@1.10.0 @openai/codex-sdk
   ```

   Use the repository's package manager and lockfile policy instead of `npm`
   when applicable.
3. Install the sibling teaching skills this leaf's reground hook injects. From
   the kit root:

   ```bash
   cp -R "$KIT/sibling-skills/cyclomatic-complexity" skills/
   ```

   The hook resolves each at `.agents/skills/<name>/SKILL.md` first, then
   `skills/<name>/SKILL.md`, and skips any that is absent — so a port that omits
   this step still re-grounds, it just re-grounds without the teaching material
   behind a gate that will still block its commits.

4. Run `scripts/cbr-codex.sh arm /absolute/repository/path`.
5. Replace every fail-closed placeholder in `.cbr-codex.json` and
   `.pre-commit-config.yaml`. Put repository-specific RoboRev rules in
   `.roborev.toml`; model values remain projected from `.cbr-codex.json` by
   `cbr-codex.sh sync-models`.
6. Start the Codex terminal TUI in the repository. At the `Hooks need review`
   screen choose `Review hooks`, inspect every command and source, then use the
   on-screen trust action. Codex Desktop chat does not expose a `/hooks` command.
   Record the vetted hash with `cbr-codex.sh record-hook-trust`.
7. Start RoboRev, run `cbr-codex.sh doctor`, then run the live
   `cbr-codex.sh probe`. A repository is not armed until both pass.

When developing this package inside `the reference host`, run
`scripts/tests/conformance.py --canonical-source-repo ../cbr-core` from the
package root. It
proves that the embedded core is exact and that provider mechanics stay on the
correct side of the core/leaf boundary. Installed copies can run it without an
argument to validate their self-contained snapshot. Do not pass
`--canonical-source-repo` in a port: that mode intentionally requires the
historical source object in this repository.

## Before an unattended builder

- Provision a fresh worktree and put a branch-correct planning trio at its root.
- For a fleet, make the deterministic `.cbr-fleet.json` companion agree with
  the fleet table and pass `graph-check`/`dispatchable`.
- Run the full live pre-commit gate in the worktree.
- Launch only after the model, sandbox, approval policy, hook hash, provision
  record, plan identity, dependencies, and ownership facts are visible.
- Immediately arm both watcher and watchdog commands printed by `launch`.

See `references/porting.md` for every project knob and
`references/acceptance.md` for the smoke contract.
