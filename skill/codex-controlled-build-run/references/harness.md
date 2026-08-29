# Codex harness specification

Verify first. Install only missing or behaviorally wrong pieces. In an established repository, the live `.codex/hooks.json`, `probity.config.ts`, `.roborev.toml`, `.pre-commit-config.yaml`, Git hooks, and entry docs are canonical and may be richer than the templates.

## 1. Planning files

Require `task_plan.md`, `findings.md`, and `progress.md` at the strand root. They are committable build artifacts. `task_plan.md` is the recovery source reinjected after compaction.

Verify:

```bash
test -f task_plan.md && test -f findings.md && test -f progress.md
```

Initialize from `templates/task_plan.skeleton.md` and the repository's own conventions. Do not overwrite an active plan from another run; create the correct worktree/strand first.

## 2. Codex hooks

Project hooks live in `.codex/hooks.json` or inline `.codex/config.toml`. This package uses JSON because `arm` can install one self-contained template without rewriting TOML. Project `.codex/` layers load only for trusted worktrees. Hook definitions are hash-trusted; a new or modified command hook is skipped until reviewed and trusted from the Codex terminal TUI's `Hooks need review` screen unless vetted automation uses `--dangerously-bypass-hook-trust`. Codex Desktop chat does not expose a `/hooks` command.

Required events:

- `PreToolUse`: Probity on `^(Bash|apply_patch|Edit|Write)$`.
- `PreToolUse`: question guard on common interactive-question tool names.
- `PostToolUse`: RoboRev feedback on `^Bash$`.
- `SessionStart`: branch-scoped RoboRev sweep on startup/resume/clear.
- `PostCompact`: write a worktree-and-thread-scoped pending re-ground marker.
- `UserPromptSubmit`: consume that marker and inject the complete re-ground.
- `SessionStart` on `^resume$`: consume the same marker if the compacted
  session was closed before its next prompt.
- `Stop`: builder continuity check.

Codex starts matching hooks from all active config layers concurrently. One hook cannot prevent another matching hook from starting. Hooks must therefore be independently safe and idempotent.

Prefer root-resolved commands:

```text
bash "$(git rev-parse --show-toplevel)/.codex/hooks/<name>.sh"
```

Relative `.codex/hooks/...` paths are wrong when Codex starts in a subdirectory.

## 3. Probity

Probity requires:

- `@nizos/probity` 1.10.0 or later in the project, or a version-pinned `npx` fallback.
- `probity.config.ts` with real production globs and explicit exempt zones.
- The Codex host adapter: `--agent codex`.
- A live PreToolUse probe after hook trust is settled.

The bundled command prefers `node_modules/.bin/probity` and falls back to `npx --yes @nizos/probity@1.10.0 --agent codex`. Keep the package version and fallback pin aligned.

Probity reads the current Codex transcript. After compaction, re-establish a green baseline in the live continuation before a refactor if the TDD rule cannot see the prior test run.

Run the nested SDK judge from a neutral temporary working directory with
`project_root_markers = []`. Without both controls, the nested Codex process
discovers the guarded repository, loads its SessionStart/Stop hooks, and can be
hijacked into continuing the builder plan until the enforcement timeout.

Apply content policies to new file content, not the absolute file path,
unchanged context, or deleted lines embedded in an `apply_patch` request.
Worktree folders and removed legacy text can legitimately name their provider;
scanning patch metadata prevents valid neutral additions and remediation.

Never declare Probity armed from configuration alone. Run the operability probe:

`doctor` must also find the content-policy and verdict-parser runtime/type
helpers and import the complete Probity configuration successfully; a present
top-level config with a broken runtime dependency is not an armed guard.
An older preserved config must also pass the active runtime integration
verifier tied to the current judge-isolation, content-policy, and parser path.
Both `arm` and `doctor` import the executable config and reject comments, dead
code, or an unattested default export before requesting a manual merge. The
helper keeps its judge, content-policy, and config attestations in private
module state, so source code cannot forge them with published property names.
The attested judge and policy are frozen, and the verifier re-checks the current
config graph so a config cannot pass once and then remove either safeguard. The
required policy scope contains every expected include/exclusion exactly once;
duplicates cannot hide a missing production glob or exclusion.
Runtime helper files are byte-checked against the executing skill so an older
parser/judge cannot self-certify with a stale verifier.

1. Attempt an untested production write inside a guarded path. It must block.
2. Attempt a scratch write outside the guarded path. It must succeed; remove it.
3. Exercise the actual patch path (`apply_patch`), not only Bash.

One nondeterministic judge flake may be retried once. Two consecutive unblocked production writes mean `HARNESS-BROKEN.marker`: stop the build.

## 4. RoboRev

Required:

- `.roborev.toml` with an explicit reviewer agent/model and repository guidelines.
- `roborev init`-installed `post-commit` and `post-rewrite` Git hooks.
- `.codex/hooks/roborev-gate.sh` wired to `PostToolUse` `Bash`.
- `.codex/hooks/roborev-session-sweep.sh` wired to `SessionStart`.
- `.cbr-codex/scripts/roborev-clean-gate.sh` wired into the live pre-commit configuration.

Immediate feedback is advisory. The clean gate blocks only the deterministic unfinished-review state:

