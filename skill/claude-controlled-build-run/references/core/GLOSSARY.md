# GLOSSARY.md — the control plane's own words

Part of `cbr-core`, the provider-neutral CBR law. These terms mean the same
thing in every project that runs the control plane. Use them exactly — don't
substitute near-synonyms ("branch job" for strand, "checker" for gate). A
host project's DOMAIN vocabulary does not belong here: that lives in the
project's own glossary (e.g. a root `CONTEXT.md`), written only when a
domain-modeling pass earns real entries.

- **control plane** — the enforcement assembly wired into a repo: write-time TDD
  guard, pre-commit facts gate, commit review, re-ground hook. It does the
  remembering so the session doesn't have to.
- **agent harness** (short: **harness**) — the agent runtime the control plane
  rides in, such as Claude Code or Codex. Never use it for the control plane
  itself; the control plane's pitch is portability across agent harnesses.
- **core / leaf** — `cbr-core` is the provider-neutral law. A **leaf** is
  one agent harness's control-plane adapter, supplying the mechanisms (tool names,
  paths, flags) that enforce the law. Law lives in core; mechanisms live in
  leaves; a mechanism appearing in core is a leak, not a promotion.
- **kit** — the generated, portable export of the control plane: drop it into
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
- **builder / orchestrator** — the two roles. Builders write code in
  their strands; an orchestrator dispatches and monitors builders and owns
  the human seam. There is no third tier.
- **solo / fleet** — the two modes: one session building in one strand,
  versus an orchestrator running parallel builders in streams.
- **arm / armed** — the control plane is verified wired in THIS worktree.
  Reading docs arms nothing; only the doctor's checks prove it.
- **doctor** — the leaf command that checks the control plane end to end,
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
- **PR-boundary review loop** — the review cadence (ratified 2026-08-31):
  per-commit reviews enqueue but are advisory; at the PR boundary the
  builder runs a branch review, handles its findings, and respond+closes
  every open job. Nothing holds an ordinary commit.
- **merge review gate** — the wall the PR-boundary loop reports to:
  a hook (pre-merge-commit on auto-merges, pre-commit when a merge is
  completed by hand) that refuses a merge while the
  merged branch has open blocking findings, lacks a completed branch
  review at its tip, or exceeds the round cap without a recorded ruling
  (`cbr-core/scripts/merge-review-gate.sh`).
- **round cap** — 3 fix rounds TOTAL (2026-08-31); then a judgment exit or
  an escalation ruling recorded as
  `git config branch.<branch>.cbrEscalation`. The merge gate counts every
  review-fix commit in the merge range — mechanically it cannot tell chains
  apart, so distinguishing a fourth round on one finding from four
  independent one-round fixes is exactly the judgment the escalation
  ruling records.
- **closeout** — the end-of-strand duties on the base branch: archive the
  strand's records, clear its markers, leave the tree safe for the next
  strand.
- **watchdog** — retired 2026-08-31 (control-plane diet): the separate dead-man
  over the watcher is gone; the watcher's own stall alarm — and the silence
  tripwire that supersedes it — carry the "silence is an alarm" law.
