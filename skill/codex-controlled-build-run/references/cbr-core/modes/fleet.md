# modes/fleet.md — orchestrating a fleet of streams

Part of `cbr-core`, the provider-neutral CBR law. Applies only when you are
the ORCHESTRATOR of several streams at once — one human ask that fans into
many streams (an epic). A solo build skips this file (`modes/solo.md`); the
single-strand rules hold per stream regardless. This is the layer above
them: how one orchestrator drives many strands whose dependencies decide
which can run when.

**Stream** = one node in the dependency graph: a single unit of parallel
work (one function, one view, one slice), built in its own strand. Stream
and strand are two views of the same 1:1 thing — *stream* is its role in
the graph (what it depends on, what it unblocks), *strand* is its isolation
(its branch, worktree, session, plan). The plan each stream is built from is
its **stream plan**; the orchestrator's own plan is the **fleet plan**.

## The orchestrator is its own strand

It runs from its OWN worktree on its OWN branch — an **integration branch,
never main** — with its own `task_plan.md` (the fleet plan) marked
`**Run type:** orchestrator` at the top. Two reasons: (1) it keeps the batch
off main, so a *second* orchestration batch can run later without colliding;
(2) the re-ground hook reads `task_plan.md`, so the orchestrator's live
state — the graph below — survives its own compaction. Set it up with the
same strand steps (the leaf's provision command). The orchestrator writes no
gated production code, so Probity never gates it; its edits are the fleet
plan, the merges, and read-only monitoring. (The `**Run type:**` line is a
human/glance aid — the re-ground hook injects the process text whole
regardless; it does not branch on the marker.)

**Builders merge into the integration branch, not main.** Cut each stream's
branch FROM the integration branch so it inherits every gate the branch
carries (the gate-inheritance law below). A finished, reviewed stream merges
back into integration. **Main gets ONE merge at the end of the epic, with
the human's sign-off** — never a per-stream push to main. That epic merge
sits outside the branches a leaf's per-commit review hook watches on some
installs, so it is reviewed like everything else BY EXPLICIT ORDER: enqueue
the merge commit's review yourself and confirm it completed before calling
the epic closed (a downstream deployment found both of its epic merges
silently unreviewed, 2026-08-26).

And it is the BUILDER that performs its own merge into integration, once GO
comes back through the file channel — the merge only; the closeout command
stays yours, because it reaps the worktree the builder is sitting in. One
standing exception, from `build-loop.md` step 9's occupancy rule: if YOUR
checkout sits on the integration branch — the common fleet topology — git
makes the builder's merge impossible, and the merge transfers to you with a
handoff note; either expect that every time, or park your checkout off the
integration branch so the builder's GO-merge stays satisfiable. Granting GO is permission, not the merge; an
orchestrator that answers GO and then merges too is racing its own builder,
which happened twice on 2026-08-19 and was harmless only by luck. Take the
merge over only when the builder is PROVEN dead — no live session and no
live process rooted in its worktree — and record that you did.
`build-loop.md` step 9 carries the rule and the reasoning.

## The live post-merge smoke is a MANDATORY merge-gate step

(Law since 2026-07-03, ratified after it caught every ship-stopper of the
2026-07-02→03 run.) After merging a stream into integration — and again
before the final merge to main — the orchestrator runs the product's REAL
entry path against the merged tree, live: real process, real machine, real
data flowing, not the unit suite and not a fixture. Unit-green ≠
product-works: that night every module was tested in isolation and green
while the product recorded nothing, the daemon spoke a wire shape the UI
dropped, the client threw away every mid-stream batch, and a fresh home
crashed on a missing mkdir — FOUR ship-stoppers, all caught by the live
smoke, ZERO by the suites. The smoke's shape is per-product (documented in
the fleet plan): what to run, what observable proves life (events flowing, a
page rendering, a daemon answering), and its time budget. A failed smoke
bounces the merge exactly like a failed review — fix test-first on the
stream, re-gate. Merging on green suites alone is a skipped-gate violation,
not a judgment call.

