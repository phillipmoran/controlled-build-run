# Claude leaf acceptance rows

The complete acceptance contract is the shared checklist under
`references/core/acceptance/` (checklist + scenarios + mutations) plus these
provider-mechanical rows. IDs here MUST exactly equal the rows marked
`leaf-row` in the shared checklist.

- **A3** — the worktree-safe pre-push hook denies a `stream/*` push unless
  `CBR_ALLOW_PUSH=1` (immune to `--dangerously-skip-permissions`, which drops
  only the prompt layer); `.claude/settings.local.json` is gitignored.
- **B1** — the resolved live `.claude/settings.json` arms: Probity `PreToolUse`
  (matcher `Bash|Write|Edit`) preferring the local install with a **pinned**
  `@nizos/probity@<v>` npx fallback (never `@latest`; the two pins —
  `package.json` and the hook line — bump together); the SessionStart session
  sweep; the `compact`-matched re-ground (a SessionStart hook, never
  `PostCompact` — log-only, cannot inject); the RoboRev PostToolUse gate; and
  the `no-interactive-ask` guard on `AskUserQuestion`. Git post-commit and
  post-rewrite hooks resolve through `git rev-parse --git-path` (a worktree's
  `.git` is a file). Arming merges into existing settings, never clobbers.
- **B4** — a fresh strand proves BOTH guard and ability after pre-warming the
  npx cache (a cold fetch can exceed the hook timeout and fail open → false
  prove-NO): an untested guarded write is BLOCKED (prove-NO); one real
  toolchain command + one allowed scratch write SUCCEED (prove-YES); the
  subagent/Agent path is exercised, not only Edit/Write.
- **C3** — the compaction triple in `.claude/settings.json` (root AND the
  stream template): `autoCompactEnabled: true`, `autoCompactWindow: 350000`,
  `autoCompactThreshold: 0.85`; on a smaller-context model the window clamps
  to the model's own limit. `cbr.sh doctor` checks all three.
- **F4a** — builders launch as **`claude --bg`** session roots (on-plan),
  never `claude -p` / the Agent SDK (off-plan billing) and never tmux
  (impossible from a Claude session — the Bash tool has no pty).
- **F4b** — `--dangerously-skip-permissions` (never `--permission-mode auto` —
  hangs unattended on compound bash; never `--bare` — skips hooks); dispatched
  via `claude --bg` so the session is parented to the supervisor daemon (never
  a `&`-child of the orchestrator), confirmed in `claude agents --json` as a
  background session rooted in the worktree; dispatched only into a worktree
  of an already-trusted repo (no send-keys rescue exists for a `--bg` trust
  prompt); the provisioned worktree carries `"bgIsolation": "none"` so the
  builder edits its own worktree directly.
- **F4c** — `--model`/`--effort` are passed explicitly from the dial and
  surfaced before a token is spent (never inherited from settings.json, no
  friendly aliases — the full id, e.g. `claude-sonnet-5`); a wrong-model
  builder triggers the recovery ritual (stop, reset worktree, close reviews,
  relaunch, audit that nothing it authored survives).
- **G1** — liveness is asserted from GROUND TRUTH by `cbr.sh status`/`fleet`
  from outside: the supervisor registry (`claude agents --json --all`) matched
  to THIS worktree's cwd (never a global match), last-commit age,
  `claude logs <id>` movement, open reviews — never plan-usage % or a stale
  heartbeat. `state` is weighed WITH commit-age (`working` + stale commits is
  the page); waits key on latching ground truth (a new commit sha), never a
  fixed countdown or another session's `state`.
- **G4** — dispatch and watch never separate: `cbr.sh launch` drops a
  needs-arm sentinel and prints the REQUIRED arm directive; `cbr.sh watch`
  (armed immediately after launch, backgrounded as a tracked task — the bare
  watcher FIRST, then `--watchdog --cycle <id>` with the cycle id the
  watcher's armed line prints) clears it; `cbr.sh status` flags a
  live-but-unwatched builder as **UNWATCHED**; the `--watchdog` dead-man
  catches a dead watcher, and binding it to the cycle is what lets it retire
  cleanly after DONE instead of paging.
- **K4** — temporary files are trap-cleaned; persistent watcher state stays
  under `.cbr-watch/` (gitignored) and archives at closeout with the stream's
  bookkeeping (`docs/streams/archive/<slug>/`).

## Claude leaf unbuilt set (TO BUILD — update as enforcement ships)

Guarantees that are real but whose mechanical enforcement does not exist yet
in THIS leaf (the shared checklist marks the neutral rows; each leaf tracks
its own unbuilt status):

- **F4 / F6a / F6c wiring** — the deterministic checker EXISTS
  (`.cbr-codex/scripts/cbr_graph.py`: DAG acyclicity, ownership overlap
  rejected unless the overlapping streams are dependency-serialized (the
  file-collision-edge law), dep-vs-merge, dispatchability facts — do not
  re-implement it); what this leaf lacks is the WIRING: no `cbr.sh` subcommand calls it as
  a fail-closed pre-launch gate, so the topological sweep and per-unlock arm
  sequence run by orchestrator hand today, and the F6a judgment-only clauses
  (shape-only steps, fog-field enumeration) stay subagent-checked.

(**E1**, the plan-coherence gate, SHIPPED and hard-blocks in this repo —
`.cbr-codex/scripts/plan-coherence.sh` via pre-commit: branch-line match,
staged production work must stage `task_plan.md`, checkpoint stamps must be
ancestors of HEAD. The old v3 checklist's "(TO BUILD)" status was stale.)
