# acceptance/scenarios.md — the six end-to-end smoke scenarios

Part of `cbr-core`. The checklist's rows are proven one at a time; these six
scenarios exercise the components **together**, on a fixture repo with a
faithful stand-in TDD guard and review daemon — never the live fleet. Each
leaf implements the six with its own mechanisms; the shape is core.

1. **Arm + dynamic graph.** Arm a disposable fixture repo (trust/vet its
   hooks); prove-NO (a blocked untested production write — twice in a row,
   the block must hold) and prove-YES (an allowed scratch write + one real
   toolchain command) across **every** write path the leaf's agent has
   (direct edit, subagent, patch mode). Then run the fixture DAG
   (1 → 3 → 1): the in-flight shape flexes 1→3→1 with no hand-scheduling,
   and the **negative** — dispatching an unlocked stream WITHOUT provision —
   is a hard failure.

2. **Compaction recovery mid-build.** Run a two-phase build through a forced
   compaction; verify the re-ground injects the whole live section set plus
   the strand's own plan, states already-booted (no boot re-run, no handoff
   switch), the continuation is role-aware (once C2 is built in that
   leaf), and the builder resumes from the
   next unchecked box with a re-established green baseline.

3. **Review lifecycle.** Against a fake review CLI, exercise every status
   the live gate must distinguish: PASS (auto-close, no hand-close of the
   last open PASS), FAIL (respond + close unblocks), queued/running
   (blocks), crashed (blocks until a done review covers the sha; duplicate
   crash ignored after), absent row (caught by the per-sha lookup, never
   the list), and daemon null (= zero open, not malformed).

4. **Dispatch survival + monitoring from outside.** Launch a detached
   builder; record its durable identity; assert liveness from ground truth
   (the durable outside liveness source + worktree-matched cwd + commit
   age + log movement) from a
   session that is NOT its parent; kill the dispatcher and confirm the
   builder survives; kill the builder and confirm the watcher fires; resume
   from the recorded identity.

5. **Plan-review tier / panel / park.** Feed the orchestrator a trivial
   plan (no panel runs), a design-weighty plan (panel runs, a taste-finding
   does not block), a plan with a decidable defect (blocked at F6a), and an
   unresolvable plan (parks at the round cap while the rest of the fleet
   keeps dispatching).

6. **Merge + closeout.** Merge a stream through the full I1 gate; run the
   live post-merge smoke against the merged tree (a fixture whose unit
   suites pass but whose real entry path fails must bounce); archive the
   plan and verify the archive commit's diffstat is non-empty; close out
   and verify no worktree, branch, or watch file remains — and each
   closeout refusal (live owner, unmerged content, uninspected dirty files)
   fires when seeded.