- open FAIL/unverdicted review;
- queued/running review;
- crashed review with no completed retry for that commit;
- no completed review for `HEAD`;
- unreachable daemon or malformed output.

An open PASS is auto-responded and closed. RoboRev may return JSON `null` for no rows; treat it as an empty set after a successful command. `roborev wait -q` can succeed when no job exists, so always prove `HEAD` with `roborev show <sha>`.

## 5. Deterministic pre-commit gate

The repository's live `.pre-commit-config.yaml` defines the facts. It must include its real format, lint, type, test, secret, and `roborev-clean` commands. All must be verify-only: a gate reports and blocks rather than silently rewriting files.

Worktree-safe Git-hook lookup:

```bash
hook="$(git rev-parse --git-path hooks/pre-commit)"
test -x "$hook"
```

Never inspect literal `.git/hooks`; `.git` is a file in a linked worktree. Never use `--no-verify`.

## 6. Compaction re-ground

After a root session compacts, Codex fires `PostCompact`, but that event cannot
emit `additionalContext`. The marker it writes is consumed automatically by
the next context-bearing prompt hook; no recovery read is required. If the
session closes first, `SessionStart(resume)` performs the same consumption. In
the installed Codex host, `/compact` does not also emit
`SessionStart(compact)`; do not route the lifeline through a source matcher
that never fires.

The hook injects:

- short binding principle/architecture docs that exist;
- `AGENTS.md`;
- this skill;
- role-specific build or fleet reference based on `**Run type:**`;
- the `cyclomatic-complexity` sibling skill, mid-build only, for both roles;
- active `task_plan.md` and a pointer to `progress.md`/`findings.md`.

The complexity skill is injected for the same reason the shared core carries the
complexity-ceiling row: the ceiling is a deterministic pre-commit gate, so an
agent that has drifted past the rule meets it as a blocked commit, which is the
most expensive moment to first read it. It is resolved the same two ways this
skill is — `.agents/skills/cyclomatic-complexity/SKILL.md` first, then
`skills/cyclomatic-complexity/SKILL.md` — and is `[ -f ]`-guarded, so a port
that never installs it still re-grounds cleanly. Install it per SETUP.md step 3;
`kit/verify/export-gate.test.sh` fails the commit if this leaf injects a sibling
skill its own SETUP.md does not install. The payload assertions live in
`scripts/tests/smoke.sh` as the `COMPLEXITY-CANARY` case, checked for the
workstream and orchestrator roles.

It states that boot and harness setup already happened, so the resumed agent
does not restart, switch to a stale handoff, re-arm hooks, or perform a
file-reading orientation ritual. Everything required to resume the active phase
is injected. Later task-specific source inspection is normal work, not recovery.

The template sets `additionalContextLimit: 0` because the source contract requires whole reinjection. Keep the injected files short enough for the chosen model. If the binding set grows, split role references and reduce the pasted set before raising context further.

Set the source harness's effective compact trigger in project config:

```toml
model_auto_compact_token_limit = 297500
```

Only use this value for models with sufficient context. This config belongs in `.codex/config.toml`, not the hook file.

## 7. Builder stop and question channel

A non-interactive builder runs with the Codex config override
`approval_policy="never"`; execution failures return to the model instead of
opening an approval dialog. It must also avoid stopping merely to ask a question.

Use these files:

- `ASK-ORCH.md`: question, phase, `BLOCKING` or `PROCEEDING-ON-DEFAULT`, proposed default.
- `ORCH-ANSWER.md`: orchestrator response plus durable decision-log update.
- `NEEDS-HUMAN.md`: terminal human-only blocker.
- `HARNESS-BROKEN.marker`: terminal guard failure.
- `DONE.marker`: committed final completion signal.

The `Stop` hook continues a `stream/*` builder when its plan still has unchecked phase boxes and none of the terminal markers exists. It must not create an infinite loop: `stop_hook_active` allows one continuation at a time, and a real blocker marker permits stop.

## 8. Strand preflight

For each worktree, prove:

- cwd resolves inside the intended worktree;
- current branch equals the plan branch;
- `Run type` is valid;
- planning files exist;
- project `.codex/hooks.json` exists and includes required events;
- hooks were trusted or the specific vetted automation run uses the trust bypass;
- Probity config and guarded path are present;
- pre-commit, RoboRev git hooks, and push firewall are installed through `git rev-parse --git-path`;
- dependencies and toolchain commands work inside the worktree;
- live prove-NO and prove-YES succeed.

Run `cbr-codex.sh provision` and then the live probe. Guarded does not imply operable.

## Failure direction

| Failure | Direction |
|---|---|
| Optional UI/surfacing hook cannot reach RoboRev | fail open; clean gate remains the backstop |
| Session sweep cannot parse output | fail open and silent |
| Re-ground lacks jq or repo root | fail open; report during doctor |
| Probity rejects a production write | block |
| Probity config cannot load or verdict cannot be proved | block |
| Pre-commit check fails | block |
| RoboRev clean state cannot be proved | block |
| Status cannot prove a process live | report dead/unknown; never infer health |
| Closeout cannot prove no live owner or merged content | block destructive cleanup |
