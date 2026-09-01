> **PORTING APPLIED (reference host):** the "canonical" snippets below were written
> for the reference host's Python/uv toolchain. THIS repo's live gate is TS/pnpm: see the real
> `.pre-commit-config.yaml` (tsc -b + gitleaks, extended as tools
> land) and `.claude/hooks/roborev-gate.sh` (the LIVE hook is canonical over any
> snippet here). cbr.sh constants are already ported (sonnet-5, cockpit-*, pnpm).

# Claude Code agent-harness spec — verify or install each piece

Work top to bottom. For each piece: **run the Verify step first.** If it passes,
the piece is present and correct — move on. Only run Install/repair for what is
missing or wrong.

**Source of truth:** in an established repo, the _live_ files are canonical —
the real hook scripts under `.claude/hooks/`, the real `probity.config.ts`,
`.pre-commit-config.yaml`, and `.roborev.toml`. The scripts and configs shown
below are **minimal illustrations of the required behavior**, deliberately
stripped of comments. A live file will usually be _richer_ than the version here
(more comments, extra edge-case handling) — that is expected and **not** a reason
to change it. Verify that the live file does the right thing; only edit it if its
_behavior_ is actually wrong or missing. Never overwrite a working hook just to
make it match the shorter copy below. Use the copies below to install a piece
that is genuinely absent.

All hook scripts **fail open** (exit silently on any error) so a broken tool
never blocks work.

---

## 1. planning-with-files

The plan lives at `task_plan.md` (repo root); `findings.md` and `progress.md`
beside it. These planning artifacts carry real decisions (incl. the in-flight decision log) — commit them with the work, don't gitignore them.

- **Verify:** the planning-with-files skill is available, or `task_plan.md`
  exists at the repo root.
- **Install:** invoke the planning-with-files skill at the start of Phase 2.

---

## 2. Probity (TDD + naming guard, fires before every write)

- **Where:** `probity.config.ts` (repo root) + a PreToolUse hook in
  `.claude/settings.json` (matcher `Bash|Write|Edit`).
- **Verify:** `test -f probity.config.ts && echo ok`; and confirm the
  PreToolUse entry below is in `.claude/settings.json`.
- **Install:** create `probity.config.ts` (canonical content below) and add the
  PreToolUse hook entry (see the settings block at the bottom). The npx command
  pulls Probity fresh; no separate install.
- **Bricked / blocking everything?** If every Bash/Write/Edit returns `Probity:
Cannot find module '<x>'`, the config failed to _load_ and Probity fails **closed**
  — usually an unprovisioned worktree (no `node_modules`) after the config gained a
  top-level `import`. See the **`probity-doctor`** skill for the diagnosis + fix
  (`pnpm install` / `cbr.sh provision` from an external terminal — the session can't
  self-repair).

Canonical `probity.config.ts` (scoped to `packages/**/*.py`): enforce TDD, forbid
project-prefixed imports (`from myproj_X`), forbid jargon imports (`engine`,
`agent`). Adjust the `files` glob and the forbidden patterns to the project's
naming rules.

```ts
import { defineConfig, enforceTdd, forbidContentPattern } from '@nizos/probity'

const noProjectPrefix = forbidContentPattern({
  match: /\b(from|import)\s+myproj_\w+/,
  reason: 'Project-prefixed module names are forbidden. Drop the prefix — see AGENTS.md <naming>.',
})
const noJargonModuleNames = forbidContentPattern({
  match: /\b(from|import)\s+(engine|agent)\b/,
  reason: 'Use GLOSSARY vocabulary: "world" not "engine"; "hero" not "agent".',
})

export default defineConfig({
  rules: [
    { files: ['packages/**/*.py'], rules: [noProjectPrefix, noJargonModuleNames, enforceTdd()] },
  ],
})
```

---

> **Tool note:** Probity bites only as a Claude Code `PreToolUse` hook, and only on
> the files its `probity.config.ts` globs name — on a different agent harness it may
> not fire at all. Confirm it with the live probe, don't assume. See SETUP "Tool notes".