## Closeout is the final merge-gate step

**A merge is not complete until the stream's remains are gone (law since
2026-07-09).** The merge is the moment a stream's worktree, branch, and
watch files become trash; teardown rides that same moment so nobody has to
remember it later (17 dead worktrees accumulated before this rule existed).
After the post-merge review closes, the orchestrator runs the leaf's
closeout command: it refuses a live session, refuses unmerged code, refuses
uncommitted files until a human has eyeballed them, archives the stream's
bookkeeping to the streams archive — the builder's narrative lives ONLY on
the stream branch, so archive-before-delete is what makes branch deletion
lossless — then reaps the worktree, branch, and watch files. In the same
motion, rotate the stream's closed sections out of the fleet
`task_plan.md`/`progress.md` into the archive: the live plan holds standing
law + active work only, because it is re-read and re-injected constantly and
every dead section rides along forever. Uncommitted files that look like
real work are NEVER force-reaped — they go to the human. As the backstop
for leaks (crashed sessions, abandoned experiments), the orchestrator runs
the leaf's janitor command at merge gates and on request — no scheduler, it
never runs on its own: a read-only reconciliation report (reapable
worktrees, orphan branches, stale watch files); a human approves each reap.
Provision is the birth ritual; closeout is the death ritual; the janitor is
the audit between them.

## The depth scan — run it when the work touches existing modules

When the fleet's work will change pre-existing code — refactors, or features
landing in modules that already exist — the orchestrator runs a **depth
scan** twice: once at plan formation (its findings shape the stream
assignments) and again at each phase boundary, over that phase's merged
diff. Skip it when a plan or phase touches no modules (docs, harness
config, isolated greenfield code) — a scan with nothing to find invents
findings.

The scan is a written method, not a tool dependency: walk the touched code
and ask where understanding one concept forces bouncing between many small
files; where a module's interface is nearly as complex as its
implementation (**shallow**); where helpers exist only to satisfy a
metric. Apply the **deletion test** to anything suspect: would deleting it
concentrate complexity behind one interface, or just relocate it? Prefer
**deep modules** — much behavior behind a small interface at a clean
**seam**.

