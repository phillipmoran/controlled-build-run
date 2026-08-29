# MANIFEST — every file, its source, and where it installs

This repository is the canonical source; a copy is identified by content
(`MANIFEST.sha256` + `VERSION`), not by a source-commit stamp. After any edit,
run `./generate-manifest.sh` and commit the refreshed manifest; check a copy's
integrity with `./verify-manifest.sh`. Extracted from a production harness
hardened across two host projects. Tool versions observed at last
regeneration: `claude 2.1.x`, `roborev v0.58+`,
`@nizos/probity@1.10.0` (TDD judge = codex, model pinned per-thread in
probity.config.ts), node 24 / pnpm 10.

**Copy mode:** VERBATIM = use as-is · TEMPLATE = edit per repo · EXTERNAL = installed
tool, not a file · HUMAN = secret/auth, never copied.

## The skill — `skill/claude-controlled-build-run/`

| File | Source in the origin host | Mode | Installs to | Notes |
|---|---|---|---|---|
| `SKILL.md` | `skills/claude-controlled-build-run/SKILL.md` | ~VERBATIM | `<repo>/skills/claude-controlled-build-run/` | Policy + why. Re-point the origin host specifics per `PORTING.md`. |
| `references/harness-spec.md` | same | ~VERBATIM | with the skill | Per-piece verify/install + the porting caveat. |
| `references/acceptance-checklist.md` | same | VERBATIM | with the skill | The invariant contract (A–K). |
| `scripts/cbr.sh` | same | TEMPLATE (light) | with the skill | Dispatch rail. Edit the declared constants — `PORTING.md` has the full table. Optional (fleet only). |
| `scripts/captain-watch.sh` | same | VERBATIM | with the skill | Builder watchers (DONE hash-latch + stall + watchdog). Project-agnostic. |
| `PORTING.md` | `skills/claude-controlled-build-run/PORTING.md` | — | reference | Exact deltas for SKILL.md + cbr.sh + hooks. |
| everything else under `skill/` (`SETUP.md`, `templates/`) | same paths | VERBATIM | with the skill | Mirrors the live skill — `export.sh` keeps the whole directory in sync. |

## Sibling skills — `sibling-skills/`

| Skill | Source | Mode | Required? | Notes |
|---|---|---|---|---|
| `planning-with-files/` | `~/.claude/skills/planning-with-files/` | VERBATIM | **Required** | The plan (`task_plan.md`). Ships its own hooks; **Stop** hook is install-location-sensitive (see SETUP Step 3 caveat). |
| `test-driven-development/` | `skills/test-driven-development/` | VERBATIM | **Required** | The TDD discipline Probity enforces; re-injected by the reground hook. |
| `fusion/` (+ `commands/`) | `~/.claude/skills/fusion/` + `~/.claude/commands/fusion-*.md` | VERBATIM | Optional | `/fusion-gpt5.5` design panel. Needs `codex`/`gemini` CLIs; falls back to two-Opus. |
| `stage-review/` | `<canon>/skills/stage-review/` | TEMPLATE | Optional | the origin host-shaped phase-review cadence; not referenced by name in SKILL.md. |
| `closeout/` | `<canon>/.claude/skills/closeout/` | TEMPLATE | Optional | the origin host-shaped closeout ritual + facts script. |

## Harness — `harness/`

