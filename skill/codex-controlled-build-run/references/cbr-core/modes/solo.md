# modes/solo.md — one strand, human seam direct

Part of `cbr-core`, the provider-neutral CBR law.

A **solo build** is the default mode: one strand (see `strand.md`), one
session, building one plan. Everything in `policy.md`, `strand.md`,
`build-loop.md`, `reviews.md`, and `judgment.md` applies as written; the
fleet and captain tiers do not exist here.

What changes without the upper tiers:

- **The human seam is direct.** There is no orchestrator to triage asks: the
  builder talks to the human for vision/scope calls (judgment bucket 3) and
  runs the multi-model panel itself for engineering forks (bucket 2) — in an
  attended session the interactive path is fine. A **headless** solo builder
  still never blocks on an interactive prompt, but `judgment.md`'s file
  channel has no orchestrator here to poll and answer it — the ask file's
  reader is the human directly, on their own schedule. So headless-solo asks
  default to `PROCEEDING-ON-DEFAULT` (state the default, keep building
  everything else); a genuinely `BLOCKING` ask with no responder becomes the
  needs-human terminal marker plus a parked plan item, never a wait. Do not
  dispatch an unattended solo run at all when the plan still contains forks
  that will need a mid-run answer — resolve them at plan time
  (`strand.md`: a builder must never start on an unresolved fork).
- **Branch base: current main.** Cut the strand's branch from the latest
  main so it contains every tracked gate, and refresh from main before
  relaunching a long-lived branch (`modes/fleet.md`'s gate-inheritance law,
  solo case — stated here so a solo reader never needs the fleet file).
- **Merge is yours, push may not be.** At closeout, merge the strand's
  branch into main per `build-loop.md` step 9. Whether pushing main is gated
  on the human is a per-repo rule — check the repo's own law before
  pushing, and stop at the gate if one exists.
- **Reviews still run at full strength.** Per-commit review, the
  review-clean gate, phase checkpoints, and the closeout review are not
  fleet features — they gate a solo strand identically. The plan-review
  gate (`reviews.md`) applies to a solo plan too when the work is
  non-trivial: review the plan before you spend the build on it.
- **Escalation shrinks, discipline doesn't.** With no orchestrator watching
  from outside, the hooks and gates are the only supervision — which is
  exactly the case the harness was built for. A solo builder that starts
  waiving gates because "no one is watching" has left the process.

A single small fleet (one orchestrator, a couple of streams) sits between
this and `modes/fleet.md`: the orchestrator exists but talks to the human
directly, skipping the captain tier.
