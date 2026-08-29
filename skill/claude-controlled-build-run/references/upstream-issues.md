# Upstream issues — observed in production, to report to the tools' maintainers

Living record of tool defects the CBR discipline currently works around. Each
entry: the observed behavior, the working workaround, and what the upstream fix
should be. Delete an entry when the upstream fix lands and is verified here.

## RoboRev

### 1. Merge-commit auto-reviews crash or never run (double-pay on re-queue)

Observed on ALL FOUR integration merges of the 2026-07-02→03 overnight fleet
build (c26981a, 80da771, 80ea0f1, fe634a8): the post-commit auto-queued review
of a `--no-ff` merge commit either crashes or never runs at all. The
roborev-clean pre-commit gate then catches the missing review at the NEXT
commit and re-queues it — the re-review passed clean every time, so each merge
commit pays for up to two review attempts and always pays a gate-blocked delay.

- **Workaround:** none needed beyond the gate — it is the designed backstop and
  it caught every occurrence. Budget the extra wait at each merge gate.
- **Upstream ask:** make merge-commit reviews first-class (review the merge's
  combined diff or auto-pass an empty one), or at minimum don't enqueue a job
  shape the reviewer is known to crash on.

### 2. `roborev wait -q <sha>` exits 0 when NO review exists for the sha

Observed same night, every merge: after the auto-review crashed, `roborev wait
-q <sha>` printed "No jobs found" and exited 0 — which scripts read as
"review complete and clean". Combined with issue 1 this makes an unreviewed
merge look reviewed to any caller that trusts the exit code.

- **Workaround:** never trust `wait -q` alone; the roborev-clean gate
  re-derives "does a completed review EXIST for HEAD" and blocks when none
  does.
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

## Probity

### 4. The TDD gate is a nondeterministic LLM judge, not a mechanism

A self-narrating probe write flipped the judge to ALLOW on 2 of 3 replays of
byte-identical input (2026-07-03 P0 incident, repro preserved in the scaffold
stream records), while real-code contexts denied consistently. Missing/empty
transcript fails closed.

- **Workaround:** the amended P0 probe rule — one unblocked probe write with a
  blocked retry = PASS-with-note; TWO consecutive unblocked writes =
  HARNESS-BROKEN, stop. One flake is tolerated; two consecutive is broken.
- **Upstream ask (@nizos/probity):** report the narration-flip repro; consider
  a deterministic pre-filter (e.g. path/config-based) before the LLM judgment
  layer.
