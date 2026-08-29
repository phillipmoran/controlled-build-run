# acceptance/checklist.md — the neutral CBR acceptance contract

Part of `cbr-core`. Merged from both leaves' acceptance contracts; each
leaf's full acceptance = these core rows + its own leaf rows. Every line is
an **invariant**: a thing that must be TRUE for a safe extended run, written
so a smoke test can prove it. A box that can't be proven is a gap, not a
style note.

**Three rules keep this lean and complete:**

1. **One row, one test.** A row exists only if breaking it turns a distinct
   test red, and no two rows share a test. A mega-row that hides five
   guarantees behind one checkbox is the bloat.
2. **Assert a property; test the LIVE artifact — never enumerate.** A row
   says "the pre-commit gate passes end-to-end against the live config,"
   not a tool list. Enumeration goes stale; the live verify stays complete.
3. **Scar detail lives elsewhere.** The checklist holds the testable
   guarantee; the why/story stays in the law files, found by search.
   Completeness is enforced by the **mutation probe** (`mutations.md`),
   never by line count.

**How to read a row:** `[when] (marker) ID — assertion.` *test:* the
smallest thing that fails if it breaks.

- **`[when]`** — when re-checked: `epic-start` · `per-dispatch` ·
  `per-commit` · `per-phase` · `per-monitor` · `per-merge` ·
  `per-compaction` · `boot` · `closeout` · `continuous`. `per-dispatch`
  re-fires for **every** strand at its own unlock, not once at epic start.
- **`(leaf-row)`** — the invariant is real for every leaf, but its
  enforcement mechanism is provider-specific: the core row states the law
  and the leaf's own acceptance file supplies the mechanical row (flag
  names, hook events, registry commands) that proves it.
- **`(TO BUILD)`** — the guarantee is real but its mechanical enforcement
  does not exist yet in a given leaf; each leaf tracks its own unbuilt set.

**Scope:** the fleet/epic flow. A **solo run** is the degenerate case — one
stream, no integration branch, merges straight to main; rows tagged
`[epic-start]`/`[per-merge]` collapse accordingly.

## Definitions (load-bearing nouns only)

- **strand** — one branch ↔ one worktree ↔ one session (rooted there) ↔ one
  `task_plan.md`. The unit of isolated work.
- **orchestrator (strand)** — drives an epic: fleet plan + human/panel seam
  + dispatch + merges. Runs on the **integration branch**. Writes no gated
  production code.
- **workstream / builder (strand)** — writes production code off its own
  **stream plan**.
- **fleet plan / stream plan** — the orchestrator's / a builder's
  `task_plan.md`, marked by its `**Run type:**` line.
- **integration branch** — the epic's staging branch; streams cut from it
  and merge back; it merges to main once, at epic close, with human
  sign-off.
- **blocking finding** — a *decidable fact* that fails a plan: a
  mechanical-criterion miss ∪ a cross-stream collision ∪ a fleet-graph
  violation. Panel design opinions are **advisory**, never blocking, unless
  the opinion is itself a verifiable fact.

## P. Core-and-leaf parity

- [ ] `[continuous]` **P1** — every section of the canonical law is
      accounted for in the core's coverage map (core / leaf / not-ported
      with reason); an unaccounted section is a blocking gap. *test:* the
      coverage map's rows tile the source with no orphaned range.
- [ ] `[continuous]` **P2** — the strong-law sentences (harness memory,
      deterministic vs fallible gates, compaction, strand isolation,
      frequent commits, crashed reviews, independent writer roots,
      file-backed recovery, silence-is-alarm, watchdog independence) remain
      explicit in core, never condensed away. *test:* each names a live
      sentence in a core file.
