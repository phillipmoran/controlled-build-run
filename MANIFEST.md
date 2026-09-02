# MANIFEST — every file, its source, and where it installs

This package is GENERATED from the upstream control-plane source; this copy is
identified by content (`MANIFEST.sha256` + `VERSION`), not by a source-commit
stamp. The generated areas are `skill/` (both leaves, each carrying a
byte-identical snapshot of the provider-neutral core) and
`sibling-skills/{planning-with-files,test-driven-development,cyclomatic-complexity}`;
everything else is package-native and hand-maintained. Tool versions observed
at last regeneration: `claude 2.1.x`, `roborev v0.67`, `@nizos/probity@1.10.0`
(the pin in both leaves' hook commands), node 24.

**Copy mode:** VERBATIM = use as-is · TEMPLATE = edit per repo · EXTERNAL = installed
tool, not a file · HUMAN = secret/auth, never copied.

## The Claude Code leaf — `skill/claude-controlled-build-run/`

`cbr.sh arm` installs everything in this table; `SETUP-claude-code.md` is the
procedure around it.

| File | Mode | Installs to | Notes |
|---|---|---|---|
| `SKILL.md`, `SETUP.md`, `PORTING.md`, `references/**` | VERBATIM (PORTING.md lists the few re-points) | `<repo>/skills/claude-controlled-build-run/` | Policy + why; `references/core/` is the shared law, never edited in a port. |
| `scripts/cbr.sh` | TEMPLATE (light, fleet only) | with the skill | Arm/doctor/provision/launch/status/closeout rail. Constants in `PORTING.md`. |
| `scripts/captain-watch.sh` | VERBATIM | with the skill | Builder watchers. |
| `templates/claude-settings.json` | TEMPLATE (model pin; `arm --model`) | `<repo>/.claude/settings.json` | The full hooks block. Existing file → `arm` lists the blocks to merge by hand. |
| `templates/hooks/roborev-gate.sh`, `roborev-session-sweep.sh`, `no-interactive-ask.sh`, `builder-stop-check.sh`, `control-plane-guard.sh` | VERBATIM | `<repo>/.claude/hooks/` | Byte-identical to the upstream live hooks by exporter contract; `doctor` warns when an installed copy drifts. |
| `templates/hooks/post-compact-reground.sh` | VERBATIM + declared PORTING block | `<repo>/.claude/hooks/` | The lifeline. Edit only the PORTING block (doc lists, skill paths, handoff guard). |
| `templates/probity.config.ts` | TEMPLATE | `<repo>/probity.config.ts` | Globs for YOUR production tree; `EDIT ME` until filled. |
| `templates/pre-commit-config.yaml` | TEMPLATE | `<repo>/.pre-commit-config.yaml` | Real typecheck/test commands; keep the gate hooks verbatim. |
| `templates/roborev.toml` | TEMPLATE | `<repo>/.roborev.toml` | Cross-family reviewer pin + your review guidelines. |
| `templates/record-ownership.json` | TEMPLATE | `<repo>/record-ownership.json` | Which record owns which fact. |
| `templates/*.skeleton.md`, `probe-prompt.md` | VERBATIM | read by `cbr.sh` | Plan/status/park-file skeletons; the operability probe prompt. |
| `references/core/scripts/merge-review-gate.sh`, `record-single-source.sh` | VERBATIM | `<repo>/scripts/` | The merge wall and the record gate (the pre-commit entries hardcode `./scripts/`). |

## The Codex leaf — `skill/codex-controlled-build-run/`

`scripts/cbr-codex.sh arm` installs it; its own `SETUP.md` is the procedure.
The `references/cbr-core/` snapshot is byte-identical to the Claude leaf's
`references/core/` (`verify/core-mirrors.test.sh`).

## Sibling skills — `sibling-skills/`

| Skill | Mode | Required? | Installed by |
|---|---|---|---|
| `test-driven-development/` | VERBATIM | **Required** (the re-ground hook points at it) | `cbr.sh arm` (`skills/`) |
| `cyclomatic-complexity/` | VERBATIM | Optional ceiling; installed so the pointer resolves | `cbr.sh arm` (`skills/`) |
| `planning-with-files/` | VERBATIM | Recommended | `cbr.sh arm` (`.claude/skills/`); Stop hook caveat in SETUP Step 4 |
| `fusion/` (+ `commands/`) | VERBATIM | Optional | SETUP Step 4 (`cp -R`) |
| `stage-review/` | TEMPLATE | Optional | SETUP Step 4 (`cp -R`) |
| `closeout/` | TEMPLATE | Optional | SETUP Step 4 (`cp -R`) |

Origins and licenses: `THIRD-PARTY.md` (public repo) and the `LICENSE` files
beside each vendored skill.

## Worked references — `examples/` (read-only, do not install)

`reference-probity.config.ts`, `reference-post-compact-reground.sh` — the
reference host's real files, as the gold standard when filling the templates.
`wayfinder-composition.md` — composing CBR with an external planner.

## Verify — `verify/`

The package's own behavioral suite (`*.test.sh`), also the executable
acceptance source for a port. `cbr.sh doctor` is the static arming check of
a target repo; there is no separate smoke script.

## External tools (installed per machine, not files in the package)

| Tool | Role | Install |
|---|---|---|
| `claude` (Claude Code CLI) | runs everything; `claude --bg` dispatches builders | Anthropic; fleet dispatch needs a build with `--bg` + `claude agents` |
| `roborev` | per-commit review engine + daemon; the merge wall queries it | `brew install roborev`, then `roborev init`. **Sends PostHog telemetry by default — see SETUP "Tool notes".** |
| `@nizos/probity` | the TDD judge | local `node_modules/.bin/probity` when installed, else `npx --yes @nizos/probity@1.10.0` (pin both together) |
| `jq` | hooks emit JSON through it | **required** (surfacing hooks fail open without it) |
| `python3` | gate scripts' inline logic; the control-plane guard (fails closed without it) | system |
| `git`, `pre-commit` | worktrees/hooks; the commit-stage gates | system; `pipx install pre-commit` |
| `gitleaks` | staged-secret scan (template wires it) | `brew install gitleaks` or delete the hook |
| `codex` / `gemini` | richer `/fusion` panels | optional |

## Auth / secrets (HUMAN — never copied)

| Item | Where | Note |
|---|---|---|
| Claude OAuth login | `~/.claude.json` / keychain | `/login` per machine; one expired token breaks everything it powers at once (`doctor`'s agent round-trip catches it) |
| Repo trust | `~/.claude.json` `projects[<path>].hasTrustDialogAccepted` | accept interactively once per repo per machine, BEFORE any `--bg` dispatch |
| `~/.roborev/` | per-machine | let `roborev init` create it fresh |