## 3. RoboRev (per-commit review, advises only)

Two wirings: a **git hook** triggers the review; a **Claude Code hook** wakes you
on a FAIL.

- **Where:** `.roborev.toml` (root) + git `post-commit`/`post-rewrite` hooks
  (installed by `roborev init`) + `.claude/hooks/roborev-gate.sh` + the
  PostToolUse entry in `.claude/settings.json`.
- **Verify:** `ls "$(git rev-parse --git-path hooks/post-commit)" "$(git rev-parse --git-path hooks/post-rewrite)"` exist (worktree-safe path — `.git` is a file in a worktree);
  `command -v roborev`; `test -f .claude/hooks/roborev-gate.sh`; PostToolUse
  entry present. Also confirm the gate's `rewakeMessage` carries the
  **close-discipline** (fix → close; wrong/intentional → respond + close; leave
  open only if deliberately deferred) — see the settings block below.
- **Install:** `roborev init` (writes the git hooks + `.roborev.toml`); create
  `.claude/hooks/roborev-gate.sh` (canonical below) and add the PostToolUse
  entry.

`roborev-gate.sh` — after a `git commit`, wait for that commit's review and
exit 2 (wake the agent) ONLY on a real FAIL; silent on pass / no-job / infra
error / already-gated. The wait is bounded by the hook's `timeout` in
settings.json (macOS ships no `timeout` binary).

```bash
#!/usr/bin/env bash
set -uo pipefail
payload="$(cat)"
case "$payload" in *"git commit"*) ;; *) exit 0 ;; esac
command -v roborev >/dev/null 2>&1 || exit 0
git_dir="$(git rev-parse --git-dir 2>/dev/null)" || exit 0
head_sha="$(git rev-parse HEAD 2>/dev/null)" || exit 0
state="$git_dir/roborev-gate-last-sha"
[ "$(cat "$state" 2>/dev/null || true)" = "$head_sha" ] && exit 0
if roborev wait -q "$head_sha" >/dev/null 2>&1; then printf '%s' "$head_sha" > "$state"; exit 0; fi
review="$(roborev show "$head_sha" 2>/dev/null)"
first_line="$(printf '%s\n' "$review" | head -1)"
if [ -z "$review" ] \
  || printf '%s\n' "$first_line" | grep -qiE '^error:|^no review found'; then
  printf '%s' "$head_sha" > "$state"; exit 0
fi
printf '%s' "$head_sha" > "$state"
printf '%s\n' "$review"
exit 2
```

**Handling a FAIL — always end by updating the review**, so an open FAIL always
means a real unresolved item (otherwise the session-sweep cries wolf):

- **fixed it** → `roborev respond <job> -m '...' && roborev close <job>`;
- **wrong / intentional / out of scope** → close-with-reason, same commands;
- **genuinely deferred, or needs the human** → leave it open (that is what
  "open" should mean).

Max 3 fix rounds TOTAL in the merge range (the merge gate counts review-fix commits; the escalation ruling is where chain judgment lives), then escalate or decline by judgment with recorded reasoning. Closing after a fix is the step most easily
forgotten; the session-sweep is the backstop that re-surfaces anything left
open at the next boot.

---

> **Tool note:** `roborev` sends PostHog telemetry to `us.i.posthog.com` by default.
> Disable it by launching the daemon with `TELEMETRY_ENABLED=0` (value **must** be `0`;
> `=false` is silently ignored). See SETUP "Tool notes".

## 4. Session sweep (lists open FAILs at boot)

- **Where:** `.claude/hooks/roborev-session-sweep.sh` + SessionStart entry.
- **Verify:** `test -f .claude/hooks/roborev-session-sweep.sh`; SessionStart
  entry present. Expect a boot line: `RoboRev gate armed. Open FAIL reviews: N.`
- **Install:** create the script (below) + add the SessionStart entry.