Scan findings are ADVISORY, always — module depth is judgment, and
judgment may only surface, never gate. At plan formation they become
stream framing ("deepen module X behind interface Y", not "get function Z
under the ceiling"); at a phase boundary they go into the acceptance
package or the next phase's work. A deterministic complexity ceiling, where
the host repo has one, is the gate; the depth scan is what keeps builders
from satisfying that ceiling by shredding one deep function into shallow
pass-through shims.

## The fleet plan holds the dependency graph

In the orchestrator's `task_plan.md`, a stream table is the source of truth
for what may run when:

| Stream | Scope | Branch | Depends on (merged first) | Files it owns | Status |
|--------|-------|--------|---------------------------|---------------|--------|
| s0-time | V4 wire+render | stream/views-s0-time | — | the wire envelope, the label sites | pending |
| s1-rail | V1 | stream/views-s1-rail | s0-time | the timeline component | pending |

Two kinds of edge go in **"Depends on":**

- **Real dependency** — the stream reads something an earlier stream adds.
- **File-collision edge** — two streams that would edit the SAME file get an
  artificial dependency so they serialize, even when logically independent.
  Build a collision matrix from every plan's "Files it owns"; any overlap
  becomes an edge. This is how you avoid the merge-storm of two frontier
  builders editing one shared file in parallel.

**Dispatch is a topological sweep, not hand-scheduled waves.** Dispatch
every stream whose dependencies are ALL merged and that has not started, up
to the concurrency cap. When a stream merges into integration, re-evaluate
the graph and dispatch whatever it just unblocked. The in-flight count
flexes on its own — you read the graph, the graph does not read you.
**Concurrency cap: 2–3 frontier builders** (past ~3 at once you outrun both
the budget and your own ability to watch them honestly from outside). Raise
it only with a reason. The orchestrator re-derives the dispatchable set from
the table on every wake, so a compacted or restarted orchestrator picks the
run back up from files, not memory.

**Every stream plan passes the plan-review gate BEFORE its builder
launches** — the gate, the panel rule, the fleet-level review, and the
2-round cap are in `reviews.md`, with the exempt-zone law.

**Log every resolved decision in `findings.md`.** When a panel (or the
human) resolves a fork, write it to that stream's `findings.md`: the
question, the recommendation, the resolution, the date. `task_plan.md`'s
in-flight decision log is overwritten each session; `findings.md` is durable
and archives with the plan, so it is the lasting record of WHY the build
went the way it did. (A headless builder writes its question into the
plan's open-with-the-human section and keeps working; the orchestrator runs
the panel and logs the resolution here.)

**Retire each finished stream with its findings.** At epic close, every
completed stream's `task_plan.md` AND its `findings.md` retire to the plans
archive — for an orchestrated stream, findings always archive (they carry
the decision record, not just scratch), overriding the "only if warranted"
default in `build-loop.md` step 9.

## Orchestrated dispatch — the three invariants

Every builder runs by three invariants: **on-plan** (billed on the
subscription plan, never an off-plan API/SDK mode), **detached** (a
supervisor-parented background session that survives the orchestrator), and
**watched from outside** (ground-truth liveness; silence = alarm).

The deterministic mechanics are bundled as the leaf's **companion script**,
one obvious subcommand per moment of the build lifecycle: *arm* (scaffold
the harness once per repo, create-if-absent never clobber, ending with the
operability probe — guarded ≠ operable), *doctor* (the standard pre-flight
before EVERY build: read-only PASS/FAIL on every piece, including the one
silent killer static checks miss — an expired auth token, caught only by a
real agent round-trip), *provision* (worktree + gitignored deps + the
armed-checks), *launch* (the detached dispatch + supervisor-registration
check, surfacing the model/effort before it spends a token, ending with a
REQUIRED watch-arm directive), *watch* (the fire-once trap on the builder's
progress), *status* (one-shot outside-view liveness), *fleet* (the whole
board, role-aware). Each subcommand follows one law — **gather facts, run
the fixed sequence, decide nothing**: it fails closed on a hard fact, never
auto-merges/relaunches/kills, and never prints a health verdict (you read
the facts and make the call). There is deliberately no "do everything"
command. The script is the hands; this text is the policy — if the script
vanished, the steps must still be hand-executable from the leaf's
documentation.

- **A builder that writes production code is a real, independent session
  ROOT — never an in-session subagent.** Hooks may fire for subagents, but
  the TDD guard gates only the root of the session that loaded it: a
  subagent (or the orchestrator itself) editing files in another worktree is
  unguarded. So a builder needs its own session rooted in its worktree, and
  the session must be **on-plan**, **detached**, and **launched
  explicitly**:

  - **On-plan.** Headless/API dispatch modes that bill outside the
    subscription plan are not the pipeline's foundation; the leaf documents
    which session type is both on-plan AND a real session root that the TDD
    guard binds to (proven by a live blocked-write probe, not assumed).
  - **Permissions skipped, the real guards kept.** An unattended builder
    writes compound shell (poll loops, command substitutions) that a
    permission prompt layer stalls on by STRUCTURE — no allowlist can match
    a loop, and no human is there to answer (observed cost ~11 min/stall, 2026-06-20).
    The leaf's dispatch removes the prompt layer entirely; the real guards
    are HOOKS, not permissions, so they all still bite: the TDD guard, the
    pre-commit gate, per-commit review. The boundary moves from "ask a
    human" (impossible unattended) to "fail-closed gates + the worktree
    sandbox" — the correct model for an autonomous agent. Pair it with the
    **push firewall**: a pre-push hook that denies a stream-branch push
    unless an explicit override variable is set — re-closing the one
    boundary prompt-skipping opens (a push to main can auto-deploy prod)
    with a hook, immune to the skipped prompts, scoped so the human's own
    pushes are untouched.
  - **Detached.** Not a background child of the orchestrator's shell — a
    child dies with its parent's process group (lived 2026-06-20: an overnight run
    lost BOTH builders and the heartbeat monitor within 30s when the
    controlling session ended at ~2 AM; ~6.5h wasted, saved only because
    every builder's work was in git). The law: the builder must not share
    fate with its dispatcher, and its liveness must be readable from a
    durable source outside the builder's own process group. The leaf's
    detached-session primitive supplies both — typically by handing the
    builder to a supervisor that parents it and keeps a queryable registry,
    but whatever the mechanism, launch must confirm the builder actually
    registered with it, rooted in the worktree (silence there is an alarm),
    and that outside source — not the builder's own output — is what
    liveness is read from.
  - **Past any one-time trust/consent gate BEFORE dispatch, not rescued
    after.** A headless session has no pane to answer an interactive
    first-run prompt; make the prompt never fire (dispatch only into a
    worktree of an already-trusted repo — trust is keyed by the repo, not
    the worktree path). A builder stuck on such a gate is stopped and
    re-dispatched from a trusted path, not rescued interactively.
  - **Launched explicitly + surfaced.** Always pass model and effort — a
    session inherits the machine default, NOT the orchestrator's model
    (caught live 2026-06-11: two builders silently booted on a small model). The values
    come from the leaf's dial. **State them to the human BEFORE launch**
    (per builder: model, effort, where pinned); a builder whose model was
    never surfaced is a dispatch bug. If one is found on the wrong model:
    stop it, reset its worktree to the last good commit, close its reviews
    with a reason, relaunch, and audit that nothing it authored survives.

- **Gate inheritance — a builder branch must CONTAIN every tracked gate.**
  The deterministic gates that live in *tracked* files only bite on a branch
  that *contains* them. A branch forked before a gate was added runs the old
  honor system even though its hook files are armed — the wall isn't in its
  tree. So: cut each builder branch from its base per this mode's branching
  rule — in a fleet, from the current integration branch (which is itself
  cut from, and refreshed against, current main, so gates flow
  main → integration → stream); solo, from current main directly. Before
  **relaunching** a long-lived branch, merge or rebase its base into it
  first so it inherits any gate added since it forked. When a pre-gate
  branch can't be refreshed in time, the merge gate is the backstop: the
  orchestrator verifies zero open reviews by hand before merging, and from
  that merge forward every new branch carries the wall.

- **The dispatch prompt** says: run this process off the worktree's
  `task_plan.md`; the contract is the only source of truth; read and touch
  nothing outside this worktree; a headless session cannot ask the human
  questions, so write blockers and open questions into the plan's
  open-with-the-human section and keep working everything else — never
  block on an interactive prompt; the orchestrator triages each
  (engineering calls to a panel, vision calls to the human — `judgment.md`);
  and **before anything else, write the readback** — mission, locked scope,
  and OUT list, in your own words, into `progress.md` (`build-loop.md`).

- **The readback is checked before the builder is left to run.** The
  orchestrator reads the new builder's `progress.md` against the plan at the
  first watch tick: is the mission the plan's mission, is the OUT list
  intact, is anything the plan forbids described as in scope. A drift found
  here costs one message; the same drift found at a phase checkpoint costs
  the phase. A missing readback is itself the finding — a builder that
  skipped it is a builder that skimmed the plan.

- **In-session subagents stay for what they're safe at:** read-only work
  anywhere (research, checkpoint reviews, golden-sample reads) and gated
  edits inside the orchestrator's own root.

## Watching from outside

The orchestrator monitors against this process's own checklist, from
outside: did the readback land and match the plan, did the harness probe
run, does every commit ride a watched-fail test, are the phase-checkpoint
stamps current, are review findings closed
(the git log, the plan's checkboxes, the review daemon's list). Vision-shaped
calls found in the builder's open questions go to the human, never answered
by momentum; engineering-shaped calls the orchestrator resolves itself with
a panel (`judgment.md`).

**Zero open FAIL reviews on the branch is a hard merge-gate checkbox** —
verified in the review daemon, never inferred from commit messages.
(Observed 2026-06-11: two independent builders fixed every finding — fix commits even
cited the review numbers — yet never closed the reviews, so fixed reviews
sat open.) The orchestrator either closes-with-evidence (fix commit +
passing re-review) or bounces the branch back.

**Surfacing cadence (ratified 2026-06-11): silence is the failure mode.**
While builders run, the orchestrator keeps a live watch (commits,
open-question changes, process exits — an armed watcher, not manual
polling) and reports to the human: new open questions as they appear, phase
checkpoints as they land, and a pulse at least every ~15 minutes
regardless. Fifty quiet minutes means the human is flying blind, not that
the orchestrator is being polite.

**The watchdog must be independent of the watched, and silence is an ALARM,
not a pass (added 2026-06-20).** Two failure modes bit at once: the monitor
was co-located with the builders, so when the controlling session died the
monitor died with it — and its last heartbeat ("RUNNING, 4 commits") was
then misread as health for ~6 hours. Both fixes are required. (a) Run the
liveness watch from OUTSIDE the builders' process group — the leaf's
durable outside liveness source (typically a session registry; whatever it
is, the builders must not share fate with it) plus the orchestrator
re-deriving state from scratch each time it wakes — never a heartbeat that
shares the builders' fate. (b) Assert liveness from GROUND TRUTH, never the
last pulse: the session's registry state and its cwd rooted in the
worktree, commit timestamps advancing, session-log mtime moving. The leaf's
status command gathers exactly these from outside in one shot and exits
non-zero on a hard-dead fact — but it prints facts, not a verdict: a gap
past your interval is itself the page — check and recover, don't assume
"busy." Plan-usage % is NOT a liveness signal. (c) **Registry state is only
as honest as the session's children — an orchestrator's own watch must not
corrupt it.** A detached session reads as working while ANY child shell of
it is alive, so a leftover watch loop holds a session falsely working long
after its work is done (observed 2026-06-23: ~25 min on a stray sleep-loop). Two
consequences: weigh state WITH commit-age (working + a stale last-commit is
the page, not a pass); and when the orchestrator waits on a builder, key
the wait on GROUND TRUTH that latches — the builder's new commit sha — and
break the instant it appears. NEVER a fixed countdown (it outlives the
event), and NEVER gate the exit on another session's reported state (it can
stay falsely working, so the watch hangs on the very bug it should catch).
(To tell a genuinely hung session from one merely parked at a clean end of
turn, see the parked-vs-wedged discriminator in `modes/captain.md`.)

**The orchestrator keeps no state that lives only in its context.** The
streams ledger row records what was dispatched (branch, worktree, status);
the worktree's `task_plan.md` is the builder's own state; commits and the
review daemon are the audit trail. An orchestrator that gets compacted
re-derives everything from those — and the builder survives its *own*
compactions via the re-ground hook. Files carry the run; no context window
is load-bearing.

**Recovery is relaunch-from-git, not restart-from-scratch.** Because work
is durable in commits and the next step is in the worktree's `task_plan.md`,
a dead or wedged builder is recovered by relaunching it on its own branch
with a one-line resume note ("you're resuming; earlier phases are
committed — read the git log + your `task_plan.md` and continue from the
next unchecked phase"). It re-grounds and continues; nothing is redone —
the whole payoff of commit-small + plan-in-files. Cap relaunches and guard
the loop: if a builder dies repeatedly at the SAME phase (a poisoned
commit, a real blocker), stop relaunching and surface it — a restart storm
hides the cause.
