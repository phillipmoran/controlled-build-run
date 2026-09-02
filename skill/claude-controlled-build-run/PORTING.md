# Porting the controlled-build-run skill to a new repo

The canonical home of this skill is `skill/claude-controlled-build-run/` in this
repository (it originally arrived here from a production reference host and has been
hardened in place since). The portable package under `kit/` is GENERATED from it
by `kit/export.sh` — port from a freshly exported kit, never from a stale copy.

The _process_ is universal and travels verbatim. What is NOT universal is a
handful of repo-specific names and paths declared in the scripts and hooks. This
file is the complete list of edits to make them fit a new repo.
(`agent-harness-spec.md` carries the `HANDOFF_GUARD` porting caveat near piece 6 —
read it too. The shared process law under `references/core/` is a byte-copy of
`skills/cbr-core/` and travels verbatim — never edit it in a port.)

## Edits in `scripts/cbr.sh` (the dispatch rail)

Line numbers are approximate — search for the constant name.

| Where                           | Constant                                                                 | Reference value   | Change to                                                                                                                                              |
| ------------------------------- | ------------------------------------------------------------------------ | ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| ~32                             | `DEFAULT_MODEL`                                                          | `claude-sonnet-5`      | a model your account can use for builders                                                                                                              |
| ~33                             | `DEFAULT_EFFORT`                                                         | `medium`               | your builder effort dial                                                                                                                               |
| ~34                             | `WEB_PKG`                                                                | `.` (repo root)        | the npm package whose `node_modules` provision links — or gut provision steps 2/2b if you have no JS package                                           |
| ~47–63                          | `ALLOWLIST_JSON`                                                         | pnpm/vitest verbs      | swap for your toolchain's read-only/test verbs (matters only for ATTENDED `--permission-mode auto` runs; inert under `--dangerously-skip-permissions`) |
| ~74                             | `worktree_path()`                                                        | `../cockpit-$1`        | your worktree prefix (e.g. `../<repo>-$1`)                                                                                                             |
| provision steps 2/2b (~490–535) | node_modules symlink + per-package pnpm entry links                      | pnpm workspace         | your env-build (`uv sync`, `bundle install`, …) — or drop if the pnpm shape fits                                                                       |
| ~310–330                        | push firewall `case "$branch" in stream/*)`                              | builder branch pattern | your builder branch prefix                                                                                                                             |
| ~912–973                        | `integration/` and `cockpit-` tokens in `fleet` role/ownership detection | —                      | your integration-branch prefix and worktree prefix                                                                                                     |

`cbr.sh` is OPTIONAL — it only matters when you dispatch parallel `claude --bg`
builders (the orchestrator/fleet flow). A solo build never calls it; the control plane
(Probity + RoboRev + pre-commit + reground) works without it.

## Edits in the hooks

- `hooks/post-compact-reground.sh` — the declared PORTING block at the top:
  `HOUSE_DOCS` (injected whole; reference: `CONSTITUTION.md AGENTS.md`),
  `PRINCIPLE_POINTERS` (listed as re-read pointers; reference:
  `ENGINEERING.md VISION.md`), `SKILL_REL`/`TDD_REL`/`COMPLEXITY_REL` (where
  the skills landed), `HANDOFF_GUARD`. Point at your repo's short "how we
  build" docs; the hook injects only docs that exist.

## Edits in the router + references (mostly read-as-is; re-point these specifics)

- **PORTING-APPLIED note** atop `SKILL.md`: replace it with your repo's own
  port-time mapping (or drop it for a repo that needs no renames).
- **Model dial** (`references/claude.md` §model dial): set the orchestrator /
  builder / RoboRev-reviewer / review-subagent models to your tiers. This is
  the one place to update when tiering changes. The RoboRev reviewer model
  also lives in `.roborev.toml` (`review_model`) and the Probity judge pin in
  `probity.config.ts` — keep the three in agreement.
- **Package path** references (`packages/**`): Probity's gated tree. Match
  your source layout (`probity.config.ts` globs + the prose in
  `references/claude.md`).
- **Binding-doc names**: the reground hook's `HOUSE_DOCS`/`PRINCIPLE_POINTERS`
  PORTING block, plus mentions in `references/claude.md` and
  `agent-harness-spec.md`. Re-point to your repo's equivalents (or drop where you
  have none).
- **Boot ritual / handoff caveat**: see `agent-harness-spec.md` piece 6 and the
  reground hook's `HANDOFF_GUARD` — set it to 1 only if your routing doc's
  boot ritual reads a newest handoff.
- **Closeout**: stream teardown is `cbr.sh closeout <slug>` (part of the merge
  gate). The optional `sibling-skills/closeout/` skill is the older reference-host-shaped
  solo ritual — use it only if you don't run the fleet flow.
- **Worktree prefix** (`../cockpit-<slug>`): matches the `cbr.sh` change above.
- **Leaf acceptance rows** (`references/acceptance-checklist.md`): the
  provider-mechanical rows hard-code the same port-specific values as the
  scripts — the builder branch pattern (`stream/*`), the model id example
  (`claude-sonnet-5`), the watcher-state dir (`.cbr-watch/`), and the archive
  path (`docs/streams/archive/<slug>/`). When you change a constant in
  `cbr.sh` or the model dial, change its acceptance row in the same pass —
  an acceptance contract describing a different implementation is worse than
  none.

Everything else — the router, the `references/core/` law files, the TDD loop,
the strand model, the Probity gotchas and dispatch invariants in
`references/claude.md`, the orchestrator tier — is repo-agnostic
process. Keep it.
