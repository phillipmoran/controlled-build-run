# build-loop.md — run the build as a watched-fail TDD loop

Part of `cbr-core`, the provider-neutral CBR law. Checkpoint mechanics, the
plan-review gate, and golden samples live in `reviews.md`; judgment-call
triage lives in `judgment.md`.

## Readback — a dispatched builder proves it read the plan

A builder that receives a plan it did not write has one failure mode above
all others: it *skims*. Nothing downstream catches it. Probity guards the
writes, the gates guard the commits, RoboRev reviews the diff — and every one
of them is happy while the builder builds a competent, well-tested version of
the wrong thing, or quietly re-enters ground the plan put OUT of scope. The
plan's own words are no defence: they were read once, at full context, and by
the second compaction they are a summary of a summary.

So the readback is LAW, not courtesy:

- **A dispatched builder's first act after reading `task_plan.md` — before
  any code, any test, any probe — is to write a readback into `progress.md`:
  the mission, the locked scope, and the OUT list, restated in its own
  words.** In its own words is the whole point; a copy-paste of the plan
  proves the clipboard works, not that anything was understood. Name the
  things that would be easy to drift into and are OUT, and the one sentence
  that says what "done" is.
- **The dispatcher checks that readback against the plan before the builder
  proceeds**, and a mismatch is caught while it costs one message. This is
  the cheapest correction seam in the whole flow: a misread scope found at
  the readback costs a sentence; found at the checkpoint it costs a phase;
  found at the merge gate it costs the strand.
- **The readback stays in `progress.md`**, because that is the file that
  survives compaction and that the next agent — or the re-grounded version of
  this one — actually reads. A readback delivered only as chat is gone.
- A **solo** builder writes the readback too. It is a weaker check (nobody
  independent reads it), but it is not worthless: restating a plan you wrote
  yourself is where you notice the step whose "why" you cannot reconstruct.

A leaf may add a deterministic **outside-view** fact for this — whether the
dispatched builder's `progress.md` contains a readback at all — because
presence is a mechanical fact. Whether the readback is *faithful* is a
judgment, so it may only surface, never gate (`policy.md`).

## The loop

1. **Read the orientation docs first.** Per the repo's boot ritual: the agent
   entry doc, the newest handoff, the roadmap, and the contract(s) your work
   touches. Know the rules before you write.

