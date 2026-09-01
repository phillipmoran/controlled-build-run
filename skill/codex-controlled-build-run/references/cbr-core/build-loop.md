# build-loop.md — run the build as a watched-fail TDD loop

Part of `cbr-core`, the provider-neutral CBR law. Checkpoint mechanics, the
plan-review gate, and golden samples live in `reviews.md`; judgment-call
triage lives in `judgment.md`.

## Readback — a dispatched builder proves it read the plan

A builder that receives a plan it did not write has one failure mode above
all others: it _skims_. Nothing downstream catches it. Probity guards the
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

The dispatcher reads the readback with its own eyes — presence and
faithfulness are both the dispatcher's judgment; no control-plane parser stands
behind this law.

## The loop

1. **Read the orientation docs first.** Per the repo's boot ritual: the agent
   entry doc, the newest handoff, the roadmap, and the contract(s) your work
   touches. Know the rules before you write.

2. **Lock the scope with the human, before any code.** Agree exactly what
   you're building and what's out. Surface forks; don't decide vision-shaped
   questions (contract edits, new top-level packages, out-of-glossary names,
   scope changes) alone. An _engineering_-shaped fork — one inside scope and
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
      If it repeats or is easy to repeat, fix the _class_: name it — a real
      class earns a principle — and guard it structurally, not just today's
      instance.
   3. **Can the bad state be made impossible?** Ask what let the broken
      state exist at all. Prefer a structural change that makes it
      unrepresentable (move data to its single owner; derive instead of
      duplicate) over a runtime guard that only watches for it. Guards are
      the backstop; structure is the cure (single-owner; derive-don't-sync).
   4. **Is the behavior I'm about to change pinned by a test?** Before you
      touch a seam, characterize what it does _today_ — including the
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
   (see _Probity gotchas_ below).

4. **Confirm the re-ground hook points at this plan** (`policy.md`, piece 6).

5. **Build each piece as a watched-fail TDD cycle:**
   - run the suite first (baseline green),
   - write **one** failing test; run it; watch it fail for the right reason,
   - if Probity demands it, add a stub that makes the symbol importable but
     still fails the _assertion_ (clean red), then write the real code,
   - run tests, then lint and types, and the formatter to tidy (the gate's
     format check blocks an untidied commit),
   - **commit** — small, often, and that is the LAW, not a preference
     (ratified by the human 2026-07-03: early catch beats batching; never
     batch commits to save review cost). Move this
     cycle's plan checkbox (`[ ] → [x]`) **in the same commit** — never as a
     later pass, because the plan is the one status source the re-ground
     hook re-injects and that every fresh agent reads, yet no other check
     here (Probity, pre-commit, RoboRev) reads it, so a checkbox that lags
     the code silently misleads the next (or compacted) agent,
   - per-commit reviews are ADVISORY in the moment (cadence ratified
     2026-08-31: the wall moved to the merge boundary). Reviews keep
     enqueueing on every commit — read a FAIL when it lands and fix what a
     later commit would compound — but nothing holds the next commit. The
     homework comes due at the PR boundary: run
     `roborev review --branch --base <integration>`, handle its findings,
     and respond+close EVERY open job on the branch — fixed → close;
     wrong or intentional → close-with-reason; clean bookkeeping →
     fold-closed by the merge gate as superseded by the branch review.
     **Batch the boundary fixes.** Every fix commit moves the tip and
     invalidates the branch review, so fix-one-rerun-review is a loop that
     converges only by luck (measured 2026-08-31: ~13 branch-review runs
     for one PR). The law: collect ALL of a branch review's findings,
     disposition each (fix or decline-with-reason), land the fixes as ONE
     batch, then rerun the branch review ONCE. A rerun that surfaces only
     already-ruled classes gets dispositions, not commits.
     The merge review gate (`cbr-core/scripts/merge-review-gate.sh`, run by
     the pre-merge-commit hook on auto-merges and by pre-commit when a merge
     is completed by hand) refuses the merge while the branch has open
     blocking findings, lacks a completed branch review spanning
     merge-base..tip, or carries more review-fix commits than the cap with
     no ruling on file.
     Max 3 fix rounds TOTAL (ratified 2026-08-31), then stop fixing:
     escalate, or exit by judgment — decline with recorded reasoning and
     surface the decline to the human for overrule. The asymmetry that
     justifies the low limit: a decline is reversible (reopening costs the
     human one glance at your reasoning) while an unbounded chain costs a
     full commit-review-fix lap per round. The gate counts every review-fix
     commit in the merge range; it cannot tell finding chains apart, so
     when the count is honest work — a genuinely NEW defect per round, not
     re-litigation — that is exactly what the escalation ruling records.
     Past the cap, record the ruling:
     `git config branch.<branch>.cbrEscalation '<who ruled what, when>'`.
   - if a review **crashes** (an infra failure — an overload, an auth lapse,
     a dead daemon — distinct from a FAIL _verdict_) it produced **no review
     at all**, so that commit is unreviewed: **re-run it, never skip** —
     request a fresh review of that sha and poll until it lands done (an
     up-front rejection costs ~nothing to retry — back off and retry).
     **Bound the loop:** if it keeps crashing ~5 times in a row, stop and
     wait — that is no longer a transient blip but a likely real outage (a
     provider incident, an expired auth token, a dead daemon), so surface it
     (flag the human / open a plan blocker) rather than hammering. Re-run is
     the default; infinite retry is not. The merge review gate holds the
     floor: a crashed or still-queued job on the branch is a blocker at the
     merge boundary, and no completed branch review means no merge. "It
     errored, move on" survives to the boundary and no further.

6. **Render and review a golden sample** when the work produces an artifact
   a human or an LLM will _read_ — see `reviews.md`.

7. **Update the plan as you go** (mark phases done; log errors) — it's your
   durable memory and the re-ground hook re-injects it. And keep a **friction
   log**: the moment the control plane itself wastes your time (a manual chore, a
   flaky gate, a missing provision step), write one line about it in
   `findings.md` right then. A control-plane retro is then a read of recorded
   artifacts, not a reconstruction from memory — and a friction that recurs
   across strands is the signal for an automation candidate.

8. **Checkpoint-review at each phase boundary** — mechanics and the
   contradiction taxonomy are in `reviews.md`. Fix load-bearing FINDINGS
   before starting the next phase.

9. **Closeout** when the build is done. First confirm every phase shows
   `reviewed == its end_sha` — a missing stamp means a checkpoint was
   skipped; do it now. Then run your project's end-of-work closeout ritual.
   The per-phase checkpoints catch issues _early_; they do **not** replace
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

   **Who merges — one rule.** The occupant of the target branch merges
   after GO; merges to main follow the HOST repo's binding branch law (who
   may merge there, and on what gates, is the host's call, not this
   process's). Git only allows a merge from a checkout sitting on the
   target branch, so ownership follows occupancy by construction — no
   transfer saga, no race: exactly one party CAN act. GO is permission, not
   the merge itself.

   **The merge and the closeout have different owners, on purpose.** The
   closeout REAPS the strand — worktree, branch, watch files — so it cannot
   be run by a session sitting inside the thing it destroys, and the leaves
   enforce exactly that (a closeout refuses to run from the checkout it is
   closing, and refuses a worktree anybody is still working in). So the
   builder writes its closeout NOTES and its completion marker; the tier
   above runs the closeout command afterwards, from the base checkout, once
   the builder is gone. Reading "the builder owns its
   ending" as "the builder runs closeout" produces a command that cannot
   succeed — see `modes/fleet.md`, which has always assigned the closeout
   command to the orchestrator.

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
   a control plane that runs more than one leaf implements them ONCE, shared, and
   calls that one implementation from each leaf. Two copies of a rule this
   quiet is two copies that drift, and the drift is invisible precisely
   because the failure shows up in the _next_ strand, not this one.

Probing an agent CLI (a liveness check, a version check)? Run it from an
empty scratch directory, never from a worktree carrying a plan: an agent
CLI launched inside a worktree reads the plan, adopts the builder role, and
writes false records — and a false control-plane-broken marker can convince a
watcher that a healthy strand is dead (field incident, 2026-08-27).

## Single-source records — one fact, one file (ratified 2026-08-29)

Every fact a strand writes down lives in exactly **one** record file. Every
other record that needs it **links to the owner** and never restates it.

The failure this closes is not untidiness. A fact written in two places is a
fact that will be wrong in one of them, with nothing on the page to say which,
and the reader who opens the stale copy acts on it. It cost this control plane a
status file whose ask list drifted three days behind the ask file while both
still looked authoritative — an orchestrator reading the wrong one would have
missed a parked question entirely. Two copies also make every review of those
records a wording review, because a reviewer that sees the same fact twice
must decide which is current, and cannot.

The default ownership, which a host may extend but not overlap:

- **the outside observer's fields** (state, phase, branch, blocked-on, last
  phase complete) → the STATUS record. Nothing else carries them in that form.
