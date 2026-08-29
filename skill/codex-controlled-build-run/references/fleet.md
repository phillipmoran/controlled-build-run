# Codex fleet orchestration

Use only when one user request fans into several dependency-ordered workstreams. A solo build skips the fleet tier but keeps one-strand isolation.

## Roles

- **Builder/workstream:** one production slice, one stream branch, one worktree, one independent Codex root, one stream plan.
- **Orchestrator:** one integration-branch strand, fleet plan, dispatch/monitor/merge/human seam. It writes no production code.
- **Captain:** optional tier above several orchestrators. Reads status/marker/commit facts and relays human decisions; it does not build or merge.

The orchestrator and every builder must be rooted in the repository they operate. Compaction reinjects docs from that root; a captain parked in another repository is not a substitute.

## Fleet plan

The orchestrator's `task_plan.md` is the source of truth:

| Stream | Goal | Branch | Worktree | Depends on merged | Files owned | Status | Findings logged |
|---|---|---|---|---|---|---|---|

Add two kinds of edges:

1. Real dependency: a stream consumes behavior or contracts another stream adds.
2. File-collision dependency: ownership paths overlap, even if logic is independent.

Before any launch, validate the graph is acyclic, ownership overlaps are serialized, all decisions have a durable home, and the integration branch—not release/main—is the base.

## Plan-review gate

Every stream plan gets an independent mechanical review before launch. Block on decidable misses:

- branch/run type mismatch;
- missing planning files;
- phase with no observable behavior or watched-fail test;
- shape-only phase;
- dishonest dependency order;
- undeclared/colliding ownership;
- missing verification;
- unseeded checkpoint table;
- unlocked scope or design fork;
- contract edit not isolated for ratification;
- undeclared Probity exemption or exemption without substitute proof.

Run a broader two-pass/panel review only for design-weighty plans: real architecture forks, contract changes, or shared fields downstream streams consume. Panel opinions advise; verifiable mechanical defects block. Iterate the blocking set twice at most. Still-under-specified plans park while unrelated graph nodes continue.

## Dispatchable predicate

A stream is dispatchable only when:

```text
all dependencies merged
AND plan gate passed
AND provision passed in this worktree
AND live Probity prove-NO/prove-YES passed
AND no live writer owns the worktree
```

Re-evaluate after every merge and every orchestrator resume. Dispatch all ready streams up to 2-3 concurrent builders. Do not manually freeze the graph into waves.

## Detached Codex builder

The portable CLI path uses a persisted `codex exec` session:

```bash
cbr-codex.sh launch <slug> \
  --prompt-file <absolute-prompt> \
  --model gpt-5.6-sol \
  --reasoning high
```

The script launches with:

- `--sandbox workspace-write`;
- `approval_policy="never"` through a Codex config override (the installed CLI's supported non-interactive surface);
- `--json` and `--output-last-message`;
- explicit `--model` and `model_reasoning_effort`;
- `-C <worktree>`;
- persisted session state (no `--ephemeral`);
- hook-trust bypass only for this vetted automation rail.

It stores pid, thread id, JSONL events, stderr, final output, prompt snapshot, and launch metadata under `.cbr-codex/runs/<slug>/` in the primary checkout. The process registry is a fact source, not a health verdict.

The launch prompt must state:

1. Use `$codex-controlled-build-run` from this worktree's `task_plan.md`.
2. Binding contracts are authoritative.
3. Read and write only inside the worktree.
4. Start with the harness probe.
5. Use watched-fail TDD and commit small.
6. Respond to and close every RoboRev review.
7. Update plan checkbox/checkpoint stamps with the work.
8. Never request interactive input; write `ASK-ORCH.md` and continue on the declared default.
9. Commit `DONE.marker` in the final commit only after all gates pass.

## Monitoring

Immediately after launch, arm both fire-once watcher and watchdog as tracked background tasks:

```bash
cbr-codex.sh watch <slug> &
cbr-codex.sh watch <slug> --watchdog &
```

Valid evidence:

- recorded pid alive/dead;
- `events.jsonl` movement and terminal `turn.completed`/`turn.failed`;
- worktree-rooted branch and commit age;
- dirty-file count;
- hash changes in `DONE.marker` and `NEEDS-HUMAN.md`;
- open RoboRev state;
- committed status/plan progress.

Never trust pid alone: a stuck process is alive. Never trust heartbeat alone: it proves only the watcher. Weigh process with commit and JSONL age. Silence past the configured stall interval is an alarm.

The watcher fires once on DONE change, human-blocker change, aged open FAIL, process exit without DONE, or total inactivity. Re-arm it first after every wake. The watchdog fires when the watcher's heartbeat is stale for 15 minutes. A coarse outer wake may backstop all-watchers-dead scenarios; it does not replace the 15-minute stall alarm.

Questions route by file:

1. Builder writes `ASK-ORCH.md`, logs the question in the plan, and continues other work.
2. Orchestrator triages: ruled/trivial → answer; engineering judgment → independent panel; scope/contract/vision → human.
3. Orchestrator writes `ORCH-ANSWER.md` and the durable decision record.
4. Resume/injection tells the builder to consume the answer.

## Recovery

Use:

```bash
cbr-codex.sh resume <slug> --prompt-file <resume-note>
```

The rail reads the recorded thread id and runs `codex exec resume` from the same worktree with the same explicit sandbox/model/reasoning. If the original rollout is unusable, launch a fresh session with a resume prompt that points to git + plan. Do not reset committed work. Stop repeated same-phase crashes rather than creating a restart storm.

## Merge gate

Before merging a stream into integration:

- independently rerun the full deterministic verification in the stream;
- every phase is checkpoint-stamped;
- `findings.md` is committed;
- all RoboRev jobs are completed and closed;
- no uncommitted real work exists;
- current destination branch is the intended integration branch;
- whole-stream diff matches the plan and binding contracts.

Merge, then run the real product entry path against the merged tree with real machine/data inputs. Unit green is insufficient. Define the live smoke command, observable proof, and time budget in the fleet plan. A smoke failure returns to the stream test-first.

Close the merge-commit review, then immediately run:

```bash
cbr-codex.sh closeout <slug> --into <integration-branch>
```

Closeout archives stream-only planning/status/channel/watch artifacts before removing worktree and branch. The merge is incomplete until closeout finishes.

At epic end, rerun the whole-tree gate, live smoke, and closeout review. The integration branch merges to the release branch once and only with the user's sign-off. The script never performs that merge or push automatically.

Run `cbr-codex.sh janitor` at merge gates and periodically. It reports reapable worktrees, active/unmerged branches, orphan stream branches, and stale registry files; it deletes nothing.