- [ ] `[continuous]` **P3** — no provider primitive survives in core (the
      neutrality lint's two lists); every leaf runtime block names its OWN
      harness's actual mechanism, never another leaf's. *test:* the lint is
      green on core; a leaf file naming the other leaf's primitive fails
      that leaf's own parity check.

## A. Strand & isolation

- [ ] `[per-dispatch]` **A1** — every unit of work (orchestrator included)
      is a strand, with the three planning files at the worktree root.
      *test:* current branch == the plan's `**Branch:**` line; session cwd
      is the worktree; the three files exist.
- [ ] `[per-dispatch]` **A2** — `task_plan.md` declares identity:
      `**Run type:** orchestrator|workstream` and `**Branch:**`. *test:*
      grep both; Run type ∈ {orchestrator, workstream}.
- [ ] `[per-dispatch]` **A3** (leaf-row) — no builder pushes: the pre-push
      firewall denies a stream-branch push unless the explicit override is
      set; any worktree-local permission file is gitignored. *test:* the
      hook denies from a stream worktree (stdin fixture, no remote
      round-trip); the local file is ignored.
- [ ] `[continuous]` **A4** — concurrent strands do not collide: a
      builder's TDD guard covers only its own folder's gated tree (root
      resolved at runtime); one builder's open review never blocks
      another's commit (the clean-gate is branch-scoped); on compaction
      each builder is re-injected its OWN plan, never a sibling's. *test:*
      with two live strands each holding an open review + an untested
      write, each strand's gate/guard/re-ground acts only on itself.
- [ ] `[per-dispatch]` **A5** — launch refuses a second live writer in the
      same worktree. *test:* a second launch into an occupied worktree is
      refused.

## B. Harness armed (assert + test against the LIVE config)

- [ ] `[per-dispatch]` **B1** (leaf-row) — all harness hooks are ARMED in
      the *live* config, proven each against it (never a hard-coded list):
      the TDD guard **pinned to a fixed version, never floating** (a
      floating guard can shift enforcement mid-run), the session sweep, the
      compaction re-ground on an event that can inject context, the
      per-commit (and post-rewrite) review triggers, the interactive-ask
      guard. Arming **merges** into existing settings and never clobbers a
      richer live hook; hook paths resolve worktree-correctly (a worktree's
      `.git` is a *file* — a literal path check lies). *test:* each hook
      present in the resolved live config; the path check works in a linked
      worktree.
- [ ] `[per-dispatch]` **B2** — the full pre-commit gate passes end-to-end
      against the **live** config, and deps are provisioned so it can (a
      fresh-worktree first commit must not die on missing toolchains).
      *test:* the all-files run passes; no hook exits 127 in a fresh
      worktree.
- [ ] `[per-dispatch]` **B3** — fail-direction is split by *what failed*:
      surfacing infra fails OPEN; deterministic inability to prove
      review/TDD/commit safety fails CLOSED (and the TDD guard's own infra
      failure fails CLOSED — `policy.md`'s exception). *test:* kill the
      review daemon → the clean-gate blocks with an infra message; a
      missing optional surfacing tool does not block the edit.
- [ ] `[per-dispatch]` **B4** (leaf-row) — a fresh strand proves BOTH guard
      and ability, after pre-warming any cold guard fetch (a cold fetch can
      exceed the hook timeout and fail open → false prove-NO): an untested
      gated write is BLOCKED (prove-NO); one real toolchain command + one
      allowed write SUCCEED (prove-YES); every write path the leaf's agent
      can use (direct edit, subagent, patch mode) is exercised. *test:* the
      probes, cache warm first.
- [ ] `[per-dispatch]` **B5** — gate inheritance holds: a strand is cut
      from a base that already contains the tracked-file gates; a branch
      cut before a gate existed runs the old honor system and must be
      refused launch. *test:* a pre-gate branch is detected and refused.

## C. Orientation & compaction

- [ ] `[boot]` **C0** — a fresh (non-compaction) session runs the repo's
      full boot ritual before work, reading the newest handoff (fresh boot
      only — a *resumed* run does not switch to it). *test:* a cold session
      reads the boot set before its first edit.
- [ ] `[per-compaction]` **C1** — re-ground re-injects the **live** section
      set the hook actually emits, whole: the binding docs, the process
      text, and — only when a plan exists — the plan itself; larger
      contextual documents (glossary, contracts) are *pointed at*, never
      pasted whole. It states the agent already booted (no boot-ritual
      re-run, no handoff switch).
      *test:* a forced compact injects every live section (grep anchored
      headers, asserting the live count, never a hard-coded number); the
      resumed session continues without re-booting.
- [ ] `[per-compaction]` **C2** (TO BUILD in either leaf that lacks it) —
      re-ground is ROLE-AWARE: orchestrator material for an orchestrator
      plan, workstream material for a workstream plan. *test:* orchestrator
      plan → no builder-only material; workstream plan → no orchestration
      bulk.
- [ ] `[per-compaction]` **C3** (leaf-row) — the compaction threshold in
      force matches the selected model: on a smaller-context model the
      window clamps to the model's own limit; a larger model's absolute
      threshold is never applied to a smaller one. *test:* threshold read
      back per model.

## D. The build loop

- [ ] `[per-commit]` **D1** — the TDD gate fires before every prod write: a
      watched, relevant red precedes the implementing edit. *test:*
      prove-NO (B4).
- [ ] `[per-commit]` **D2** — only **deterministic** checks block the
      commit. Fallible LLM judgment may *wake* the agent but never blocks:
      a FAIL verdict is advisory; the clean-gate (a deterministic fact
      about review closure) is what blocks. *test:* a FAIL alone does not
      block; an open/unclosed review does.
- [ ] `[per-commit]` **D3** — FAIL lifecycle against the live gate: an open
      FAIL blocks the next commit until respond + close; a fix commit that
      merely *cites* the review does not close it. *test:* both paths.
- [ ] `[per-commit]` **D3b** — review-status semantics against the live
      gate: a **crash** (failed status, or no row at all — caught only by a
      per-sha lookup, never the list alone) blocks until a completed review
      exists; a duplicate crash is ignored only once a done review covers
      that sha; a null from the daemon means *zero open*, not malformed; a
      clean PASS auto-closes (never hand-close the last open PASS). *test:*
      each path against the live gate script.
- [ ] `[per-commit]` **D4** — commits are small; the plan checkbox moves in
      the SAME commit as the work. *Discipline now; mechanically enforced
      once E1 ships.*
- [ ] `[per-commit]` **D5** — every known TDD-guard false-block has a
      named, working, sanctioned recovery (the gotchas in `build-loop.md`),
      and the bypass paths are refused. *test:* drive any current gotcha,
      confirm its recovery works and the bypass is refused.
- [ ] `[per-phase]` **D6** — for any human/LLM-facing artifact, a golden
      sample is rendered from real domain objects and reviewed **with the
      human**. *test:* a format-bearing change shows a rendered sample
      reviewed before merge.
- [ ] `[per-phase]` **D7** — a phase checkpoint is an INDEPENDENT read-only
      subagent (never self-review), scoped `<last-reviewed>..HEAD`, dedup'd
      by stamping; its prompt carries the full contradiction taxonomy, a
      default-to-silent calibration, and the FINDING-vs-INTERPRETATION
      self-classification with both-sides-quoted evidence required to bind
      (`reviews.md`). *test:* a self-review is rejected; the range is the
      delta only; a blocked-first-command subagent does not silently
      abandon the review; an unquoted binding assertion or a taxonomy-less
      prompt is rejected.

## E. Plan integrity

- [ ] `[per-commit]` **E1** (TO BUILD in either leaf that lacks it) — a
      plan-coherence pre-commit
      check keeps the plan honest about git: (a) a gated-tree commit also
      touches `task_plan.md`; (b) any `end_sha`/`reviewed` stamp is an
      ancestor of HEAD; (c) the plan's `**Branch:**` line == current
      branch. *test (once built):* each violation caught.
- [ ] `[per-merge]` **E2** — findings are durable: every resolved fork
      (panel or human) is written to the owning strand's `findings.md`
      (question, recommendation, resolution, date). *test:* each resolved
      open item has a findings entry.

## F. Orchestrator & the fleet

- [ ] `[epic-start]` **F1** — the orchestrator is its own strand on the
      integration branch (never main); its commits touch no gated
      production code (its lack of a TDD guard is safe *only* because of
      that). *test:* Run type orchestrator; branch ≠ main; commits clean of
      the gated tree.
- [ ] `[epic-start]` **F2** — the fleet plan holds the dependency graph:
      per stream — slug, branch, worktree, depends-on, files-owned,
      status, findings state. *test:* the table exists with those columns;
      every active stream has a row.
- [ ] `[continuous]` **F3** — dispatch is a topological sweep with dynamic
      concurrency, cap 2–3. *test:* a fixture graph (1 → 3 → 1) produces
      the 1→3→1 in-flight shape with no hand-scheduling.
- [ ] `[per-dispatch]` **F4** — `dispatchable` OWNS the arm step:
      `deps_all_merged AND provision==PASS AND probe==PASS`, evaluated at
      *that stream's* unlock, so a stream unlocked late runs the identical
      arm sequence as the first. Dispatching an unlocked stream WITHOUT
      provision is a hard failure, not a silent pass. *test:* a
      late-unlocked fixture stream has provision/probe logs timestamped
      after its deps' merges, before its builder boots.
  - [ ] `[per-dispatch]` **F4a** (leaf-row) — the builder launches as the
        leaf's on-plan, real-session-root, detached mode — never an
        off-plan API/headless mode, never an undetached child, never an
        ephemeral mode. *test:* a wrong-mode launch is flagged.
  - [ ] `[per-dispatch]` **F4b** (leaf-row) — process safety: the prompt
        layer is removed the sanctioned way (never a half-mode that hangs
        on compound shell; never a mode that skips hooks); the session is
        supervisor-parented and confirmed registered, rooted in the
        worktree; dispatched only into an already-trusted path. *test:*
        each wrong variant is flagged.
  - [ ] `[per-dispatch]` **F4c** (leaf-row) — model and effort are passed
        explicitly and surfaced before a token is spent (never inherited,
        no aliases); a found-on-wrong-model builder triggers the recovery
        ritual (stop, reset worktree, close reviews, relaunch, audit).
        *test:* a launch echoes its model first; a wrong-model builder
        triggers recovery.
  - [ ] `[per-dispatch]` **F4d** — the dispatch prompt carries every
        clause of `modes/fleet.md`'s dispatch-prompt contract. *test:* a
        prompt missing any clause is flagged.
- [ ] `[continuous]` **F5** — the orchestrator holds no context-only state:
      killed + relaunched, it reconstructs the in-flight set from durable
      records alone (plan, git, the liveness source, review daemon).
      *test:* exactly that.
- [ ] `[per-dispatch]` **F6** — plan-review weight is tied to plan RISK.
      Never dispatch onto a plan with a *decidable* defect; spend panels
      only on real design forks.
  - [ ] **F6a (mechanical gate — always, BLOCKS)** — decidable misses block
        launch: branch line; test-drivable steps; honest dep order vs merge
        state; files-owned disjoint; verification commands; checkpoint
        table seeded; contract edits isolated as ratify steps; scope
        locked; exempt zones declared with substitute proofs; for any
        fog-bound view, perceivable fields enumerated with the binding rule
        cited. *test:* each miss blocks.
  - [ ] **F6b (cross-stream fit — BLOCKS)** — thin check only: files-owned
        vs live streams, depends-on vs real merge state, shared-contract
        overlap. *test:* a colliding plan is blocked.
  - [ ] **F6c (fleet graph-check — once before ANY launch, BLOCKS)** — a
        deterministic check sorts the DAG (cycles), intersects ownership
        (disjoint), validates merge order, fail-closed; then a subagent
        confirms every taken decision has a findings home. *test:* a
        cyclic graph or overlapping ownership is blocked deterministically.
  - [ ] **F6d (tier · advisory panel · bounded park)** — plans are labeled
        trivial or design-weighty; design-weighty ones also get a
        multi-model panel whose findings are advisory (they inform a
        re-plan, never block — unless a finding is a verifiable fact,
        which is an F6a miss); the loop iterates only on the blocking set,
        cap 2 rounds; still non-empty → PARK the stream and keep
        dispatching the rest. *test:* a trivial plan runs no panel; a
        taste-finding does not block; an unresolvable plan parks while the
        fleet keeps moving.
- [ ] `[per-merge]` **F7** — findings collection is enforced at the merge
      gate: a stream cannot merge until its `findings.md` is committed.
      *test:* an unlogged resolved fork blocks the merge.
- [ ] `[per-monitor]` **F8** — decision routing: ruled/trivial → decide and
      move; engineering fork → panel (prompt excludes the newest handoff;
      informs, never replaces ratification); vision/scope/contract call →
      the human. *test:* each class routes right; a vision call is never
      auto-decided by a panel.

## G. Monitoring & liveness

- [ ] `[continuous]` **G1** (leaf-row) — liveness is asserted from GROUND
      TRUTH by an independent watcher using valid signals (a durable
      liveness source outside the builder's own process group — a session
      registry is the typical shape — plus worktree-matched cwd,
      last-commit age, session-log movement, open reviews — matched to
      THIS worktree, never a global process match) and never an invalid one (plan-usage %, a
      stale heartbeat). Reported state is weighed WITH commit-age, never
      alone; a wait keys on latching ground truth (a new commit sha), never
      a fixed countdown nor another session's reported state; an
      orchestrator leaves no lingering watch shell. *test:* the status
      command exits non-zero on hard-dead, finds the right session by
      worktree, is not fooled by another same-harness process on the
      machine.
- [ ] `[continuous]` **G2** — the human pulse has teeth: builder questions
      surface within one monitoring cycle; a heartbeat lands at least every
      ~15 min during active builds; ~50 quiet minutes is a failure. *test:*
      a seeded open item is detected within one cycle; cadence stays under
      threshold.
- [ ] `[continuous]` **G3** — the watcher fires on latching events (a
      done-marker hash change, a blocker-file hash change, an aged FAIL,
      process death, inactivity past the stall threshold) and stale
      pre-existing markers do not false-fire. *test:* each event fires
      once; a stale marker at arm time does not.
- [ ] `[continuous]` **G4** (leaf-row) — dispatch and watch never
      separate: launch leaves a durable not-yet-watched marker that only
      arming the watcher clears, and
      a watchdog detects a dead watcher (the dead-man layer is distinct
      from the stall layer and the slow outer heartbeat). *test:* an
      unarmed launch reports UNWATCHED; a killed watcher trips the
      watchdog.

## H. Recovery

- [ ] `[per-compaction]` **H1** — recovery is relaunch-from-git with a
      one-line resume note; the relaunched session continues from the next
      unchecked box (no redo, no skip), does not re-run the boot ritual or
      re-wire the harness, does not switch to the newest handoff, and
      resumes the leaf's recorded session/thread identity where one exists.
      *test:* kill a builder mid-phase → relaunch → continues correctly.
- [ ] `[per-compaction]` **H2** — bounded: repeated same-phase death
      escalates as a **crash storm** to the human rather than relaunch
      looping (a same-place storm is often one expired auth token only the
      human can fix). *test:* same-phase death N times → escalates.

## I. Merge & closeout

- [ ] `[per-merge]` **I0** — the depth scan ran at BOTH mandated points
      (modes/fleet.md): at plan formation when the plan touches existing
      modules (findings recorded in the plan or `findings.md`, shaping the
      stream framing), and over each module-touching phase's merged diff
      (findings in the acceptance package, marked ADVISORY). The human MAY
      additionally run an interactive architecture-review tool on the
      integration tree before ratifying — human-invoked only, never
      required, never blocking. *test:* a module-touching plan with no
      formation-scan record, or a module-touching phase with no boundary-
      scan record, fails this row; docs-only plans and phases pass without
      either. (This row is audited by the acceptance walk itself; an
      executable record-verifier belongs to a leaf once a leaf defines an
      acceptance-package format — the scan's findings are judgment and may
      never gate.)
- [ ] `[per-merge]` **I1** — stream merge gate: complete; deterministic
      checks green; all checkpoints stamped (`reviewed == end_sha`); zero
      open/queued/running reviews; `findings.md` committed; the merge done
      on the verified right branch. *test:* any failing clause blocks; a
      wrong-branch merge is caught.
- [ ] `[per-merge]` **I2** — the live post-merge smoke: the product's REAL
      entry path runs against the merged tree with a real observable
      proving life; fixture-only green cannot satisfy it; a failed smoke
      bounces the merge like a failed review. *test:* a merged tree whose
      unit suites pass but whose live entry path fails is blocked.
- [ ] `[closeout]` **I3** — closeout: a whole-work closeout review (not
      replaced by checkpoints); every plan + findings archived; the
      archive-rename commit's diffstat verified non-empty (the rename +
      pre-commit stash trap silently drops unstaged edits); closeout
      refuses a live owner, unmerged content, or uninspected dirty files —
      real-looking uncommitted work goes to the human, never force-reaped.
      For an epic, integration merges to main once, with human sign-off.
      *test:* the archive commit preserves content; each refusal fires; a
      partial epic merge to main is blocked.
- [ ] `[closeout]` **I4** — cleanup is complete and the janitor is
      read-only: post-closeout no stray worktrees/branches/watch files
      remain; the janitor only reports (reapable, active, orphan, stale) —
      a human approves each reap. *test:* post-closeout audit clean; the
      janitor makes no mutation.

## J. Model dial

- [ ] `[epic-start]` **J1** — every model ID lives in ONE dial per leaf,
      nowhere else; models are passed explicitly (no aliases, never
      inherited) and surfaced before a token is spent; a wrong-model boot
      has a recovery ritual. *test:* grep model IDs outside the dial →
      none; a launch echoes its model first.

## K. Script law

- [ ] `[continuous]` **K1** — every harness script (and any watcher) obeys
      one law: gather facts, run the fixed sequence, **decide nothing** —
      fail closed, never auto-merge/auto-push/auto-relaunch/auto-kill,
      never print a health verdict. *test:* no such code path exists; no
      subcommand emits a pass/health verdict.
- [ ] `[closeout]` **K2** — destructive teardown resolves explicit targets
      and proves ownership/merged/dirty state before deleting anything.
      *test:* a teardown against an ambiguous or unproven target refuses.
- [ ] `[continuous]` **K3** — arming never clobbers foreign hooks/configs:
      create-if-absent, merge-if-present. *test:* a pre-existing richer
      hook survives an arm run byte-identical or safely merged.
- [ ] `[continuous]` **K4** (leaf-row) — temporary files are trapped and
      cleaned; run bookkeeping lives under the leaf's scoped runs
      directory, never scattered. *test:* a killed script leaves no
      stray temp files; bookkeeping paths are scoped.
