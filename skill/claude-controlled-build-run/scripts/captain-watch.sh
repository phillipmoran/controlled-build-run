#!/usr/bin/env bash
# captain-watch.sh — the dispatcher's fire-once event trap over a dispatched run.
# (Filename is historical: the captain tier retired 2026-08-31; the orchestrator —
# or the human in the primary — is the dispatcher now.)
#
# Companion to cbr.sh but deliberately NOT a cbr.sh subcommand: cbr.sh commands are
# one-shot fact-gatherers, this is a long-running trap. Same law otherwise — it DECIDES
# NOTHING. It blocks until the FIRST latching event, prints one EVENT= line, and exits.
# The exit IS the wake. Fire-once semantics: the dispatcher re-arms it as the FIRST act of
# every wake (fleet.md watcher law — a re-arm left for the end of a wake gets forgotten).
#
# Events (first one wins) — DECISION-ONLY wakes (ratified 2026-07-03): the watcher fires
# only when the dispatcher has a judgment to make, never for bookkeeping. Every commit is
# still checked by the machinery (Probity, the pre-commit gate, per-commit RoboRev) —
# just not by a big-context session.
#   EVENT=DONE                 the branch's own DONE-<branch>.marker appeared or CHANGED since arm time.
#                              HASH-latch like NEEDS-OPERATOR, not existence: a fix-round relaunch
#                              on an already-DONE worktree carries a stale marker, and an
#                              existence check false-fires instantly, killing the watcher and
#                              leaving the builder unwatched (2026-07-10: 4h phantom stall).
#   EVENT=NEEDS-OPERATOR-CHANGED  NEEDS-OPERATOR.md content differs from arm time. HASH-latch, not
#                              existence: the file is tracked, so it exists in every checkout
#                              and an existence check false-fires the moment the worktree
#                              checks it out.
#   EVENT=REVIEW-FAIL          an open RoboRev review on the watched branch carries verdict F
#                              and has sat unresolved past --fail-grace-secs (default 600) —
#                              the grace keeps a healthy fix-then-close cycle from paging the
#                              dispatcher mid-fix. CAUTION at the wake: an "F" can be a clean
#                              review missing the verdict sentinel (known mis-grade) — read
#                              the review BODY before treating it as a real FAIL.
#   EVENT=STALL                no activity past --stall-secs (default 900 = 15 min): newest commit on
#                              ANY branch, the orchestrator's newest transcript, and its
#                              MORNING-REPORT.md are ALL older than the dial. Silence is an
#                              alarm, so the watcher exits on the bad path too.
#
# Tip moves NO LONGER fire (was EVENT=MERGE): each new commit is appended to the per-slug
# digest .cbr-watch/<slug>.commits instead, for the dispatcher to read at its next REAL wake.
# Waking a full-context dispatcher per commit was the fleet's single biggest token waste, and
# the wake carried no decision — the machinery had already checked the commit.
#
# Usage:
#   captain-watch.sh <slug> [--stall-secs N] [--fail-grace-secs N]
#                                               # fire-once watcher — ALWAYS background it;
#                                               # a foreground loop wedges the session
# <slug> maps to the sibling worktree ../cockpit-<slug>, same as cbr.sh.

set -uo pipefail

die() { echo "captain-watch: $*" >&2; exit 2; }

slug="${1:-}"; [ -n "$slug" ] || die "usage: captain-watch.sh <slug> [--stall-secs N] [--fail-grace-secs N]"
shift
# A healthy builder commits and touches its transcript every few minutes, so 15 min of TOTAL
# silence is already a strong wedge signal — 30 min just delayed the wake that matters.
stall_secs=900 fail_grace_secs=600
while [ $# -gt 0 ]; do
  case "$1" in
    --stall-secs)      stall_secs="${2:-}"; shift 2 ;;
    --fail-grace-secs) fail_grace_secs="${2:-}"; shift 2 ;;
    *) die "unknown arg '$1'" ;;
  esac
done

# Root from the script's own location, NOT the invoker's cwd: status and doctor
# rendezvous on the heartbeat path, so a watcher launched from a different
# checkout (say, inside a cockpit-<slug> worktree) must still resolve the same file.
root="$(cd "$(dirname "$0")/../../.." && pwd -P)" || die "cannot resolve repo root from script location"

# The shared strand mechanics — marker identity among them. A watcher that
# cannot load them still watches, because a watcher that refuses to arm leaves a
# builder with nobody looking at it, which is the worse of the two failures. It
# says so out loud at arm time rather than running quietly unguarded.
CBR_STRAND_LIB="$(dirname "$0")/../references/core/scripts/strand-lib.sh"
[ -f "$CBR_STRAND_LIB" ] || CBR_STRAND_LIB="$(dirname "$0")/../../cbr-core/scripts/strand-lib.sh"
if [ -f "$CBR_STRAND_LIB" ]; then
  . "$CBR_STRAND_LIB"
