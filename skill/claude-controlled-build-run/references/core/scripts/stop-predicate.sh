#!/usr/bin/env bash
# May this builder's session end here?
#
# The whole point of a stop gate is that "the session stopped" is the ONLY
# thing a watcher outside the worktree can see. It cannot tell finished from
# abandoned, so the control plane makes the builder leave a committed fact behind
# before it is allowed to go quiet. Three facts qualify, and nothing else:
# the completion latch, the operator park file, and the control-plane-broken marker.
#
# One implementation, in the neutral core, because the leaves differ only in
# how their hook payload arrives and what they told the operator to name the
# park file. A rule copied into two hooks is a rule that gets fixed in one.
#
#   stop-predicate.sh --worktree <dir> --park-file <name>
#     exit 0  — allowed to stop (reason on stdout when there is one to give)
#     exit 1  — must keep working; the message on stdout is for the builder
#     exit 2  — the predicate was called wrong
set -uo pipefail

wt= park=
while [ $# -gt 0 ]; do
  case "$1" in
    --worktree)  wt="${2:-}";   shift 2 ;;
    --park-file) park="${2:-}"; shift 2 ;;
    *) echo "stop-predicate: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$wt" ] && [ -n "$park" ] || {
  echo "stop-predicate: --worktree <dir> and --park-file <name> are both required" >&2
  exit 2
}
[ -d "$wt" ] || { echo "stop-predicate: not a directory: $wt" >&2; exit 2; }

# The committed-marker question is the same one every watcher asks, so it is
# answered in the same place. A second copy here would drift from the one the
# watchers use, and the two would disagree about whether a strand finished.
_pred_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=/dev/null
[ -f "$_pred_dir/strand-lib.sh" ] && . "$_pred_dir/strand-lib.sh"

# Scope. This binds stream builders only. An orchestrator or a
# human at a terminal has no plan-shaped obligation to a watcher and must
# never be trapped in its own session by this.
branch="$(git -C "$wt" branch --show-current 2>/dev/null || true)"
case "$branch" in stream/*) ;; *) exit 0 ;; esac

# The two releases that mean "a human now owns this": the operator park file
# the leaf pins, and a control plane too broken to reach the next phase. Both are
# terminal on purpose — a builder that cannot proceed must be able to stop,
# or the gate turns every blocker into a spin.
#
# Neither requires a commit, and that asymmetry is deliberate. They are read
# off the filesystem by the same watcher that polls the ask channel, and a
# control plane broken badly enough to fail its own commit gates is exactly the case
# where demanding a commit would trap the session with no way out. The latch
# below is the one that must be committed, because it is the only one that
# claims success.
[ -e "$wt/$park" ] && exit 0
[ -e "$wt/CONTROL-PLANE-BROKEN.marker" ] && exit 0

# A stream builder with no plan is not a builder with nothing to prove — it is
# a worktree whose plan was moved, renamed, or deleted, and allowing the stop
# there makes "rm task_plan.md" the bypass for the entire gate.
if [ ! -f "$wt/task_plan.md" ]; then
  cat <<MSG
Stop refused: $branch has no task_plan.md.

A stream builder's plan is the one record that says whether its work is
finished, so a missing plan is not permission to stop — it is a strand nobody
can assess. Restore it from git, or hand the strand over explicitly by writing
$park or CONTROL-PLANE-BROKEN.marker.
MSG
  exit 1
fi

# Phase lines in real plans carry markdown emphasis — `- [ ] **P3 — ...**` —
# and their identifiers are not all P-then-digit: `P5b` and `P-E` are both in
# use. A pattern that misses either shape reads a plan with open phases as
# fully checked, which is the gate silently retiring itself rather than
# failing. `P` must be followed by a digit or a dash so that ordinary words
# starting with P are not mistaken for phase ids.
# The completion latch is named FOR the branch (strand-lib
# cbr_done_marker_name): an inherited marker has a different name and cannot
# pass for this strand's completion.
if command -v cbr_done_marker_name >/dev/null 2>&1; then
  done_marker="$(cbr_done_marker_name "$branch")"
else
  done_marker="DONE.marker"
fi

open_phases="$(grep -cE '^[[:space:]]*- \[ \][[:space:]]*[*_]*[[:space:]]*(P[-0-9]|Phase[[:space:]]*[0-9]|Stage[[:space:]]*[0-9])' \
  "$wt/task_plan.md" 2>/dev/null || true)"
open_phases="${open_phases:-0}"

if [ "$open_phases" -gt 0 ]; then
  # Deliberately checked BEFORE the latch: a marker left over from an earlier
  # state is not a password for work that is demonstrably still open.
  cat <<MSG
Stop refused: the plan for $branch still has $open_phases phase(s) left open.

Continue from task_plan.md. This session is watched from outside the worktree,
where a stopped session and a dead one look identical — so the control plane needs a
committed fact before it lets you go quiet:

  - finish the phases and COMMIT $done_marker, or
  - write $park, if this needs a human, or
  - write CONTROL-PLANE-BROKEN.marker if the control plane itself cannot carry you further.

The latch must be committed because it is read from the repository after this
worktree is gone. The other two are read off the filesystem, so writing them is
enough — commit them too if the reason is worth keeping.

If the blocker is a question, do not stop to ask: record it with a proposed
default in ASK-ORCH.md and keep moving on work that does not depend on it.
MSG
  exit 1
fi

# COMMITTED, not merely present. This one is a claim that the work is finished,
# and it is read by whoever decides whether the strand can be reaped — from the
# repository, after the worktree is gone. A latch that exists only in the
# working tree makes that claim to nobody.
if command -v cbr_marker_is_committed >/dev/null 2>&1; then
  [ -e "$wt/$done_marker" ] && cbr_marker_is_committed "$wt/$done_marker" && exit 0
else
  # No second spelling of the question. The fallback that stood here answered a
  # NARROWER one — is a file of this name committed at the repo root — which is
  # both of the defects this predicate has already been repaired for: a path
  # present in HEAD while the claim in front of it is not, and a basename that
  # names a different file than the marker. A library that did not load leaves
  # the question unanswered, and unanswered is not a release: this gate fails
  # CLOSED on what it could not check, and says which check it could not run.
  cat <<MSG
Stop refused: the shared strand library did not load, so this gate cannot tell a
committed completion latch from an uncommitted one.

The predicate sources scripts/strand-lib.sh from its own directory; missing or
unreadable, that is a control-plane fault, not a completion. Repair it, or write
CONTROL-PLANE-BROKEN.marker to hand the strand over deliberately.
MSG
  exit 1
fi

if [ -e "$wt/$done_marker" ]; then
  cat <<MSG
Stop refused: $done_marker is in your working tree but not committed on $branch.

The latch is read from the repository, after this worktree is gone — uncommitted
it claims completion to nobody, and the strand still looks like one whose builder
died mid-phase. Commit it (the gates run on that commit, which is the point) and
stop again.
MSG
  exit 1
fi

cat <<MSG
Stop refused: every phase on $branch is checked, but no $done_marker is committed.

The checkboxes live in your working tree; the latch is what an outside watcher
reads. Without it a finished strand is indistinguishable from one whose builder
died mid-phase, and it will be either reaped with real work in it or left
waiting on a session that is never coming back.

Run the plan's closing gate, then commit $done_marker. If something is stopping
you from finishing, write $park or CONTROL-PLANE-BROKEN.marker instead so a human is
handed the strand explicitly.
MSG
exit 1
