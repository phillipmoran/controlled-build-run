# Workstream build loop

## Plan altitude

A good phase fixes decisions and acceptance without scripting implementation. Each phase names:

1. Observable outcome.
2. One watched-fail test that proves it.
3. Decisions already locked: contract/event/field/threshold/seed/compatibility/file anchors.
4. Files or path zones owned.
5. Verification command.

Do not dispatch unresolved design forks. Put human-only forks in `Open with human`; resolve in-scope engineering judgment with an independent Codex panel/reviewer and log the recommendation.

Avoid shape-only phases such as a standalone sync-to-async conversion. A shape change has no honest behavioral red. Fold it into the first behavior that requires the shape and start from that behavior's failing test.

## Before the plan

Ask four questions:

1. Which binding rule already governs this behavior? Return drift to the rule instead of inventing a second path.
2. Is this one occurrence or a repeatable class? Search history and sibling sites.
3. Can structure make the bad state unrepresentable? Prefer single ownership and derivation over synchronized copies.
4. Is current behavior characterized at the seam before it changes?

Contract, scope, new top-level package, or vocabulary changes are human decisions. Local implementation choices inside ratified contracts are agent decisions. Real architecture judgment gets an independent panel recommendation; it does not silently mutate scope.

## Watched-fail cycle

1. Run the focused suite immediately before adding the new behavior test.
2. Add one failing test.
3. Run it and confirm the failure is the intended assertion, not an import crash or unrelated red.
4. Add a minimal stub if necessary to reach the assertion.
5. Implement only the behavior that makes this test pass.
6. Run focused tests, then the live repository verification commands.
7. Update the plan checkbox and logs in the same commit.
8. Commit normally and wait for review.

Commit early and often. Review cost is controlled by routing and diff risk, not by batching unrelated changes.

## Probity recoveries

- **No recent baseline:** run the relevant committed suite green, then retry the test write.
- **Import crash:** add a minimal importable stub, observe the behavior assertion fail, then implement.
- **Red does not reference the change:** rewrite the test so it exercises the exact symbol/behavior being edited.
- **New test file deadlock:** create a scratch red outside the gated production tree, run it to observe the genuine missing behavior, then land the real test and implementation. Assert values/status, not an expected exception that can be confused with a crash.
- **Pass-immediately characterization test:** test-only change may land with a commit note citing this exception after proving the suite is green and production is unchanged. It never permits production code.
- **Behavior change:** edit the existing claim to the new truth, observe red, then change production.
- **Shape-only change:** resequence it into the first behavior phase; do not bypass.
- **Pure relocation:** use the refactor path. A documented one-session exception is legitimate only for a demonstrably false Probity judgment on behavior-preserving relocation, never for a mis-sequenced feature.
- **After compaction:** rerun the baseline in the live transcript before continuing a refactor.
- **Wrong worktree root:** stop. Relaunch Codex rooted in the worktree; never edit a sibling worktree from the current session.

## RoboRev lifecycle

After every commit:

- PASS: the clean gate auto-closes an open clean review.
- FAIL fixed: `roborev respond <job> -m '<evidence>' && roborev close <job>`.
- FAIL rejected/intentional: respond with the rule/evidence and close.
- Deferred/human: convert to a plan item, respond, and close; do not leave an ambiguous open review.
- Crash/no review: `roborev review <sha>`, wait, then handle the completed result.

Cap finding/fix iterations at about two. Cap repeated review infrastructure retries at about five with backoff. A same-error storm is a blocker, not permission to skip.

## Phase checkpoint

At each completed plan phase, stamp `end_sha = HEAD`. Review only `<last-reviewed-sha>..HEAD` with an independent read-only Codex subagent/session. The reviewer checks the phase goal and touched binding contracts, not line-level style already covered by RoboRev.

Contradiction taxonomy:

1. Behavior without a rule.
2. Rule without a test.
3. Ratified-text drift.
4. Homeless/new concept without a contract or vocabulary home.
5. Second implementation of an existing concept.
6. Goal miss.

Most phases should return zero findings. Require each item to contain:

- severity: `load-bearing` or `minor`;
- label: `FINDING` or `INTERPRETATION`;
- evidence: for a FINDING, quote both disagreeing artifacts with `file:line`;
- contradiction: one sentence;
- resolution: concrete fix or `needs-human`.

Only quoted evidence-backed FINDINGs bind. Fix load-bearing findings before the next phase. Stamp `reviewed = HEAD`; reopened phases review only their new delta.

## Golden sample

When a human or model reads the output, generate a realistic full sample from real-shaped domain objects and inspect it. Check omission, duplication, ordering, leaked IDs, readability, and failure rendering. For hero-facing formats, obtain human review.

## Recovery

After interruption or process death:

1. Read `task_plan.md`, `progress.md`, `findings.md`, `git log`, `git status`, and RoboRev state.
2. Confirm branch/cwd/harness.
3. Resume the recorded Codex thread with `cbr-codex.sh resume <slug> --prompt-file <resume-note>` when usable; otherwise launch a new root with the one-line resume instruction.
4. Continue from the next unchecked phase. Do not redo committed phases or reread a stale handoff as current scope.
5. If the worker repeatedly dies in the same phase, stop relaunching and surface the poisoned state.

## Closeout

Before completion:

1. Verify every `reviewed` stamp equals its phase `end_sha`.
2. Run the whole-work closeout review; checkpoints do not replace it.
3. Run the full deterministic gate and product smoke.
4. Prove zero open/queued/running reviews.
5. Archive the plan and durable findings under the repository convention.
6. Preserve any workstream-only bookkeeping before branch deletion.
7. Merge only from the verified destination branch.
8. Reap the worktree/branch/watch state through `cbr-codex.sh closeout` only after merge proof and no-live-owner proof.

Never push or deploy unless the user explicitly authorized it. A terminal requirement to finish does not broaden release authority.
