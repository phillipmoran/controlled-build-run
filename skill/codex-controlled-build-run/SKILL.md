---
name: codex-controlled-build-run
description: >-
  Set up and run a disciplined, plan-driven Codex build with planning files,
  Probity watched-fail TDD, deterministic pre-commit checks, RoboRev review,
  role-aware post-compaction reinjection, isolated worktree strands, and
  persistent fleet supervision. Use for non-trivial builds, long or autonomous
  runs, harness setup or smoke testing, compaction recovery, and orchestrated
  multi-worktree development.
---

# Codex Controlled Build Run

Treat this file as the Codex provider router. The complete process law lives in
the byte-exact shared-core snapshot under `references/cbr-core/`; Codex-specific
mechanics live in this leaf's references, scripts, and templates. Never replace
the routed law with a summary from memory.

## Route the law before acting

Read these shared files for every controlled build, in order:

1. `references/cbr-core/policy.md`
2. `references/cbr-core/strand.md`
3. `references/cbr-core/reviews.md`
4. `references/cbr-core/judgment.md`
5. `references/cbr-core/GLOSSARY.md` (the harness's own words; use them exactly)

Then select the current role from the active `task_plan.md` and branch:

- **Workstream/builder:** read `references/cbr-core/build-loop.md` and
  `references/build-loop.md`. When this is a solo strand rather than a
  `stream/*` fleet builder, also read `references/cbr-core/modes/solo.md`.
  Do not load fleet or captain mode into a workstream.
- **Orchestrator:** read `references/cbr-core/modes/fleet.md` and
  `references/fleet.md`. Do not load the builder TDD loop or solo/captain mode
  into an orchestrator reinjection payload.
- **Captain:** read `references/cbr-core/modes/captain.md` and the role/mechanism
  sections of `references/fleet.md`. A captain watches and relays; it does not
  build or merge.

For harness setup or repair, read `references/harness.md` completely before
changing a hook or config. For portability decisions, read
`references/porting.md`. For panel mechanics, read
`references/panel-review.md`. For acceptance, combine
`references/cbr-core/acceptance/checklist.md`,
`references/cbr-core/acceptance/scenarios.md`, and
`references/cbr-core/acceptance/mutations.md` with the Codex mechanical rows in
`references/acceptance.md`. `references/conformance.md` defines how the copy and
provider boundary are enforced; `references/CODEX-COVERAGE.md` proves that the
former long Codex router's provider mechanics all have surviving destinations.

## Use the Codex harness exactly

Use two hook systems:

- Project hooks in `.codex/hooks.json` run Probity before writes, redirect
  interactive questions, surface RoboRev results, sweep open failures, continue
  unfinished builders, and re-ground after compaction.
- Git hooks run the deterministic pre-commit gate and trigger RoboRev after
  commits and rewrites.

Wire compaction recovery as a two-step provider handoff. `PostCompact` writes a
worktree-and-thread-scoped pending marker because that event cannot emit
`additionalContext`; the next `UserPromptSubmit` consumes the marker and injects
the complete role-aware payload with `additionalContextLimit: 0`.
`SessionStart(resume)` consumes the same marker when a compacted session is
closed before its next prompt. The installed Codex host does not emit
`SessionStart(compact)` after `/compact`; wiring re-grounding there leaves the
resumed model blind. Review project hooks in the Codex terminal TUI's `Hooks need review`
screen; Codex Desktop chat has no hook-review command. Record the vetted source
hash before unattended launch.

Run the pinned TDD guard with `--agent codex`. Exercise every real write path,
including `apply_patch`, in the live prove-NO/prove-YES probe. The guard fails
closed when its config, judge, or load path cannot prove a safe write.

Use persisted `codex exec --json` sessions for detached builders. Launch with:

- `--sandbox workspace-write`, never unrestricted access;
- `approval_policy="never"` so a headless run cannot wait on a prompt;
- explicit worktree, model, and reasoning values from `.cbr-codex.json`;
- no ephemeral mode;
- the hook-trust bypass only after the harness independently verifies the exact
  trusted hook hash.

Keep the selected model's threshold in `.codex/config.toml` under
`model_auto_compact_token_limit`; the portable large-context value is `297500`,
and MUST be clamped for a smaller model. The re-ground hook remains mandatory.

## Verify or wire before building

Run the companion script from this skill directory:

- `scripts/cbr-codex.sh arm <repo>` — create missing harness pieces without
  clobbering richer existing files, then stop for hook review/trust.
- `scripts/cbr-codex.sh doctor [repo]` — prove every harness fact before each
  build.
- `scripts/cbr-codex.sh probe [repo]` — run the live blocked/allowed write probe.

Do not declare the harness armed from static configuration alone. Confirm the
branch equals the plan, the session root is the worktree, dependencies work,
Probity blocks an untested guarded write, and an allowed scratch write succeeds.

## Run one strand from files

Keep `task_plan.md`, `findings.md`, and `progress.md` at the worktree root. One
branch, one plan, one folder, and one root session form the strand. Update the
plan checkbox in the same commit as its work. Commit small and often.

For each behavior: run a green baseline, add one relevant failing test, observe
the intended red, implement the minimum green change, run focused and repository
gates, update the plan, commit, and handle the review. Respond to and close every
RoboRev finding before the next commit. Re-run crashed reviews; after about two
finding/fix rounds or five infrastructure crashes, escalate instead of looping.

At each plan phase boundary, run the independent contradiction review from
`references/cbr-core/reviews.md`, then stamp the exact reviewed SHA. Render and
inspect a realistic golden sample whenever a human or model reads the output.

## Run a fleet through the fixed rail

Use one integration-branch orchestrator strand and one independent worktree-root
session per builder. Never use an in-task subagent as a production writer in
another worktree; its hooks and TDD transcript bind to the wrong root.

Use only these lifecycle commands for fleet mechanics:

- `scripts/cbr-codex.sh provision <slug> <branch>`
- `scripts/cbr-codex.sh launch <slug> --prompt-file <file>`
- `scripts/cbr-codex.sh watch <slug>` and `--watchdog`
- `scripts/cbr-codex.sh status <slug>` and `fleet`
- `scripts/cbr-codex.sh resume <slug> --prompt-file <file>`
- `scripts/cbr-codex.sh closeout <slug> [--into <branch>]`
- `scripts/cbr-codex.sh janitor`

Run `watch` and its watchdog immediately after launch. Durable run facts live
under `.cbr-codex/runs/<slug>/`; the not-yet-watched latch and watcher state live
under `.cbr-codex/watch/`. Weigh process state with JSONL/commit age. Silence is
an alarm. Scripts gather facts and run fixed sequences; they never decide to
merge, push, relaunch, kill, or declare health.

## Resume after compaction without reading

The re-ground hook injects the binding project docs, this router, the shared
common law, exactly one role payload, the active plan, findings, and progress.
It states that boot and harness setup already happened. Continue from the next
unchecked plan item immediately; do not perform a recovery-time file-reading
ritual or switch to a newer handoff. Task-specific source inspection after
resumption remains normal work.

## Hold the final boundaries

Run the full deterministic gate, live product smoke, phase/closeout reviews, and
zero-open-review proof before merge. Archive planning records before teardown.
Never push, deploy, cross a ratification gate, or delete ambiguous work unless
the user explicitly authorized it.
