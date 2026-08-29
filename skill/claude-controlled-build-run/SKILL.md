---
name: claude-controlled-build-run
description: >-
  Controlled Build Run (CBR) keeps long coding sessions on the rails: a
  written plan drives the work, automated checks and reviewer agents inspect
  the code at every step, and re-injected context after memory compaction
  keeps the session from losing the plot. It scales from a single builder to
  an orchestrator running parallel builders, up to a captain overseeing
  several orchestrators. Use it to plan and build anything non-trivial.
---

> **PORTING HEADER (fill in per host — see `PORTING.md`):** this skill text and
> its scripts name a few host-specific constants. As shipped, the reference
> values are: binding docs -> your repo's short "how we build" docs (e.g.
> ENGINEERING.md + AGENTS.md; the reground hook injects only docs that exist) ·
> WEB_PKG -> the package whose node_modules provision links ("." = repo root) ·
> worktree prefix -> sibling `../cockpit-<slug>` (rename to `../<repo>-<slug>`
> per host) · toolchain -> pnpm/vitest/eslint/prettier/tsc (swap for yours) ·
> builder model dial -> claude-sonnet-5 @ medium (operator-set; pick a model
> your account can run). cbr.sh in this folder carries these constants — edit
> them per `PORTING.md`, then rewrite this header to record YOUR host's values.
> The captain's watcher is scripts/captain-watch.sh (same worktree mapping);
> blocker files are NEEDS-OPERATOR.md + HARNESS-BROKEN.marker + DONE.marker at
> the worktree root.

# Controlled Build Run (Claude router)

Treat this file as the Claude provider router. The complete process law lives
in the byte-exact shared-core snapshot under `references/core/` (hash-gated
against `skills/cbr-core/`); Claude-specific mechanics live in
`references/claude.md`, `references/harness-spec.md`, and this leaf's scripts
and templates. Never replace the routed law with a summary from memory.

## What this gives you

A build that runs off a **written plan**, with **automatic checks** and
**drift-proof hooks**, so even a long or unattended run stays honest. The plan
holds the decisions; the checks catch mistakes; the hooks re-ground you when
your memory gets squished. None of it depends on you *remembering* to be
disciplined — the harness does that.

Two jobs, in order: **(1) verify/wire the harness**, then **(2) run the loop**.

## Route the law before acting

Read these shared files for every controlled build, in order:

1. `references/core/policy.md` — the checks, what may block, why
2. `references/core/strand.md` — one branch ↔ one plan ↔ one folder ↔ one session
3. `references/core/reviews.md` — per-commit review, phase checkpoints, closeout
4. `references/core/judgment.md` — triage, panels, ratification, plan altitude
5. `references/core/GLOSSARY.md` — the harness's own words; use them exactly

Then select the current role from the active `task_plan.md`'s `**Run type:**`
line and branch:

- **Workstream/builder:** read `references/core/build-loop.md`. When this is a
  solo strand rather than a `stream/*` fleet builder, also read
  `references/core/modes/solo.md`. Do not load fleet or captain mode into a
  workstream.
- **Orchestrator:** read `references/core/modes/fleet.md`. Do not load the
  builder TDD loop or solo mode into an orchestrator payload. (The re-ground
  hook deliberately also injects captain mode to an orchestrator — the tier
  above is its escalation seam, and a captain session, having no plan of its
  own, is never re-grounded role material; plan-locked at P-A, diverging from
  the Codex leaf on purpose.)
- **Captain:** read `references/core/modes/captain.md` plus the dispatch and
  watcher sections of `references/claude.md`. A captain watches and relays; it
  does not build or merge.

For every role, read `references/claude.md` — the Claude provider adapter: how
each core mechanism binds to this harness (hooks, Probity, RoboRev, cbr.sh,
`claude --bg` dispatch, the model dial, subagent coverage). For harness setup
or repair, work through `references/harness-spec.md` completely before changing
a hook or config. For porting to another repo, read `PORTING.md`; for the
plain-words tour of the pieces, `SETUP.md`. For acceptance, combine
`references/core/acceptance/checklist.md`, `scenarios.md`, and `mutations.md`
with the Claude mechanical rows in `references/acceptance-checklist.md`.

## Verify or wire the harness first (CHECK BEFORE YOU CLOBBER)

Most pieces already exist in an armed repo. For each piece: check if it's
present first; if it is, confirm it matches the spec and move on — never
blindly overwrite a working hook. Only install what is missing or wrong. The
exact contents, verify commands, and install steps are in
`references/harness-spec.md` (§1–§8). The pieces:

1. **planning-with-files** — the plan lives in `task_plan.md` at the worktree root.
2. **Probity** — `probity.config.ts` + the PreToolUse hook: watched-fail TDD
   before any production write. If it is blocking every call or the config
   won't load, use the `probity-doctor` skill (config-load fails closed; the
   usual cause is an unprovisioned worktree).
3. **RoboRev** — `.roborev.toml` + git post-commit/post-rewrite hooks + the
   PostToolUse gate that wakes you on a FAIL.
4. **Session sweep** — SessionStart hook listing open FAIL reviews at boot.
5. **pre-commit deterministic checks** — format, lint, types, tests, plus the
   `roborev-clean` gate (blocks a commit while any review on the branch is
   open, queued, or running). Most often present-but-not-armed: check
   `.git/hooks/pre-commit`, and note gate inheritance — a branch cut before a
   gate existed doesn't carry it (`references/core/policy.md`).