| File | Source | Mode | Installs to | Notes |
|---|---|---|---|---|
| `hooks/roborev-gate.sh` | `.claude/hooks/roborev-gate.sh` | VERBATIM | `<repo>/.claude/hooks/` | PostToolUse: wake on a RoboRev FAIL. Project-agnostic. |
| `hooks/roborev-session-sweep.sh` | `.claude/hooks/roborev-session-sweep.sh` | VERBATIM | `<repo>/.claude/hooks/` | SessionStart: list open FAILs + liveness line. Project-agnostic. |
| `hooks/post-compact-reground.sh` | `.claude/hooks/post-compact-reground.sh` | VERBATIM + declared knob | `<repo>/.claude/hooks/` | The lifeline. Verbatim mirror of the live hook; edit the `PORTING` block at the top (doc list, vocab, handoff guard) per repo — it injects only docs that exist. |
| `hooks/no-interactive-ask.sh` | `.claude/hooks/no-interactive-ask.sh` | VERBATIM | `<repo>/.claude/hooks/` | Blocks AskUserQuestion in `--bg` builders (they must use ASK-ORCH.md). Project-agnostic. |
| `scripts/roborev-clean-gate.sh` | `scripts/roborev-clean-gate.sh` | VERBATIM | `<repo>/scripts/` | The close-every-review wall. **Must** be at repo-root `scripts/` (the pre-commit entry hardcodes `./scripts/...`). Project-agnostic. |
| `settings.hooks.json` | *extracted from* `.claude/settings.json` | TEMPLATE (merge) | merge into `<repo>/.claude/settings.json` | The `hooks` block (Probity + RoboRev gate + sweep + reground). **Merge, never overwrite.** Set `"model"` separately. |
| `templates/probity.config.ts.template` | *from* `probity.config.ts` | TEMPLATE | `<repo>/probity.config.ts` | The single most repo-specific file (globs + bans). |
| `templates/pre-commit-config.yaml.template` | *from* `.pre-commit-config.yaml` | TEMPLATE | `<repo>/.pre-commit-config.yaml` | Replace format/lint/type/test; keep `roborev-clean`. |
| `templates/roborev.toml.template` | *from* `.roborev.toml` | TEMPLATE | `<repo>/.roborev.toml` | Dial keys verbatim; rewrite `review_guidelines`. |

## Worked references — `examples/` (read-only, do not install)

`reference-probity.config.ts`, `reference-.pre-commit-config.yaml`, `reference-.roborev.toml`,
`reference-post-compact-reground.sh`, `reference-.claude-settings.json` — the real, complete
the origin host files. Use them as the gold standard when filling in the templates.

## Verify — `verify/smoke.sh`

Static arming check; run from the target repo root after SETUP. New (kit-authored).

## External tools (installed per machine, not files in the kit)

| Tool | Role | Install |
|---|---|---|
| `claude` (Claude Code CLI) | runs everything; `claude --bg` dispatches builders; `claude agents` is the liveness registry | Anthropic; needs a build with `--bg` + `claude agents` (the origin host: 2.1.186) |
| `roborev` | per-commit review engine + daemon + the gate/sweep/clean-gate | `brew install roborev`, then `roborev init --agent claude-code`. **Sends PostHog telemetry by default — see SETUP "Tool notes" to disable.** |
| `@nizos/probity` | the TDD/naming guard | local `node_modules/.bin/probity` when installed, else fetched by `npx --yes @nizos/probity@1.8.1` (needs node/npm/npx) |
| `jq` | hooks emit JSON through it | `brew install jq` — **required** (hooks fail open without it) |
| `git`, `python3` | worktrees/hooks; gate scripts' inline logic | system |
| `pre-commit` | runs `.pre-commit-config.yaml` | `pipx install pre-commit` or via `uv run` |
| `uv` | Python env + venv the uv-based hooks need | `brew install uv` — only if the repo is Python/uv |
| `gitleaks` | staged-secret scan (optional pre-commit hook) | `brew install gitleaks` |
| `codex` / `gemini` | richer `/fusion` panels | optional; fusion falls back to two-Opus without them |

## Auth / secrets (HUMAN — never copied)

| Item | Where | Note |
|---|---|---|
| Claude OAuth login | macOS keychain / `~/.claude.json` | `/login` per machine; one expired token 401s claude + RoboRev + Probity together |
| Repo trust | `~/.claude.json` `projects[<path>].hasTrustDialogAccepted` | accept interactively once per repo per machine, BEFORE any `--bg` dispatch |
| `~/.roborev/` (DB, daemon, config) | `~/.roborev/` | per-machine; let `roborev init` create fresh — don't copy |

> **Not a dependency (ruled out):** the `roborev-*` slash-command skills
> (`roborev-review`, `roborev-fix`, etc.) — CBR drives RoboRev via the **CLI + hooks
> directly**, not via those skills, so they are excluded from the kit (install
> separately if you want them as operator convenience). Likewise MiniMax / runtime
> LLM API keys are the *game's* concern, not the build harness's.
