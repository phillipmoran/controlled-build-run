---
name: claude-controlled-build-run
description: >-
  Controlled Build Run (CBR) keeps long coding sessions on the rails: a
  written plan drives the work, automated checks and reviewer agents inspect
  the code at every step, and re-injected context after memory compaction
  keeps the session from losing the plot. It scales from a single builder to
  an orchestrator running parallel builders. Use it to plan and build anything non-trivial.
---

> **PORTING APPLIED (reference host, 2026-07-02):** this skill text was written in
> the reference host. In THIS repo read its host names as: CONSTITUTION.md/GLOSSARY.md
> -> (none; ENGINEERING.md + AGENTS.md + VISION.md are the binding docs) ·
> packages/player-view-web -> the pnpm workspace root (WEB_PKG=".") · <repo>-<slug>
> worktrees -> cockpit-<slug> · uv/pytest/ruff/mypy -> pnpm/vitest/eslint/prettier/tsc ·
> builder model dial -> claude-sonnet-5 @ medium (operator-set in the machine-2 resume
> handoff, superseding the fable-5 dial from earlier that day; the v1 build ran Sonnet 5 @ high).
> cbr.sh in this folder already carries these constants. The dispatcher's watcher
> is scripts/captain-watch.sh (ported, same cockpit-<slug> mapping; the name
> predates the captain tier's 2026-08-31 retirement); blocker
> files in this repo are NEEDS-OPERATOR.md + CONTROL-PLANE-BROKEN.marker + DONE-<branch>.marker
> at the worktree root, as the fleet task_plan.md specifies.

# Controlled Build Run (Claude router)

Treat this file as the Claude provider router. Set `CBR_CORE` to the repository's
`skills/cbr-core/` directory when it exists; otherwise use this leaf's
`references/core/` snapshot. Claude-specific mechanics live in
`references/claude.md`, `references/agent-harness-spec.md`, and this leaf's scripts
and templates. Never replace the routed law with a summary from memory.

## What this gives you

A build that runs off a **written plan**, with **automatic checks** and
**drift-proof hooks**, so even a long or unattended run stays honest. The plan
holds the decisions; the checks catch mistakes; the hooks re-ground you when
your memory gets squished. None of it depends on you _remembering_ to be
disciplined — the control plane does that.

Two jobs, in order: **(1) verify/wire the control plane**, then **(2) run the loop**.

## Route the law before acting

Read these shared files for every controlled build, in order:

1. `$CBR_CORE/policy.md` — the checks, what may block, why
2. `$CBR_CORE/strand.md` — one branch ↔ one plan ↔ one folder ↔ one session
3. `$CBR_CORE/reviews.md` — per-commit review, phase checkpoints, closeout
4. `$CBR_CORE/judgment.md` — triage, panels, ratification, plan altitude
5. `$CBR_CORE/GLOSSARY.md` — the control plane's own words; use them exactly

Then select the current role from the active `task_plan.md`'s `**Run type:**`
line and branch:

- **Workstream/builder:** read `$CBR_CORE/build-loop.md`. When this is a
  solo strand rather than a `stream/*` fleet builder, also read
  `$CBR_CORE/modes/solo.md`. Do not load fleet mode into a workstream.
- **Orchestrator:** read `$CBR_CORE/modes/fleet.md` (its watcher-law
  section carries the retired captain tier's folded duties). Do not load the
  builder TDD loop or solo mode into an orchestrator payload.

For every role, read `references/claude.md` — the Claude provider adapter: how
each core mechanism binds to this agent harness (hooks, Probity, RoboRev, cbr.sh,
`claude --bg` dispatch, the model dial, subagent coverage). For control-plane setup
or repair, work through `references/agent-harness-spec.md` completely before changing
a hook or config. For porting to another repo, read `PORTING.md`; for the
plain-words tour of the pieces, `SETUP.md`. Acceptance is the verify battery
(`kit/verify/`) plus the Claude mechanical rows in
`references/acceptance-checklist.md`.

## Verify or wire the control plane first (CHECK BEFORE YOU CLOBBER)

Most pieces already exist in an armed repo. For each piece: check if it's
present first; if it is, confirm it matches the spec and move on — never
blindly overwrite a working hook. Only install what is missing or wrong. The
exact contents, verify commands, and install steps are in
`references/agent-harness-spec.md` (§1–§8). The pieces:

1. **planning-with-files** — the plan lives in `task_plan.md` at the worktree root.
2. **Probity** — `probity.config.ts` + the PreToolUse hook: watched-fail TDD
   before any production write. If it is blocking every call or the config
   won't load, use the `probity-doctor` skill (config-load fails closed; the
   usual cause is an unprovisioned worktree).
3. **RoboRev** — `.roborev.toml` + git post-commit/post-rewrite hooks + the
   PostToolUse gate that wakes you on a FAIL.
4. **Session sweep** — SessionStart hook listing open FAIL reviews at boot.
5. **pre-commit deterministic checks** — format, lint, types, tests
   (per-commit reviews are advisory; the blocking review check rides the
   merge path). Most often present-but-not-armed: check
   `.git/hooks/pre-commit`, and note gate inheritance — a branch cut before a
   gate existed doesn't carry it (`$CBR_CORE/policy.md`).
6. **Post-compaction re-ground** — `.claude/hooks/post-compact-reground.sh`,
   wired as a **SessionStart** hook with `matcher: "compact"` (NOT `PostCompact`,
   which is log-only and cannot inject). The lifeline of a long run: it
   re-injects the binding docs, this router, the role-matched core law files,
   `references/claude.md`, the TDD skill, and the plan trio — whole. Spec §6.

The fail-open/fail-closed line, the compaction-window triple (350k @ 0.85),
and the blocking table live in `$CBR_CORE/policy.md` and
`references/claude.md`; `cbr.sh doctor` proves the armed state before every
build.

## Run one strand from files

Every non-trivial plan gets its own worktree on its own branch, with the build
session rooted in that worktree — the control plane binds to a _folder_, so a
misrooted session guards and re-grounds the wrong plan. `cbr.sh provision
<slug> <branch>` builds the strand (worktree + link-only deps + allowlist +
armed-checks); the policy and the by-hand steps are
`$CBR_CORE/strand.md`, with the Claude mechanics (trust gate, settings,
the live Probity probe you run in-session regardless) in
`references/claude.md`.

Every session open, and after every compaction: confirm
`git branch --show-current` matches the plan's `**Branch:**` line AND Probity
blocks an untested guarded write. Either failing means you're in the wrong
place — stop, don't build.

For each behavior: green baseline, one failing test watched red for the right
reason, minimal green implementation, gates, plan checkbox moved **in the same
commit**, commit small and often — that is LAW, not a preference. Handle every
RoboRev finding by the merge boundary: per-commit reviews are advisory in
the moment, but the merge-path review gate refuses a merge with open blocking
findings, so respond + close them at the PR boundary; re-run crashed reviews,
never skip; 3 review-fix commits TOTAL in the merge range, then escalate or decline by
judgment (see `$CBR_CORE/build-loop.md`). Full loop:
`$CBR_CORE/build-loop.md`; Probity gotchas and the honest unlocks:
`references/claude.md`.

At each plan phase boundary, run the independent read-only checkpoint review
from `$CBR_CORE/reviews.md` and stamp the exact reviewed SHA in the
plan's phase-checkpoint table. Render and eyeball a golden sample whenever a
human or model will read the output.

## Judgment calls and fleets

- A mid-build question is triaged, not auto-escalated: settled/trivial →
  decide and move on; engineering fork → panel; vision or scope → the human,
  recommendation attached. `$CBR_CORE/judgment.md`.
- A headless builder never blocks on an interactive prompt — the
  `no-interactive-ask` hook denies `AskUserQuestion` on `stream/*` branches and
  redirects to the `ASK-ORCH.md`/`ORCH-ANSWER.md` file channel.
- An orchestrator is its own strand on an integration branch; the fleet plan
  holds the dependency graph; dispatch is a topological sweep; every stream
  plan passes the plan-review gate before launch; the live post-merge smoke
  and the closeout ritual are mandatory merge-gate steps.
  `$CBR_CORE/modes/fleet.md`.

## Dispatch through the fixed rail

Builders are real, independent session roots — **on-plan** (`claude --bg`,
never off-plan `claude -p`/Agent SDK), **detached** (parented to the
supervisor daemon), **watched from outside** (ground-truth liveness; silence
is an alarm). Never use an in-session subagent as a production writer in
another worktree — Probity gates only the session's own root. The mechanics,
the proven dead ends, and the trust/permission gates are in
`references/claude.md`; the lifecycle commands are one script:

- `scripts/cbr.sh arm <repo>` — once per repo: control plane, never clobber
- `scripts/cbr.sh doctor` — the pre-flight; run before EVERY build
- `scripts/cbr.sh provision <slug> <branch>` — birth ritual for a strand
- `scripts/cbr.sh launch <slug> --prompt-file <f>` — on-plan `--bg` dispatch
- `scripts/cbr.sh watch <slug>` — REQUIRED right after launch
- `scripts/cbr.sh status <slug>` / `fleet` — outside-view liveness facts
- `scripts/cbr.sh closeout <slug> [--into <branch>]` — death ritual at merge
- `scripts/cbr.sh janitor` — on-demand leak audit (merged-but-unreaped
  worktrees + reap commands, orphan branches, stale watch files); a human
  approves each reap; `doctor` runs its merged-worktree half last, non-gating

Each subcommand gathers facts, runs the fixed sequence, and decides nothing.
Always pass `--model`/`--effort` from the model dial (in
`references/claude.md`) and surface them to the human before launch.

## Files are the letter, messaging is the doorbell

Claude sessions can message each other (`ListAgents` / `SendMessage`), and a
`--bg` builder can too. Everything that must survive — plan, scope, decisions,
asks and answers, readback, blockers — still goes in a **file in the worktree**;
a message is a notification that a file changed, never the instruction itself,
never proof of receipt, and never a source of authority. Probed live
2026-08-19; the observed behavior and the full doctrine are in
`references/claude.md` §9, the transcript in
`docs/streams/evidence/2026-08-19-cross-session-messaging-probe.md`.

## Resume after compaction without re-booting

The re-ground hook injects the binding docs, this router, the shared core law
for exactly your role, `references/claude.md`, the TDD skill, and the plan
trio. It states that boot and control-plane setup already happened: continue from
the plan's current phase immediately — no boot ritual, no re-wiring, no
recovery-time reading ritual. Task-specific source inspection afterward is
normal work.

## Non-negotiable laws (carried here; detail in the routed files)

- **Deterministic facts may gate; fallible judgment may only surface.**
- **One strand per build** — branch, plan, folder, session; misrooted = stop.
- **Watched-fail test first** for every production change; no shape-only steps.
- **Commit small and often; the plan checkbox rides the same commit.**
- **Every review responded + closed by the PR boundary; zero open blocking
  findings is a hard merge gate** (merge-review-gate.sh), verified in the
  daemon, never inferred. Per-commit reviews are advisory in the moment.
- **Probity-exempt zones are declared up front with a named substitute proof**
  — never widened mid-run by a builder.
- **The live post-merge smoke and the closeout ritual are mandatory merge-gate
  steps**; unit-green ≠ product-works.
- **Never push, deploy, cross a ratification gate, or delete ambiguous work
  without the human's explicit sign-off.** Real WIP goes to the operator before it dies.

## The honest gap this skill closes

Without it, the plan and the checks are stitched together by hand: the agent
has to _remember_ to run the gates, commit often, and keep the plan alive
across compactions. This control plane does the remembering — verify it once, then
the hooks fire on their own and the plan re-grounds you automatically.
