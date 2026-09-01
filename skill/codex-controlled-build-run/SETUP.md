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
3. Optionally install the sibling teaching skills this leaf's reground hook
   injects (the complexity ceiling is an optional per-project knob, not core
   law — install its skill only if your project wires the gate). From the kit
   root:

   ```bash
   cp -R "$KIT/sibling-skills/cyclomatic-complexity" skills/   # only if you wire the gate
   ```

   The hook resolves each at `.agents/skills/<name>/SKILL.md` first, then
   `skills/<name>/SKILL.md`, and skips any that is absent — a port that omits
   this step still re-grounds; in a project that DID wire the gate, it
   re-grounds without the teaching material behind it.

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

When developing this package inside its upstream source repo, run
`scripts/tests/conformance.py ../cbr-core` from the
package root. It
proves that the embedded core is exact and that provider mechanics stay on the
correct side of the core/leaf boundary. An installed copy run without an
argument validates its internal contracts; byte-exactness of its snapshot is
only provable against a canonical core — pass that path explicitly when one
is available.

## Before an unattended builder

- Provision a fresh worktree and put a branch-correct planning trio at its root.
- For a fleet, make the deterministic `.cbr-fleet.json` companion agree with
  the fleet table and pass `graph-check`/`dispatchable`.
- Run the full live pre-commit gate in the worktree.
- Launch only after the model, sandbox, approval policy, hook hash, provision
  record, plan identity, dependencies, and ownership facts are visible.
- Immediately arm the watcher command printed by `launch`.

See `references/porting.md` for every project knob and
`references/acceptance.md` for the smoke contract.
