# GLOSSARY.md — the harness's own words

Part of `cbr-core`, the provider-neutral CBR law. These terms mean the same
thing in every project that runs the harness. Use them exactly — don't
substitute near-synonyms ("branch job" for strand, "checker" for gate). A
host project's DOMAIN vocabulary does not belong here: that lives in the
project's own glossary (e.g. a root `CONTEXT.md`), written only when a
domain-modeling pass earns real entries.

- **operator** — the human who owns the run: ratifies scope and vision
  forks, answers `NEEDS-OPERATOR` parks, approves reaps of ambiguous work,
  and holds the push/deploy/merge-to-main gate. Judgment escalates to the
  operator; it never defaults past them. One person wears this hat per run.
- **harness** — the enforcement assembly wired into a repo: write-time TDD
  guard, pre-commit facts gate, per-commit review, re-ground hook. It does
  the remembering so the session doesn't have to.
- **core / leaf** — `cbr-core` is the provider-neutral law. A **leaf** is
  one provider's harness adapter, supplying the mechanisms (tool names,
  paths, flags) that enforce the law. Law lives in core; mechanisms live in
  leaves; a mechanism appearing in core is a leak, not a promotion.
- **kit** — the generated, portable export of the harness: drop it into
  another repo to arm CBR there. A build artifact — never hand-edited,
  always regenerated from the live source.
- **strand** — the unit of isolation: one branch ↔ one plan ↔ one folder ↔
  one session. Every build, solo or orchestrated, runs in exactly one.
- **stream** — a fleet builder's strand on a `stream/*` branch. Streams
  merge into the integration branch, never the default branch.
- **integration branch** — the branch a fleet's streams merge into. The
  single integration→default merge at epic close needs the human's
  explicit sign-off.
- **plan trio** — `task_plan.md` (decisions and phases), `findings.md`
  (durable discoveries), `progress.md` (running record, incl. readback).
- **Run type** — the plan-header line declaring the session's role. Role
  selection keys off its exact token; a fuzzy match grounds the wrong law.
- **builder / orchestrator / captain** — the tiers. Builders write code in
  their strands; an orchestrator dispatches and monitors builders; a
  captain dispatches orchestrators. Each tier narrows toward the human.
- **solo / fleet** — the two modes: one session building in one strand,
  versus an orchestrator running parallel builders in streams.
- **arm / armed** — the harness is verified wired in THIS worktree.
  Reading docs arms nothing; only the doctor's checks prove it.
- **doctor** — the leaf command that checks the harness end to end,
  reporting per check. Run it in the tree you actually build from,
  immediately before the next irreversible step.
- **gate** — a deterministic, blocking check. Facts may gate; fallible
  judgment may only surface. Anything not mechanically decidable must
  advise, never block.
- **re-ground** — the post-compaction reinjection of law, grounding docs,
  and the active plan — whole and verbatim, because a summary fuzzes the
  exact rules.
- **readback** — a dispatched builder's first act: restate the plan's
  intent, constraints, and current phase in its own words in
  `progress.md`, checked by the dispatcher before building starts.
- **prove-NO** — verifying an enforcement change by showing the forbidden
  thing actually fails or blocks — not just that the allowed path passes.
- **judgment exit** — after the fix-round limit, a review finding may be
  declined with recorded reasoning and surfaced to the human instead of
  fixed forever. It keeps advisory review from becoming an infinite gate.
- **closeout** — the end-of-strand duties on the base branch: archive the
  strand's records, clear its markers, leave the tree safe for the next
  strand.
- **watchdog** — the timer that pages the dispatcher when a builder goes
  quiet; it retires when the build's own cycle-bound DONE marker appears.
