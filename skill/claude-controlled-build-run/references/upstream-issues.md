# Upstream issues — observed in production, to report to the tools' maintainers

Living record of tool defects the CBR discipline currently works around. Each
entry: the observed behavior, the working workaround, and what the upstream fix
should be. Delete an entry when the upstream fix lands and is verified here.

## RoboRev

### 1. Merge-commit auto-reviews crash or never run (double-pay on re-queue)

Observed on ALL FOUR integration merges of the 2026-07-02→03 overnight fleet
build (c26981a, 80da771, 80ea0f1, fe634a8): the post-commit auto-queued review
of a `--no-ff` merge commit either crashes or never runs at all. The
then-active roborev-clean pre-commit gate caught the missing review at the
NEXT commit and re-queued it — the re-review passed clean every time. (That
commit gate retired 2026-08-31; the merge-path review gate is now the backstop
that notices a merge range without a completed review.)

- **Workaround:** the merge-path review gate requires a completed branch
  review, so a crashed merge-commit review surfaces there. Budget the re-run.
- **Upstream ask:** make merge-commit reviews first-class (review the merge's
  combined diff or auto-pass an empty one), or at minimum don't enqueue a job
  shape the reviewer is known to crash on.

### 2. `roborev wait -q <sha>` exits 0 when NO review exists for the sha

Observed same night, every merge: after the auto-review crashed, `roborev wait
-q <sha>` printed "No jobs found" and exited 0 — which scripts read as
"review complete and clean". Combined with issue 1 this makes an unreviewed
merge look reviewed to any caller that trusts the exit code.

- **Workaround:** never trust `wait -q` alone; derive "does a completed
  review EXIST" from `roborev list`/`roborev show` directly (the merge-path
  review gate does exactly this for the branch review).
- **Upstream ask:** `wait -q` should exit non-zero (distinct code) when no job
  exists for the sha, so "nothing to wait for" is distinguishable from "waited
  and it's done".

### 3. Verdict sentinel mis-grade: clean reviews graded "F"

A review whose body is a clean pass but whose output is missing the verdict
sentinel can be recorded with verdict `F` (observed 2026-06-24 era, again
2026-07-03 as a "bodyless F" on the recorder stream, job 1801). Any automation
keyed on the verdict letter alone will false-alarm.

- **Workaround:** READ THE BODY before treating an F as a real FAIL —
  captain-watch.sh's EVENT=REVIEW-FAIL message carries this warning, and the
  fail-grace window keeps most transients from paging at all.
- **Upstream ask:** grade from the body when the sentinel is absent, or mark
  sentinel-missing reviews as a distinct status instead of F.

### 5. No delta review: every branch-review rerun re-reads the whole branch

Each fix commit moves the branch tip, invalidating the completed branch
review the merge gate requires, so the boundary loop reruns
`roborev review --branch` from scratch — ~300k input tokens per run late in
a branch, and one PR took ~13 runs to converge (2026-08-31, PR-4 of the
control-plane diet contract).

- **Workaround:** the batch-fixes law in cbr-core build-loop.md — collect
  ALL findings, land fixes as one batch, rerun once; already-ruled classes
  get dispositions, not commits.
- **Upstream ask:** a delta mode — review only commits since the last
  completed branch review on the same branch, carrying prior findings
  forward as context instead of re-deriving them.

### 6. The reviewer has no memory of dispositions

A finding declined with recorded reasoning (respond + close) is re-raised
verbatim by the next review — one decision was re-litigated three times in
one boundary loop (jobs 5545/5568/5569), each round costing a full response
cycle.

- **Workaround:** decline messages cite the prior job numbers so the human
  audit trail stays coherent; the round cap bounds the waste.
- **Upstream ask:** feed the branch's closed-job respond texts into the
  review context (or accept a dispositions file), so a settled ruling is
  visible to the reviewer instead of rediscovered as a fresh finding.

## Probity

### 4. The TDD gate is a nondeterministic LLM judge, not a mechanism

A self-narrating probe write flipped the judge to ALLOW on 2 of 3 replays of
byte-identical input (2026-07-03 P0 incident, repro preserved in the control plane
stream records), while real-code contexts denied consistently. Missing/empty
transcript fails closed.

- **Workaround:** the amended P0 probe rule — one unblocked probe write with a
  blocked retry = PASS-with-note; TWO consecutive unblocked writes =
  CONTROL-PLANE-BROKEN, stop. One flake is tolerated; two consecutive is broken.
- **Upstream ask (@nizos/probity):** report the narration-flip repro; consider
  a deterministic pre-filter (e.g. path/config-based) before the LLM judgment
  layer.