else
  cbr_marker_counts_as_done() { [ -f "$1" ]; }
  cbr_done_marker_name() { echo "DONE.marker"; }
  cbr_guard_note="WARNING: shared strand library not found at $CBR_STRAND_LIB — marker-identity guard UNAVAILABLE, an inherited marker can false-latch"
fi

# Poll interval. A dial rather than a constant so the loop can be exercised by a
# test in seconds instead of minutes; the default is the operational value.
poll_secs="${CBR_WATCH_POLL_SECONDS:-60}"
wt="$(dirname "$root")/cockpit-$slug"   # sibling of the repo, same mapping as cbr.sh

# The heartbeat is the watcher proving itself via the filesystem — status and
# doctor read its freshness as "watched"; it replaced ps scraping, which
# false-fired across windows where watchers were provably alive.
hb="$root/.cbr-watch/$slug.heartbeat"

# ---- watcher mode -----------------------------------------------------------
[ -d "$wt" ] || die "worktree '$wt' does not exist — provision the orchestrator first"
wt_real="$(cd "$wt" && pwd -P)"
branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD)" || die "cannot read the worktree's branch"
# The marker name needs the branch NAME, and needs to know when there isn't
# one. `rev-parse --abbrev-ref HEAD` prints the literal string HEAD on a
# detached worktree — non-empty, so it reads as a branch called HEAD and the
# watcher would watch a marker name nothing will ever write.
# `branch --show-current` prints nothing there, which is the honest answer.
watched_branch="$(git -C "$wt" branch --show-current 2>/dev/null || true)"
# Per-branch completion marker (strand-lib cbr_done_marker_name): an inherited
# marker has a different name, so it can never false-latch this watcher.
if command -v cbr_done_marker_name >/dev/null 2>&1; then
  done_name="$(cbr_done_marker_name "$watched_branch")"
else
  done_name="DONE.marker"
fi
tip="$(git -C "$wt" rev-parse "$branch")" || die "cannot resolve the branch tip"

# Claude project transcript dir for the worktree: path with / and . mapped to -
tdir="$HOME/.claude/projects/$(printf '%s' "$wt_real" | tr '/.' '--')"

np_hash()   { git hash-object "$wt/NEEDS-OPERATOR.md" 2>/dev/null || echo none; }
# The other two terminal facts. Both RELEASE a builder from the stop gate, so a
# watcher blind to them turns a deliberate handoff into an unexplained stall:
# the builder is allowed to go quiet, nobody is told why, and the orchestrator
# finds out fifteen minutes later as a stall it has to diagnose from scratch.
hb_hash()   { git hash-object "$wt/CONTROL-PLANE-BROKEN.marker" 2>/dev/null || echo none; }
sug_hash()  { git hash-object "$wt/STOP-UNGUARDED.marker" 2>/dev/null || echo none; }
done_hash() { git hash-object "$wt/$done_name"    2>/dev/null || echo none; }

# Open-FAIL reviews on the watched branch, older than the grace window. Prints one line
# per qualifying review ("<id> <sha8> <age_s>s"); empty output = nothing to fire on.
# roborev prints literal `null` for an empty --open list (known trap) — python treats
# that as no rows. Any parse/CLI failure degrades to empty (never a false page); the
# merge-path review gate remains the hard backstop.
stale_fails() {
  command -v roborev >/dev/null && command -v python3 >/dev/null || return 0
  (cd "$wt" && roborev list --open --json --branch "$branch" 2>/dev/null) | python3 -c '
import sys, json, datetime
try:
    rows = json.load(sys.stdin) or []
except Exception:
    rows = []
grace = int(sys.argv[1])
now = datetime.datetime.now(datetime.timezone.utc)
for r in rows:
    if r.get("verdict") != "F":
        continue
    done_at = r.get("finished_at") or r.get("enqueued_at") or ""
    try:
        # roborev mixes Z-suffixed and offset timestamps; pre-3.11 fromisoformat rejects Z
        age = (now - datetime.datetime.fromisoformat(done_at.replace("Z", "+00:00"))).total_seconds()
    except Exception:
        age = grace + 1  # unparseable timestamp on a real open F: err toward firing
    if age > grace:
        print(f"{r.get('id','?')} {str(r.get('git_ref',''))[:8]} {int(age)}s")
' "$fail_grace_secs" 2>/dev/null
}