2. **Lock the scope with the human, before any code.** Agree exactly what
   you're building and what's out. Surface forks; don't decide vision-shaped
   questions (contract edits, new top-level packages, out-of-glossary names,
   scope changes) alone. An *engineering*-shaped fork — one inside scope and
   contracts — takes a multi-model panel instead (see `judgment.md`).

   **Before you write the plan, run the fix through four questions.**
   Skipping them is how the old repo rotted — each bug spawned a new code
   path instead of conforming to the design.

   1. **Is this already a rule?** Find the contract that governs this
      behavior. If the code drifted from it, the fix is to return to the
      contract and delete the drift — not to invent; most "bugs" here are
      drift. If no contract covers it, stop and surface it to the human
      before building — an unruled behavior is a vision call, not an agent
      call (contracts-as-rules + stop-and-surface).
   2. **One bug, or a kind of bug?** Could this same broken state happen at
      other sites — now, or the next time someone writes similar code? And
      has it hit before — scan the git history (`git log --grep`, or the
      commits that touched these files), the one record that can't go stale.
      If it repeats or is easy to repeat, fix the *class*: name it — a real
      class earns a principle — and guard it structurally, not just today's
      instance.
   3. **Can the bad state be made impossible?** Ask what let the broken
      state exist at all. Prefer a structural change that makes it
      unrepresentable (move data to its single owner; derive instead of
      duplicate) over a runtime guard that only watches for it. Guards are
      the backstop; structure is the cure (single-owner; derive-don't-sync).
   4. **Is the behavior I'm about to change pinned by a test?** Before you
      touch a seam, characterize what it does *today* — including the
      edges — with a test. An untested behavior is where a silent regression
      hides (test discipline).

3. **Make the plan** with the planning skill: `task_plan.md`, `findings.md`,
   `progress.md`. Into `task_plan.md` write the **Branch:** line (see
   `strand.md`), the locked scope, the build steps in order, the verification
   commands (tests / lint / types, including the format check), and a
   "commit very often" reminder, and — as you go — the in-flight decision
   log. These planning artifacts are committable: they carry real decisions
   worth keeping, so commit them with the work rather than gitignoring them.
   (Note: `task_plan.md` is overwritten each session, so the durable
   decision record is the handoff's decisions section.) Also seed a
   **phase-checkpoint table** (see `reviews.md`) so each phase's review is
   tracked from the start.

   **When you order the build steps, never create one that changes shape but
   no behavior** (a standalone sync→async flip is the classic) — it can't be
   test-driven and Probity will rightly block it. Fold it into the first
   step that adds the behavior it serves, and lead with that behavior's test
   (see *Probity gotchas* below).

4. **Confirm the re-ground hook points at this plan** (`policy.md`, piece 6).

5. **Build each piece as a watched-fail TDD cycle:**
   - run the suite first (baseline green),
   - write **one** failing test; run it; watch it fail for the right reason,
   - if Probity demands it, add a stub that makes the symbol importable but
     still fails the *assertion* (clean red), then write the real code,
   - run tests, then lint and types, and the formatter to tidy (the gate's
     format check blocks an untidied commit),
   - **commit** — small, often, and that is the LAW, not a preference
     (ratified by the human 2026-07-03: early catch beats batching; never
     batch commits to save review cost). Review cost decouples from commit
     count on the ROUTING side instead: a docs-only diff (every changed path
     under `docs/**` or `*.md`) gets a skipped or feathered review, decided
     by the DIFF PATHS, never by builder declaration — a builder saying
     "docs-only" counts for nothing; the paths are the fact. Move this
     cycle's plan checkbox (`[ ] → [x]`) **in the same commit** — never as a
     later pass, because the plan is the one status source the re-ground
     hook re-injects and that every fresh agent reads, yet no other check
     here (Probity, pre-commit, RoboRev) reads it, so a checkbox that lags
     the code silently misleads the next (or compacted) agent,
   - if RoboRev returns a FAIL, handle it **and then close the review** so
     an open FAIL always means a real unresolved item: fixed → close it;
     wrong or intentional → close-with-reason (respond, then close). Leave
     it open only if it's deliberately deferred or needs the human. Max ~2
     fix rounds **per finding-surface**, then stop fixing: escalate, or
     exit by judgment — decline with recorded reasoning and surface the
     decline to the human for overrule. The asymmetry that justifies the
     low limit: a decline is reversible (reopening costs the human one
     glance at your reasoning) while an unbounded chain costs a full
     commit-review-fix lap per round. A genuinely NEW defect — a different
     surface, or found on a fresh commit — resets the counter: the limit
     caps re-litigation, never real bugs. (Closing after a fix is the easy step to
     forget — so since 2026-06-12 it is mechanically enforced: the
     review-clean pre-commit gate refuses the next commit while this branch
     has any open, queued, or running review. A deliberately deferred review
     must be close-with-reason'd and re-opened as a plan item instead of
     left open. The session-sweep remains the backstop.)
   - if a review **crashes** (an infra failure — an overload, an auth lapse,
     a dead daemon — distinct from a FAIL *verdict*) it produced **no review
     at all**, so that commit is unreviewed: **re-run it, never skip** —
     request a fresh review of that sha and poll until it lands done (an
     up-front rejection costs ~nothing to retry — back off and retry).
     **Bound the loop:** if it keeps crashing ~5 times in a row, stop and
     wait — that is no longer a transient blip but a likely real outage (a
     provider incident, an expired auth token, a dead daemon), so surface it
     (flag the human / open a plan blocker) rather than hammering. Re-run is
     the default; infinite retry is not. The review-clean gate holds the
     floor: it blocks a commit whose reviews *all* crashed, and ignores a
     crashed job only once that same commit has a done review (the crash was
     a duplicate/retry). "It errored, move on" is the one thing the gate
     will not let you do.

6. **Render and review a golden sample** when the work produces an artifact
   a human or an LLM will *read* — see `reviews.md`.

7. **Update the plan as you go** (mark phases done; log errors) — it's your
   durable memory and the re-ground hook re-injects it. And keep a **friction
   log**: the moment the harness itself wastes your time (a manual chore, a
   flaky gate, a missing provision step), write one line about it in
   `findings.md` right then. A harness retro is then a read of recorded
   artifacts, not a reconstruction from memory — and a friction that recurs
   across strands is the signal for an automation candidate.

8. **Checkpoint-review at each phase boundary** — mechanics and the
   contradiction taxonomy are in `reviews.md`. Fix load-bearing FINDINGS
   before starting the next phase.

9. **Closeout** when the build is done. First confirm every phase shows
   `reviewed == its end_sha` — a missing stamp means a checkpoint was
   skipped; do it now. Then run your project's end-of-work closeout ritual.
   The per-phase checkpoints catch issues *early*; they do **not** replace
   or shrink the closeout's whole-work review — that ritual owns how the two
   relate.

   **Archive the plan at closeout.** The root `task_plan.md` is ephemeral
   working memory (overwritten next session, and the path both this process
   and the planning skill hardcode). To keep a durable, organized record,
   copy the finished plan to the repo's plans archive under a
   UTC-timestamp-plus-slug name matching the handoffs convention. The root
   file stays put so the hooks keep working; the archived copy is the
   permanent, named record. Leave `progress.md` / `findings.md` at root as
   the running logs (archive them too only if a session warrants it).

   **Merge back and clean up.** When it's done, merge the branch into its
   base — main for a solo strand; in a fleet, the integration branch
   (`modes/fleet.md`) — then remove the worktree and delete the branch.

   **Who merges: after GO, the builder merges.** Approval and execution are
   two different acts, and leaving the second one unassigned means both
   parties reach for it. On 2026-08-19 the builder and its orchestrator
   merged the same strand twice within seconds of each other; it was a no-op
   only by luck, and the same race with a conflict, a hook, or a `--no-ff`
   in flight is a corrupted base branch that nobody owns.

   So the rule is: the builder asks for GO through the file channel and
   waits; the tier that grants GO grants permission, not the merge itself.
   Once GO lands, the BUILDER performs the merge. It is the right owner
   because it is the session holding the context a conflict would need, and
   because it is already the one whose gates must be green at that moment.

   **The merge and the closeout have different owners, on purpose.** The
   closeout REAPS the strand — worktree, branch, watch files — so it cannot
   be run by a session sitting inside the thing it destroys, and the leaves
   enforce exactly that (a closeout refuses to run from the checkout it is
   closing, and refuses a worktree anybody is still working in). So the
   builder merges and then writes its closeout NOTES and its completion
   marker; the tier above runs the closeout command afterwards, from the
   base checkout, once the builder is gone. Reading "the builder owns its
   ending" as "the builder runs closeout" produces a command that cannot
   succeed — see `modes/fleet.md`, which has always assigned the closeout
   command to the orchestrator.

   **The base branch's own ownership rule wins.** "The builder merges" settles
   WHICH of the two automated tiers performs an approved merge; it does not
   grant either of them a branch a human has reserved. A repo whose binding
   docs say a named person merges a given branch has already assigned that
   act, and no process law written elsewhere overrides it — read the rule as
   applying to the branches the machinery owns (integration and below), and
   treat a human-owned branch as a stop: prepare the merge, hand it over, say
   so in the records. Where the two are in tension, the ask goes to the human
   and names the tension; a builder that resolves it in its own favour has
   given itself permission, which is the failure this whole step exists to
   prevent.

   **The merge transfers when the target branch is occupied.** Git refuses
   to merge into a branch that is checked out in another worktree, so a
   builder can hold GO and still be mechanically unable to act. In a fleet
   this is not an edge case but the standing state: the orchestrator's own
   checkout typically sits on the integration branch for the whole epic, so
   the builder's GO-merge is unsatisfiable by construction (observed on a
   downstream deployment, 2026-08-26 — two consecutive epics). Occupancy is
   the RACE'S OPPOSITE — exactly one party CAN act — so the transfer is
   safe by the same logic that makes the race dangerous: the builder writes
   a handoff note through the ordinary question channel — no new filename —
   stops, and the occupant of the target branch performs the merge it
   already approved, recording that it did. The note's required parts, in
   order (shape proven on the same deployment's run, where the occupant
   landed the handed-off merge in one command sequence): a header that says
   BLOCKING and states the world before the reasoning ("merge NOT done") —
   the flag is what makes a skimming reader stop, because most question
   entries are recorded-default non-blockers; the occupancy facts, each
   independently checkable; the named hazard (the plumbing route and
   exactly what one `reset --hard` would destroy — naming the destructive
   reflex is what keeps the next builder from trying it); and a
   `git merge-tree --write-tree` pre-verification summarized as an exact
   conflict list — expected, not a courtesy, because it converts the
   handoff from "you deal with it" into a pre-chewed merge. Mirror the
   handoff at the top of the strand's progress record too: that file is
   archived verbatim at closeout, so the permanent record explains the
   anomalous merge authorship without the question channel's context. What
   the builder must NEVER do is route around occupancy with plumbing: a
   `commit-tree` / `update-ref` ref-move lands under a working tree that
   may hold uncommitted work, leaving its index behind its new HEAD, where
   one reflex `reset --hard` destroys the occupant's edits.

   **The orchestrator merges only when the builder is proven dead.** Proven,
   not assumed, and not inferred from silence: the leaf's status command
   must report no live session AND no live process rooted in the worktree
   (`policy.md` — deterministic facts may gate, and occupancy is one). A
   builder that is merely quiet, compacting, or waiting on a review is
   alive, and taking the merge away from it is how the race gets recreated
   by the party that was supposed to prevent it. When the orchestrator does
   take over, it says so in the strand's records, because the next reader
   needs to know which session's judgment the merge carries.

   **When occupancy cannot be established at all.** On a host whose process
   table cannot be inspected, "is anybody working here" has no answer, and
   both the dispatch and the reap refuse rather than guess — an unanswerable
   question is not a pass. That refusal must have a way through it, or the
   only route left is a hand-run removal OUTSIDE the ritual, which skips the
   three duties below and re-opens exactly the gaps they close. So the
   refusal names an explicit operator assertion: a human checks by hand and
   says so, in as many words, on that one command. The escape hatch is a
   human taking responsibility for the fact, never the tool inventing one.

   **The three duties closeout owes the base branch.** Reaping the worktree
   is the visible half of the ritual; these three are the half that, left
   undone, quietly charge the NEXT strand. Each was paid by hand, as its own
   fix-up commit, before it was written down here (observed 2026-08-19 across
   two strands finishing the same evening):

   1. **Archive the strand's records out of its FINAL COMMIT** — the plan,
      the progress log, the findings, the completion marker, the ask/answer
      channel. Not out of the worktree: by the time closeout runs the strand
      has merged, so the base checkout holds the same bytes, and any archiver
      that skips what matches the base skips the entire archive. The commit
      is the only source that still holds what the strand ended with, and it
      is about to become unreachable — the branch is deleted seconds later.
      A record that exists and cannot be saved FAILS the closeout; a record
      the strand never wrote is simply absent — where "wrote" means committed,
      since the commit is what is being read. A record left uncommitted in the
      worktree is the dirty guard's business, not the archiver's: it is the
      dirty guard that puts an uncommitted record in front of a human and makes
      them declare it disposable before the reap proceeds.

      Failing the closeout means STOPPING, before duty 2. The duties run
      seconds ahead of the reap, so their order is the whole safety property:
      carrying on past a failed archive removes the marker and regrounds the
      plan on behalf of records that were never saved. Stop with the base
      untouched, and make the retry that invites actually runnable — a
      half-finished closeout that cannot be re-run gets finished by hand, which
      is how the duties get skipped. Runnable is not the same as unguarded:
      slugs get reused, so an archive already sitting at the destination is a
      retry only when the records in it name the branch being closed out. One
      that names a different branch, or names none, is another strand's record
      and stops the closeout for a human to move aside.
   2. **Remove the strand's completion marker from the base.** The marker
      merges onto the base with the work and stays there. The next strand
      folds the base into its branch, inherits a marker naming a strand that
      finished days ago, and its watcher latches on it — a completion signal
      for work that has not started. Deleting it at closeout is the cure;
      a watcher that ignores a marker naming a different branch is the
      backstop, and a system this cheap to get wrong deserves both.
   3. **Reground the base's root plan.** A merged strand leaves the base's
      `task_plan.md` naming a branch that no longer exists, so any gate
      comparing that line against the checked-out branch fails the base's
      very next commit until a human edits one line. Closeout rewrites the
      branch token and nothing else.

   All three are staged with the closeout commit, so they land as one
   deliberate act rather than as debris someone finds later in `git status`.
   They are deterministic git and filesystem work with no provider in them:
   a harness that runs more than one leaf implements them ONCE, shared, and
   calls that one implementation from each leaf. Two copies of a rule this
   quiet is two copies that drift, and the drift is invisible precisely
   because the failure shows up in the *next* strand, not this one.

## Probity gotchas (so you don't fight the guard)

- **Baseline before a new test:** run the suite right before adding a
  behavior-asserting test, or the add is blocked.
- **One new test per write.**
- **Stub-then-real:** an import error is not a clean red. Add a stub that
  raises (or returns the wrong thing), watch the *assertion* fail, then
  implement.
- **Minimal green:** implement only what the failing test needs; add the
  next branch via its own failing test.
- **The red must reference the change.** Probity reads the *failing* test
  and only unlocks a production edit that would make *that* test pass — an
  unrelated red unlocks nothing. The watched-fail must exercise the symbol
  or behavior you're about to change. (Probed: an edit adding a marker
  symbol stayed blocked while the only red asserted on an unrelated name —
  Probity rejected it by name, "does not reference" the marker.)