```bash
#!/usr/bin/env bash
set -uo pipefail
command -v roborev >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0
fails="$(roborev list --open --json --limit 50 2>/dev/null \
  | jq -r '[.[] | select(.verdict=="F")][:10][] | "Job #\(.id)  \(.git_ref[0:7])  \(.commit_subject)"' 2>/dev/null || true)"
count="$(printf '%s' "$fails" | grep -c . || true)"
liveness="RoboRev gate armed. Open FAIL reviews: ${count}."
if [ "${count:-0}" -eq 0 ] 2>/dev/null; then jq -n --arg msg "$liveness" '{systemMessage: $msg}'; exit 0; fi
ctx="RoboRev session sweep — ${count} open FAIL review(s) need action (fix / close-with-reason / surface):

${fails}"
jq -n --arg msg "$liveness" --arg ctx "$ctx" \
  '{systemMessage: $msg, hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
exit 0
```

---

## 5. pre-commit deterministic checks (ruff format + lint + mypy + tests, BLOCKS)

The piece most often present-but-not-armed. The config file can exist while the
git hook is not installed.

- **Where:** `.pre-commit-config.yaml` (root) + `.git/hooks/pre-commit`.
- **Verify:** `test -f "$(git rev-parse --git-path hooks/pre-commit)" && echo armed || echo NOT-armed`. Use `git rev-parse --git-path`, never a literal `.git/hooks/...` — in a worktree `.git` is a _file_, so a literal path falsely reports "NOT-armed" even though the (shared) hook is armed. Also confirm the config carries every check, not just that the hook is armed — in particular `grep -q 'ruff format' .pre-commit-config.yaml` (a config with only lint/mypy/tests is silently missing the formatter).
- **Install/arm:** `uv run pre-commit install` (writes `.git/hooks/pre-commit`).
  If `.pre-commit-config.yaml` is missing, create it (canonical below; adjust the
  paths to the project's packages).

```yaml
repos:
  - repo: local
    hooks:
      - id: ruff-format
        name: ruff (format check)
        entry: uv run ruff format --check packages/
        language: system
        pass_filenames: false
        always_run: true
      - id: ruff
        name: ruff (lint)
        entry: uv run ruff check packages/
        language: system
        pass_filenames: false
        always_run: true
      - id: mypy
        name: mypy (types)
        entry: uv run mypy packages/world/src/world packages/heroes/src/heroes
        language: system
        pass_filenames: false
        always_run: true
      - id: pytest
        name: pytest (tests)
        entry: uv run pytest packages/heroes/tests packages/world/tests
        language: system
        pass_filenames: false
        always_run: true
```

Per-commit reviews are ADVISORY (2026-08-31 cadence move): commits are never
held for a review, and the blocking check is the merge-path review gate — a
merge with open blocking findings on the merged branch refuses. The retired
`roborev-clean` commit gate (mechanical 2026-06-12 → 2026-08-31) lives in git
history if a port wants the old cadence back.

These are deterministic facts, so they are allowed to block. A rare false
positive gets a conscious inline suppression (`# type: ignore[...]`,
`# noqa: ...`), never `--no-verify`.

The formatter is `--check` (verify-only), not an in-place rewrite — the gate
reports facts and blocks, it never silently edits your files, symmetric with
the other three. When _adopting_ the formatter on a repo that has pre-existing
unformatted code, run `uv run ruff format packages/` once and commit that tidy
on its own first; otherwise the next commit blocks on legacy formatting.

---

## 6. Post-compaction re-ground (the lifeline)

- **Where:** `.claude/hooks/post-compact-reground.sh` + a **SessionStart** entry
  with `matcher: "compact"` (NOT a `PostCompact` entry — see "Why
  SessionStart/`compact`, not `PostCompact`" below).
- **What it injects (COMPOSED, role-aware).** The payload is composed from the
  leaf's `references/` tree, never a single pasted file:
  - the repo's binding docs (the `PRINCIPLE_DOCS` + `ROUTING_DOC` porting
    knobs; in this repo CONSTITUTION, ENGINEERING, VISION, AGENTS.md), whole;
  - the router `SKILL.md`, unconditionally;
  - when a `task_plan.md` exists (a build is in progress): the core law files
    for **exactly the plan's role** — `references/core/`
    policy/strand/reviews/judgment always, plus fleet mode for an
    orchestrator plan or build-loop+solo for a workstream plan (role read from
    the plan's `**Run type:**` line; workstream when absent/unknown) — then
    `references/claude.md`, the TDD skill, and the plan trio
    (task_plan/findings/progress), whole. Missing files are skipped silently.
- **Verify:** run the script and count the anchored section headers:
  `bash .claude/hooks/post-compact-reground.sh | jq -r '.hookSpecificOutput.additionalContext' | grep -c '^=== '`
  Assert the **live** section count against the files that actually exist —
  never a hard-coded number (acceptance row C1); with this repo's full doc set
  and a workstream plan the current count is 16. Grep the anchored `=== `
  headers, not bare substrings (the injected docs mention their own names many
  times). Role-awareness (C2) is pinned by `kit/verify/reground-gate.test.sh`
  (run by pre-commit whenever the hook or the gate test changes): orchestrator
  plans must NOT receive build-loop/solo, workstream plans must NOT receive
  fleet, and an oversized plan trio must still emit valid JSON (the
  payload goes to jq via stdin, never as an argument — ARG_MAX).
- **Install/repair:** the canonical script is
  `templates/hooks/post-compact-reground.sh` in this skill folder — copy it to
  `.claude/hooks/` and edit only the PORTING block at the top (binding-doc
  names, skill path, `HANDOFF_GUARD`). The live hook and the template must stay
  byte-identical apart from nothing at all — this repo keeps them in lockstep
  (`diff .claude/hooks/post-compact-reground.sh skills/claude-controlled-build-run/templates/hooks/post-compact-reground.sh`).
  Confirm it reads `task_plan.md` at the repo root — the path
  planning-with-files uses — so it re-grounds on **this run's plan**. Larger
  contextual documents (a glossary, contracts) stay pointed-at, never pasted.

**Why `SessionStart`/`compact`, not `PostCompact`.** `PostCompact` is a real hook
event, but it is **observability-only** — its stdout goes to the debug log and is
**never injected into context**, so a reground wired there fires and accomplishes
nothing (the symptom: after a compaction the rules and plan are _not_ back in
context, and a fresh-feeling agent has to re-read the skill by hand). The event
that actually re-injects is **`SessionStart`**, whose `additionalContext` _is_
added to context. An auto-compaction ends by starting a fresh session with
`source = compact`, so a `SessionStart` hook with `matcher: "compact"` fires
exactly — and only — then. Two consequences: (1) the `hookEventName` in the
script's JSON output must be `"SessionStart"` (it has to match the firing event,
not the colloquial "post-compaction" label), and (2) the session-sweep (piece 4)
is a _second_ `SessionStart` hook with no matcher, so it runs on every start; the
two coexist as separate `SessionStart` groups.

**Porting caveat — the `HANDOFF_GUARD` knob.** The extra "do NOT switch to the
newest handoff" sentence exists for repos whose routing doc contains a boot
ritual that tells the agent to read a newest handoff — the hook re-injects that
doc whole, which would otherwise pull a mid-run agent onto a prior session's
priorities. The template gates that sentence behind `HANDOFF_GUARD` in its
PORTING block: set it to `1` only in such a repo (the reference host was one, and paired it
with a matching guard in its own `AGENTS.md`). This repo's `AGENTS.md` has no
handoff-reading boot ritual, so the live hook runs `HANDOFF_GUARD=0`.

---

## 7. Worktree-local operability allowlist (`settings.local.json`)

**The live dispatch runs `--dangerously-skip-permissions`, so this allowlist is now a
FALLBACK** — for an attended run, or if you deliberately drop back to `--permission-mode
auto`; under skip-permissions it is inert (there is no prompt layer to satisfy). It is
kept because it documents _why_ the permission layer cannot gate an unattended builder —
the lesson that forced skip-permissions (see `references/claude.md` §dispatch). The
builders are `claude --bg` sessions parented to the supervisor daemon (on-plan, real
session roots), NOT `claude -p` and NOT tmux (impossible — the Bash tool has no pty).
Under `--permission-mode auto`, the layer runs only what this list matches
and **prompts on everything else** — and with no human
at the pane, a prompt is a silent hang. That includes _read-only_ commands you'd
think are safe: `git ls-files`, `git check-ignore`, a compound `a; b`, a seeded
probe `CLAW_WORLD_SEED=… uv run …` (the env prefix breaks the `uv run` match) all
stalled a live builder (S4+S5, 2026-06-20). So the list must cover the builder's
real read-only surface, not just its writes. It does **not** weaken Probity:
Probity is a PreToolUse hook that fires regardless of the permission layer, so
untested prod edits stay blocked — the gates are the boundary, the allowlist only
keeps an unattended session from hanging on a safe op.

- **Where:** `.claude/settings.local.json` at the worktree root. It is gitignored
  (worktree-scoped, never committed) — confirm with `git check-ignore
.claude/settings.local.json`.
- **Verify:** `test -f .claude/settings.local.json && echo ok`, then a live probe
  — a `uv --version` and a throwaway `Write` you delete must both report
  _permitted_ (see the prove-YES step in `references/core/strand.md`).
- **Canonical contents** (scope each `Bash` entry to its tool — never `Bash(*)`):

```json
{
  "worktree": { "bgIsolation": "none" },
  "permissions": {
    "allow": [
      "Edit",
      "Write",
      "MultiEdit",
      "Bash(uv --version:*)",
      "Bash(uv run:*)",
      "Bash(uv sync:*)",
      "Bash(roborev:*)",
      "Bash(git add:*)",
      "Bash(git commit:*)",
      "Bash(git status:*)",
      "Bash(git diff:*)",
      "Bash(git log:*)",
      "Bash(git show:*)",
      "Bash(git rev-parse:*)",
      "Bash(git ls-files:*)",
      "Bash(git check-ignore:*)",
      "Bash(git branch:*)",
      "Bash(git rev-list:*)",
      "Bash(git worktree list:*)",
      "Bash(ls:*)",
      "Bash(cat:*)",
      "Bash(grep:*)",
      "Bash(rg:*)",
      "Bash(find:*)",
      "Bash(head:*)",
      "Bash(tail:*)",
      "Bash(wc:*)",
      "Bash(sleep:*)",
      "Bash(echo:*)"
    ]
  }
}
```

The write/commit rules stay narrow (Probity + pre-commit do the enforcing there);
the read-only git + fs verbs are broad-but-safe so the unattended session never
hangs on inspection. `sleep`/`echo` are there for the per-commit RoboRev wait —
the builder polls with an `until roborev show … ; do sleep 5; done; echo …` loop,
and a compound stalls unless EVERY sub-command is allowlisted (observed: S5 hung
~11 min on this after each commit, unable to read+close its own review). The session itself appends a `"don't ask again"` rule to this
file when a human picks option 2 at a prompt — so it is read **and written** live,
which means editing it mid-run takes effect without a restart. Env-prefixed forms
(`CLAW_WORLD_SEED="…" uv run *`) need their own entry — a `Bash(uv run:*)` rule
won't match a command that starts with the env assignment.

The `"worktree": {"bgIsolation": "none"}` key is what lets a `claude --bg` builder
edit its provisioned worktree directly. A background session otherwise refuses to
touch the shared checkout until it calls `EnterWorktree` ("hasn't isolated its
changes yet…"); since `cbr.sh provision` already created the worktree the builder
runs in, that guard would be a dead-end, so it is turned off per-worktree. This does
NOT loosen the real fences: Probity (folder-scoped) and the merge-path review
gate (branch-scoped) are unchanged — it only suppresses the redundant self-isolation step.

Dispatch caveats: (1) pass `--model` a real model id (e.g. `claude-opus-4-8`),
never a friendly alias, and never rely on the `.claude/settings.json` default — it
may be a model the account can't currently use (e.g. `claude-fable-5`). (2) A
session can show a one-time workspace-trust prompt (`Yes, I trust this folder`) that
stalls until answered — and a `claude --bg` session has no pane to send-keys into,
so it can't be rescued after the fact. Trust is repo-keyed (shared `.git`), not
path-keyed, so a worktree of an already-trusted repo — the normal case — shows no
prompt at all. The invariant is therefore **dispatch only into an already-trusted
repo** (the reference repo is trusted). If a `--bg` builder is nonetheless stuck (`cbr.sh status`
shows `state=blocked`), stop it and re-dispatch from a trusted path; there is no
send-keys fix. Trust state lives in `~/.claude.json`
(`projects[<path>].hasTrustDialogAccepted`).

## 8. AskUserQuestion guard (headless builders must not freeze, BLOCKS)

A headless `--bg` builder that calls `AskUserQuestion` freezes indefinitely — no
human watches its prompt, and the orchestrator cannot answer an app-modal dialog
from outside (one builder sat ~16 min on it). The guard denies the tool for builders
and redirects them to the `ASK-ORCH.md` file channel (see `references/core/judgment.md` "Resolving a
judgment call"). It is scoped to builders by the same `stream/*` branch signal the
push firewall uses, so the orchestrator (`integration/*`) keeps `AskUserQuestion`.

- **Where:** `.claude/hooks/no-interactive-ask.sh` + a PreToolUse entry in
  `.claude/settings.json` with `matcher: "AskUserQuestion"`.
- **Verify:** `test -x .claude/hooks/no-interactive-ask.sh`; the PreToolUse
  `AskUserQuestion` block is present (`cbr.sh doctor` checks both — the script is in
  the executable-hook loop and the block is in `missing_hook_wiring`'s `need` list).
  Behavior check: on a `stream/*` branch the hook exits 2 with the redirect message;
  on any other branch it exits 0 silently.
- **Install:** create the script (branch-scoped `case` on
  `git rev-parse --abbrev-ref HEAD`; `exit 2` on `stream/*`, else `exit 0`) + add the
  PreToolUse entry. `cbr.sh arm` installs it via its `put` list; `provision` refuses
  to arm a worktree whose settings lack the block.

---

## The `.claude/settings.json` hooks block

All five Claude Code hook scripts live here, across three events — the reground
shares the `SessionStart` event with the session-sweep (it is a _second_
`SessionStart` group with `matcher: "compact"`), and is **not** a `PostCompact`
hook. Two PreToolUse entries fire: Probity (`Bash|Write|Edit`) and the
`no-interactive-ask` guard (`AskUserQuestion`). Merge these entries (don't drop
existing unrelated hooks). `asyncRewake` on the RoboRev gate is what lets a FAIL wake
the agent; the `timeout` bounds the wait.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|Write|Edit",
        "hooks": [{ "type": "command", "command": "npx --yes @nizos/probity --agent claude-code" }]
      },
      {
        "matcher": "AskUserQuestion",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/no-interactive-ask.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/roborev-gate.sh",
            "asyncRewake": true,
            "timeout": 300,
            "rewakeMessage": "RoboRev flagged the last commit (FAIL) - ADVISORY under the PR-boundary cadence: read the finding now; fix now only if a later commit would compound it, otherwise carry it to the PR boundary, where the branch review is the sole source of actionable findings and every open job gets an explicit disposition. Round cap: 3 fix rounds TOTAL in the merge range, then stop fixing: escalate, decline by judgment with recorded reasoning surfaced to the human, or record an escalation ruling. Finding follows:",
            "rewakeSummary": "RoboRev FAIL on last commit"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/roborev-session-sweep.sh",
            "timeout": 30
          }
        ]
      },
      {
        "matcher": "compact",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/post-compact-reground.sh",
            "timeout": 15
          }
        ]
      }
    ]
  }
}
```

After editing `.claude/settings.json`, a one-time `/hooks` reload may be needed
if the settings watcher doesn't auto-arm the new hooks.