- **decisions, scope, phase checkboxes, the phase-checkpoint table, the
  endgame chain** → the plan.
- **the running narrative, the readback, per-phase evidence** → the progress log.
- **durable findings, ledgers, reconciliation tables** → the findings record.
- **open questions and the defaults being proceeded on** → the ask file;
  **answers** → the answer file.

This is a **mechanical** rule, so it is enforced mechanically or not at all: a
reviewer instructed to notice duplication is a reviewer who will notice it
sometimes. The host wires a commit gate driven by an ownership table — a
pattern per fact class and the file that owns it — and a fact matching outside
its owner FAILS the commit, naming the file, the line, the class and the owner.
A review row is not a substitute and does not discharge this.

Two properties that gate has to have, both learned the hard way:

- It **fails closed on its own infra.** It blocks commits, so an ownership
  table it cannot read is not permission to proceed.
- A pattern that matches **nothing in its own owner** is a stale class, and a
  stale class silently retires itself along with every duplicate it would have
  caught. That is louder than a violation, not quieter: it stops the commit and
  asks for a human, unless the table declares the record legitimately empty.

## Probity gotchas (so you don't fight the guard)

- **Baseline before a new test:** run the suite right before adding a
  behavior-asserting test, or the add is blocked.
- **One new test per write.**
- **Stub-then-real:** an import error is not a clean red. Add a stub that
  raises (or returns the wrong thing), watch the _assertion_ fail, then
  implement.
- **Minimal green:** implement only what the failing test needs; add the
  next branch via its own failing test.
- **The red must reference the change.** Probity reads the _failing_ test
  and only unlocks a production edit that would make _that_ test pass — an
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
  session blocks untested production code). The trap is a _mismatch_ — a
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
  so it must not be its own step.** Probity blocks it _correctly_: nothing
  behaves differently, only the contract changes color, and the only failure
  you can produce is a crash, which the rubric rejects as "not the right
  reason." Don't retry the edit and don't reach for an exception.
  Re-sequence: fold the shape change into the first step that adds the
  _real_ behavior it exists for, and lead with that behavior's failing
  test — the flip then rides in as the implementation that red demands.
  (The rubric's own clean-red recovery, "adjust the signature to reach the
  assertion," is exactly this path.)
- **A pure relocation (move code, no behavior change) should pass Probity's
  refactor rules.** If the fallible judge wrongly blocks one, that — and
  only that — is when a documented one-session exception is legitimate: the
  valve for a wrong verdict, not a way around an inconvenient red. Never use
  it for a shape flip; a blocked shape flip is a mis-sequenced plan, not a
  wrong verdict.