- **A brand-new test against a green file can deadlock** ("must be observed
  failing in a prior run" is circular for a test that does not exist yet).
  The honest unlock is a **scratch red**: write the test in a scratch file
  OUTSIDE the gated tree, run the test runner on that file, watch the
  genuine red — then land the test at its real home and implement. This
  works only when a real red exists (the behavior is genuinely missing
  today). Two riders: assert on values or status codes, not on expected
  exceptions — an unexpected-exception failure can read as a crash and be
  rejected as "not the right reason"; and a test that would pass immediately
  has no red to observe — land it under the test-only exception rule below
  instead.
- **Test-only exception (ratified by the domain owner, 2026-06-11):** a
  change that is ONLY a test, and passes immediately against committed
  production code, may land past the gate with a documented note in the
  commit message citing this rule. A test cannot smuggle untested production
  code, and a wrong pin fails the suite on the spot. Production code always
  still needs its watched red — this exception never covers a production
  line. Mechanically: state the case in-session first (suite green, this
  rule, why no red can exist), then attempt the write — the
  transcript-reading judge has accepted pass-immediately characterization
  tests before. If it still refuses, the write cannot happen from inside the
  gated session: it becomes a documented deferral surfaced at the next
  checkpoint, and the orchestrator lands it at the fix round or merge gate
  with the citing note (Probity is root-scoped, so the orchestrator's
  session is the one place this policy-covered write is mechanically
  possible).
- **Probity guards the worktree the session is rooted in — and only that
  one.** It works correctly inside a worktree (proven: a worktree-rooted
  session blocks untested production code). The trap is a *mismatch* — a
  session rooted in folder A editing files in worktree B is unguarded,
  because Probity's gated-tree glob only sees the session's own root. Keep
  the session rooted where the code lives (one session per worktree);
  prefer launching it there over any in-session folder-switch tool, which
  does not survive a compaction. Re-verify with a probe after switching
  folders.
- **A real behavior change: edit the claim, watch it go red.** Change the
  existing test's assertion to the new truth and run it — that red is what
  unlocks the production fix. This is the honest path and almost always
  works.
- **A shape-only change (sync→async, no new behavior) has no honest red —
  so it must not be its own step.** Probity blocks it *correctly*: nothing
  behaves differently, only the contract changes color, and the only failure
  you can produce is a crash, which the rubric rejects as "not the right
  reason." Don't retry the edit and don't reach for an exception.
  Re-sequence: fold the shape change into the first step that adds the
  *real* behavior it exists for, and lead with that behavior's failing
  test — the flip then rides in as the implementation that red demands.
  (The rubric's own clean-red recovery, "adjust the signature to reach the
  assertion," is exactly this path.)
- **A pure relocation (move code, no behavior change) should pass Probity's
  refactor rules.** If the fallible judge wrongly blocks one, that — and
  only that — is when a documented one-session exception is legitimate: the
  valve for a wrong verdict, not a way around an inconvenient red. Never use
  it for a shape flip; a blocked shape flip is a mis-sequenced plan, not a
  wrong verdict.
