# strand.md — one plan, one worktree (isolate before you build)

Part of `cbr-core`, the provider-neutral CBR law.

## The strand

Every non-trivial plan gets its **own worktree on its own branch**, with the
build session **rooted in that worktree**. The control plane binds to a _folder_,
so a misrooted session guards and re-grounds the _wrong_ plan.

**Why:** the re-ground hook reads `task_plan.md` from the session's worktree
root, and Probity only guards the gated tree under the session's own root.
Sit in the wrong folder → wrong plan re-injected, unguarded edits. Two plans
at once need two worktrees, or they collide.

We call the bundle a **strand**: one branch ↔ one plan ↔ one folder ↔ one
session. It is the unit of isolation — every build, solo or orchestrated,
runs in exactly one strand.

## Set up the strand (one-time)

The leaf's provision command does these deterministically (printing PASS/FAIL
per check, failing closed); the steps stay written out here because the
script is the hands, not the policy, and because the live gate probe (step 3)
is yours to run in-session regardless. By hand:

1. **Make the folder + branch** (`git worktree add` from the repo root), then
   **provision the gitignored deps the gate needs** — a fresh worktree has no
   installed dependency trees, yet the pre-commit hooks run unconditionally,
   so the builder's _first_ commit dies on missing toolchains. Link or build
   the dependency trees per the leaf's provision recipe before anything else.
   Stack-specific prep beyond the leaf's recipe belongs in the **project prep
   hook** — `.cbr/provision-hook.sh` at the primary repo root, run by every
   leaf's provision inside the new worktree with `(repo, worktree)` as
   arguments. Absent is the normal case; a present hook that fails fails the
   provision, because a half-prepared worktree is the trap this exists to
   remove. The hook is per-project and never ships in the kit — the kit ships
   only the socket and examples.
   Provision also owes the newborn two more duties (shared mechanics in
   `scripts/strand-lib.sh`): **reset stale records** — the worktree inherits
   the base's `STATUS.md`/`DONE-*.marker`/ASK-ORCH leftovers, and a watcher
   that glances at a dead strand's "COMPLETE" believes a build that never ran
   — and **pin the base** (recorded at birth, asserted at launch with
   `merge-base --is-ancestor`) so a branch that grew from the wrong place is
   refused before dispatch instead of discovered mid-build.
2. **Put the plan in it**, and write the branch at the top of
   `task_plan.md`: `**Branch:** <branch>` — so anyone landing there knows
   where they belong.
3. **Check the control plane in that folder:** pwd/branch right, and a Probity
   probe (untested prod code → must be blocked) confirms the hooks bite here.
4. **Prove the session can actually _build_, not just that it's guarded.**
   Step 3 proves the gate says _no_; this proves the path says _yes_. Run one
   real toolchain command and make one throwaway allowed edit (a write you
   then delete) — both must succeed. A dispatched builder running unattended
   under a prompting permission layer silently blocks its toolchain, its
   commits, and its edit tools; with no human to approve, it passes the whole
   probe and then stalls dead. How the leaf removes the prompt layer for
   unattended runs (and what compensating guard re-closes any boundary that
   opens) is leaf content — the law is: an unattended builder must never be
   able to stall on a prompt no one will answer, and removing prompts must
   never remove the fail-closed gates, which are hooks, not permissions.

**Every time a session opens (and after every compaction):** confirm the
current branch matches the plan's `**Branch:**` line, AND the control-plane check
passes (Probity blocks an untested write). If either fails, you're in the
wrong place — stop, don't build.

## Plan altitude — decision-dense, implementation-sparse

A plan is a **contract, not a script**: it fixes the _decisions_ and the
_acceptance bar_ and leaves the _implementation_ to the builder. A frontier
builder executes it faithfully and expensively, so the plan is where the
cheap review pays off — get the decisions right, not the keystrokes. Two
failure modes bound the altitude:

- **Too abstract** ("animate the merge", "fix the recorder") makes the
  builder re-derive decisions you already made — which event, which field,
  the threshold, the color, the determinism seed — burning its most expensive
  cycles re-litigating settled design and inviting drift. A plan that won't
  converge at the review gate is usually this: the view is under-specified.
- **Too concrete** (line-by-line pseudocode) is brittle the moment the code
  doesn't match your assumptions, wastes what the builder is _for_, and means
  you wrote the logic yourself — outside Probity's write-time guard.

**The sizing rule:** one step is **one behavior** — roughly **≤400 lines of
product diff**, green at its end, revertable as a unit. A step that cannot
fit is split **at planning time**; discovering the split mid-build means the
plan was written at the wrong altitude, and the most expensive reader found
it first.

**The sweet spot:** each build step names its **observable outcome**, the
**watched-fail test that proves it** (test-first), the **decisions already
locked** (event carrier, field, threshold, color, seed, the `file:line`
anchors), the **files it owns**, and its **verification command** — then
stops. Resolve every open design fork _before_ dispatch (park human-only
ones in _Open with the human_); a builder must never start on an unresolved
fork, or it becomes a 4am guess. The plan-review gate's mechanical criteria —
test-drivable steps, perceivable fields named with their binding rule,
verification present — exist to pull a plan to this altitude: treat them as
the floor and write the decision-density in on purpose.

## Zero-context plans — write for a reader who was not in the room

A plan is read by agents who have none of the conversation that produced it:
a dispatched builder that has never spoken to the author, the same builder
after a compaction has replaced its memory with a summary, and the reviewers
at the plan gate and the phase checkpoints. **`task_plan.md` must therefore
stand entirely on its own.** Concretely:

- **No reference to a conversation.** "as we discussed", "the approach the operator
  preferred", "per the earlier thread", "the option we picked" — every one of
  these is a dangling pointer to something the reader cannot open. Write the
  decision, not the fact that a decision happened.
- **Every constraint stated, not implied.** If a path is untouchable, say
  which and why. If a sibling build owns a directory, say so. A constraint
  that lives only in the dispatcher's head is a constraint the builder will
  break in good faith.
- **Every "why" spelled out**, especially for the rejected alternative. A
  builder that cannot see why the obvious approach was rejected will re-derive
  it, choose it, and be right on its own evidence.
- **Taste gates written down.** "Matches the existing style" is unreadable to
  someone who has not seen what you saw; name the file, the rule, and what a
  violation looks like.
- **Absolute over relative.** Dates, SHAs, paths, versions — "the current
  behaviour" and "last week" both rot the moment the plan is read late.

The test: hand the plan to a competent stranger with repo access and no chat
history. If they must ask a question before they can start, the plan is not
finished. This is a **plan-review criterion** (`reviews.md`), not a private
habit — but it is a reviewer's judgment, so it surfaces at the gate and is
never machine-gated.