np_base="$(np_hash)"
hb_base="$(hb_hash)"
sug_base="$(sug_hash)"
done_base="$(done_hash)"
done_noted=
digest="$root/.cbr-watch/$slug.commits"
mkdir -p "$(dirname "$hb")" && touch "$hb"
echo "armed: slug=$slug branch=$branch watched-branch=${watched_branch:-none-detached} tip=${tip:0:8} needs-operator=${np_base:0:8} done-marker=${done_base:0:8} stall-secs=$stall_secs fail-grace-secs=$fail_grace_secs digest=$digest"
[ -n "${cbr_guard_note:-}" ] && echo "$cbr_guard_note"
[ "$done_base" != none ] && echo "note: stale $done_name present at arm — DONE fires only when its content CHANGES (fix-round semantics)"

while true; do
  touch "$hb"
  done_now="$(done_hash)"
  # The watched file is the branch's OWN marker name, so a changed hash is a
  # claim by THIS strand. Committed is still required: an uncommitted latch is
  # the middle of the ordinary write-then-commit sequence, and the commit that
  # finishes it does not change the file — so the baseline stays and the note
  # is deduped on the hash instead.
  if [ "$done_now" != "$done_base" ] && [ "$done_now" != none ]; then
    if cbr_marker_counts_as_done "$wt/$done_name" "$watched_branch"; then
      echo "EVENT=DONE $(tail -1 "$wt/$done_name")"
      exit 0
    fi
    if [ "$done_now" != "$done_noted" ]; then
      echo "note: $done_name changed but is not a committed latch on $watched_branch — a latch that dies with the worktree is not a completion; not latching; watching on"
      done_noted="$done_now"
    fi
  fi

  hb_now="$(hb_hash)"
  [ "$hb_now" != "$hb_base" ] && { echo "EVENT=CONTROL_PLANE_BROKEN $wt/CONTROL-PLANE-BROKEN.marker"; exit 0; }
  sug_now="$(sug_hash)"
  [ "$sug_now" != "$sug_base" ] && { echo "EVENT=STOP-UNGUARDED $wt/STOP-UNGUARDED.marker — the builder stopped without a terminal fact and the gate could not hold it"; exit 0; }

  np_now="$(np_hash)"
  [ "$np_now" != "$np_base" ] && { echo "EVENT=NEEDS-OPERATOR-CHANGED $wt/NEEDS-OPERATOR.md"; exit 0; }

  # Tip moves are bookkeeping, not decisions: append to the digest and keep watching.
  now_tip="$(git -C "$wt" rev-parse "$branch" 2>/dev/null || echo "$tip")"
  if [ "$now_tip" != "$tip" ]; then
    git -C "$wt" log --format='%h %ci %s' "$tip..$now_tip" 2>/dev/null >> "$digest" \
      || echo "$(date '+%Y-%m-%d %H:%M:%S') tip moved ${tip:0:8} -> ${now_tip:0:8} (log range unreadable)" >> "$digest"
    tip="$now_tip"
  fi

  # Review polling is 5x cheaper than the loop: the 600s grace makes sub-minute
  # freshness pointless, so shell out to roborev only every 5th poll (~300s).
  poll_n=$(( ${poll_n:-0} + 1 ))
  if [ $(( poll_n % 5 )) -eq 1 ]; then
    fails="$(stale_fails)"
    [ -n "$fails" ] && {
      echo "EVENT=REVIEW-FAIL branch=$branch open-F past ${fail_grace_secs}s grace — READ THE BODY before treating as real (sentinel mis-grade gives clean reviews an F):"
      echo "$fails"
      exit 0
    }
  fi

  now=$(date +%s)
  head_ts="$(git -C "$wt" for-each-ref --format='%(committerdate:unix)' refs/heads | sort -n | tail -1)"
  tr_file="$(ls -t "$tdir"/*.jsonl 2>/dev/null | head -1)"
  tr_ts=0; [ -n "$tr_file" ] && tr_ts="$(mtime "$tr_file")"
  rp_ts=0; [ -f "$wt/MORNING-REPORT.md" ] && rp_ts="$(mtime "$wt/MORNING-REPORT.md")"
  act="${head_ts:-0}"
  [ "$tr_ts" -gt "$act" ] && act="$tr_ts"
  [ "$rp_ts" -gt "$act" ] && act="$rp_ts"
  [ $((now - act)) -gt "$stall_secs" ] && { echo "EVENT=STALL idle=$((now - act))s newest-transcript=${tr_file:-none}"; exit 0; }

  sleep "$poll_secs"
done