6. **Post-compaction re-ground** — `.claude/hooks/post-compact-reground.sh`,
   wired as a **SessionStart** hook with `matcher: "compact"` (NOT `PostCompact`,
   which is log-only and cannot inject). The lifeline of a long run: it
   re-injects the binding docs, this router, the role-matched core law files,
   `references/claude.md`, the TDD skill, and the plan trio — whole. Spec §6.

The fail-open/fail-closed line, the compaction-window triple (350k @ 0.85),
and the blocking table live in `references/core/policy.md` and
`references/claude.md`; `cbr.sh doctor` proves the armed state before every
build.

## Run one strand from files

Every non-trivial plan gets its own worktree on its own branch, with the build
session rooted in that worktree — the harness binds to a *folder*, so a
misrooted session guards and re-grounds the wrong plan. `cbr.sh provision
<slug> <branch>` builds the strand (worktree + link-only deps + allowlist +
armed-checks); the policy and the by-hand steps are
`references/core/strand.md`, with the Claude mechanics (trust gate, settings,
the live Probity probe you run in-session regardless) in
`references/claude.md`.

Every session open, and after every compaction: confirm
`git branch --show-current` matches the plan's `**Branch:**` line AND Probity
blocks an untested guarded write. Either failing means you're in the wrong
place — stop, don't build.

For each behavior: green baseline, one failing test watched red for the right
reason, minimal green implementation, gates, plan checkbox moved **in the same
commit**, commit small and often — that is LAW, not a preference. Handle every
RoboRev finding and then `roborev respond` + `roborev close` before the next
commit (the roborev-clean gate enforces it); re-run crashed reviews, never
skip; ~2 fix rounds per finding-surface or ~5 infra crashes, then escalate
or decline by judgment (see references/core/build-loop.md). Full loop:
`references/core/build-loop.md`; Probity gotchas and the honest unlocks:
`references/claude.md`.

At each plan phase boundary, run the independent read-only checkpoint review
from `references/core/reviews.md` and stamp the exact reviewed SHA in the
plan's phase-checkpoint table. Render and eyeball a golden sample whenever a
human or model will read the output.

## Judgment calls, fleets, captains

- A mid-build question is triaged, not auto-escalated: settled/trivial →
  decide and move on; engineering fork → panel; vision or scope → the human,
  recommendation attached. `references/core/judgment.md`.
- A headless builder never blocks on an interactive prompt — the
  `no-interactive-ask` hook denies `AskUserQuestion` on `stream/*` branches and
  redirects to the `ASK-ORCH.md`/`ORCH-ANSWER.md` file channel.
- An orchestrator is its own strand on an integration branch; the fleet plan
  holds the dependency graph; dispatch is a topological sweep; every stream
  plan passes the plan-review gate before launch; the live post-merge smoke
  and the closeout ritual are mandatory merge-gate steps.
  `references/core/modes/fleet.md`.
- The captain tier (N orchestrators, one human seam) watches files, never
  transcripts. `references/core/modes/captain.md`.

## Dispatch through the fixed rail

Builders are real, independent session roots — **on-plan** (`claude --bg`,
never off-plan `claude -p`/Agent SDK), **detached** (parented to the
supervisor daemon), **watched from outside** (ground-truth liveness; silence
is an alarm). Never use an in-session subagent as a production writer in
another worktree — Probity gates only the session's own root. The mechanics,
the proven dead ends, and the trust/permission gates are in
`references/claude.md`; the lifecycle commands are one script:

- `scripts/cbr.sh arm <repo>` — once per repo: scaffold, never clobber
- `scripts/cbr.sh doctor` — the pre-flight; run before EVERY build
- `scripts/cbr.sh provision <slug> <branch>` — birth ritual for a strand
- `scripts/cbr.sh launch <slug> --prompt-file <f>` — on-plan `--bg` dispatch
- `scripts/cbr.sh watch <slug>` (then `--watchdog --cycle <id>` from the
  watcher's armed line) — REQUIRED right after launch, watcher first
- `scripts/cbr.sh status <slug>` / `fleet` — outside-view liveness facts
- `scripts/cbr.sh closeout <slug> [--into <branch>]` — death ritual at merge
- `scripts/cbr.sh janitor` — on-demand leak audit; a human approves each reap
- `scripts/cbr.sh closeout-pending` — WARN-only: worktrees whose branch is
  merged but never reaped (also run as `doctor`'s last, non-gating step)
- `scripts/cbr.sh readback <slug>` — is the builder's readback in
  `progress.md`? (presence only; also in `status`'s SUMMARY, never gating)

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
trio. It states that boot and harness setup already happened: continue from
the plan's current phase immediately — no boot ritual, no re-wiring, no
recovery-time reading ritual. Task-specific source inspection afterward is
normal work.

## Non-negotiable laws (carried here; detail in the routed files)

- **Deterministic facts may gate; fallible judgment may only surface.**
- **One strand per build** — branch, plan, folder, session; misrooted = stop.
- **Watched-fail test first** for every production change; no shape-only steps.
- **Commit small and often; the plan checkbox rides the same commit.**
- **Every review responded + closed before the next commit; zero open reviews
  is a hard merge gate**, verified in the daemon, never inferred.
- **Probity-exempt zones are declared up front with a named substitute proof**
  — never widened mid-run by a builder.
- **The live post-merge smoke and the closeout ritual are mandatory merge-gate
  steps**; unit-green ≠ product-works.
- **Never push, deploy, cross a ratification gate, or delete ambiguous work
  without the human's explicit sign-off.** Real WIP goes to the operator before it dies.

## The honest gap this skill closes

Without it, the plan and the checks are stitched together by hand: the agent
has to *remember* to run the gates, commit often, and keep the plan alive
across compactions. This harness does the remembering — verify it once, then
the hooks fire on their own and the plan re-grounds you automatically.
