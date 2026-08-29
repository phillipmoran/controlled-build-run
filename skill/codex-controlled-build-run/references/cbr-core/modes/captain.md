# modes/captain.md — the tier that dispatches the orchestrators

Part of `cbr-core`, the provider-neutral CBR law.

For an epic too large or long-running to babysit interactively, a
**captain** session sits one tier above the orchestrators: it dispatches
**one or more** orchestrators and owns the human seam for all of them (a
headless orchestrator can't reach the human — it escalates upward). The
point is **N:1** — the captain tracks every orchestrator so the human
watches one board, not N. It runs from the **primary checkout**, not a
worktree, so the leaf's fleet command shows it the whole machine-wide board.
A solo build or a single small fleet skips this tier — there the one
orchestrator talks to the human directly.

## Roles doctrine (ratified 2026-07-03)

An orchestrator session runs ROOTED IN THE REPO BEING BUILT — its re-ground
hook re-grounds it in THAT repo's docs, plan, and contracts, which is
worthless if the session is rooted somewhere else (a captain session parked
in a different repo re-grounds into the WRONG project after compaction,
then orchestrates from stale context). The captain is a SEPARATE,
deliberately small session: it reads status files, talks to the human, and
holds no build context worth compacting. To make that split work, **every
orchestrator maintains a status file as a standard CBR artifact** — build
name, current phase, state (running/blocked/done), blocked-on — updated on
every phase transition; the captain (and any dashboard that tails the same
file as an event source) watches THAT, never the orchestrator's transcript.
Wake for judgment, never for bookkeeping: the status file plus the commit
digest the watcher accumulates is what a captain reads at a wake; a
full-context wake per commit was the fleet's biggest measured token waste.

## The captain drives nothing itself — dispatch, watch, relay

- **Dispatch** each orchestrator as its own detached strand with the same
  mechanics (provision an orchestrator worktree on its integration branch,
  then launch), then stay out of its worktree — the orchestrator drives the
  builders. One captain runs several this way, each on its own integration
  branch.
- **Watch files, not the logs.** Each orchestrator appends its done-marker
  to its own phase-done doc when it finishes, keeps its status file current
  (the roles doctrine above), and creates a per-epic needs-human blocker
  file *only* for a real blocker — per-orchestrator so several can't
  collide, and the file's mere existence means "this orchestrator's human
  gate is blocking." Liveness is the leaf's status/fleet commands + commit
  age + file mtimes; raw session logs are escape-code soup — read them only
  to diagnose a confirmed death.
- **A completion marker must name the strand it belongs to, and a watcher
  must check.** The marker merges onto the base branch with the work; the
  next strand folds the base in and inherits a marker announcing that a
  build which finished days ago is complete. A watcher that latches on it
  exits, tells the human the build is done on the day it started, and leaves
  the builder with nobody looking at it for the rest of its run. Closeout
  deleting the marker from the base is the cure and this is the backstop,
  and a mistake this cheap to make deserves both. The asymmetry is
  deliberate: foreignness must be PROVEN, so a marker naming no branch
  counts as the watcher's own. A missed latch is loud — the stall fires and
  a human looks — while a wrongly disarmed completion signal is silent. The
  same asymmetry covers the watcher's own side of the comparison: a worktree
  whose branch cannot be read (a detached head, most often) gives the watcher
  no basis to call anything foreign, so there the marker counts as its own
  too. A watcher that reads its branch as the literal word for "detached"
  and then finds every marker foreign has disarmed itself, silently, for the
  rest of the run.
- **One watcher line** — silence = alarm, so the watcher must exit on the
  bad paths too, not just the happy one. For N orchestrators, wake on ANY
  blocker file appearing OR when nothing is still working (covers all-done
  and stall together — disambiguate at the wake with the fleet board +
  commit age). One background watcher, one notification. No persistent
  pulse loop and no bespoke parser — those are the over-build this tier
  keeps drifting into; promote the line into the leaf's watch tooling only
  once you've typed it enough to earn it.
- **Wake-cadence dial (2026-07-07).** Three distinct layers, tuned apart
  because they watch different things: per-builder **STALL = 15 min** (a
  healthy builder is never silent that long); the **watcher dead-man = 15
  min** (watches the watcher process, not the builder); and an **outer
  heartbeat ~60 min** — a coarse scheduled wake that only earns its keep in
  the rare all-watchers-dead case, so it runs slow. Don't collapse the
  outer heartbeat into the stall: one alarms on a silent builder, the other
  is the backstop for the alarms themselves.

## Liveness tips — telling a hung session from a healthy idle

The core outside-watching discipline (weigh reported state *with*
commit-age; key a wait on latching ground truth — a new commit sha — never
a fixed countdown or another session's reported state) is in
`modes/fleet.md`; it holds one tier up unchanged, so the captain keys its
watch off the **builder's** progress, not off orchestrator-idle. Two
captain-specific additions:

- **Never foreground a blocking watcher.** A detached session that runs an
  endless sleep-loop as a normal (foreground) call **wedges itself** — the
  call never returns, the transcript freezes, and it reports working while
  doing nothing. Always background the watcher.
- **Parked ≠ wedged, though they look identical.** Both show ~0% CPU, a
  frozen transcript, and a working state — those metrics alone can't
  separate a healthy session parked at the clean end of its turn from one
  hung on a foreground loop. Two cheap tells do: **process tree** — a wedge
  has a blocking sleep child, a parked session has *no children*; and the
  **last transcript entry** — a wedge's is mid-flight (a tool call awaiting
  its result), a parked session's is a completed assistant turn. *Wedge:*
  kill the **watcher subtree** (not the session pid) — control returns to
  the blocked call and it resumes warm; then neuter the watcher to
  one-shot. *Parked:* don't kill it — but it won't self-wake, so the
  captain re-pokes it (relaunch-from-git) when the work it waited on is
  ready.

## The human's gates are the captain's to surface, never to cross

Design/mock approval and contract ratification (per stream, and at the
final merge to main) belong to the human. Relay on transitions — a stream
merged, a blocker raised, the epic done — not on a clock.
