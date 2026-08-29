# Codex leaf acceptance rows

The complete acceptance contract is the shared checklist under
`references/cbr-core/acceptance/` plus these provider-mechanical rows. IDs here
MUST exactly equal the rows marked `leaf-row` in the shared checklist.

- **A3** — the worktree-safe pre-push hook denies a `stream/*` push unless
  `CBR_ALLOW_PUSH=1`; worktree-local permission state is ignored by Git.
- **B1** — the resolved `.codex/hooks.json` arms pinned Probity with
  `--agent codex`, session sweep, a `PostCompact` worktree-and-thread marker consumed by
  `UserPromptSubmit` or `SessionStart(resume)` with
  `additionalContextLimit: 0`, RoboRev feedback, question redirect, and Stop
  continuity; Git post-commit and post-rewrite hooks resolve through
  `git rev-parse --git-path`.
- **B4** — a trusted fresh strand proves two consecutive blocked untested
  guarded writes and an allowed toolchain/scratch write through Bash,
  `apply_patch`, and every enabled Codex write alias.
- **C3** — `.codex/config.toml` applies
  `model_auto_compact_token_limit = 297500` only to a model whose context can
  support it; the effective threshold clamps for smaller models.
- **F4a** — builders launch as persisted, non-ephemeral
  `codex exec --json -C <worktree>` roots recorded by the harness.
- **F4b** — builders launch with `--sandbox workspace-write`,
  `approval_policy="never"`, verified hook trust, and an outside-owned PID/thread
  registry; unrestricted, skipped-hook, untrusted, or dispatcher-child variants
  fail.
- **F4c** — launch passes and prints the exact model and reasoning values from
  `.cbr-codex.json` before the first model event; a wrong-model run follows the
  stop/audit/relaunch ritual.
- **G1** — `status` derives liveness for this worktree from
  `.cbr-codex/runs/<slug>/` PID, thread, JSONL, cwd, commit age, and review facts;
  a global Codex process or stale heartbeat cannot satisfy it.
- **G4** — launch creates `.cbr-codex/watch/<slug>.needs-arm`; arming `watch`
  clears it, and the independent watchdog detects a stale watcher heartbeat.
- **K4** — temporary files are trap-cleaned and persistent run/watch bookkeeping
  stays under `.cbr-codex/runs/` and `.cbr-codex/watch/`.
