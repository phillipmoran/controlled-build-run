#!/usr/bin/env bash
# captain-watch.sh — the captain's fire-once event trap over an orchestrator run.
#
# Companion to cbr.sh but deliberately NOT a cbr.sh subcommand: cbr.sh commands are
# one-shot fact-gatherers, this is a long-running trap. Same law otherwise — it DECIDES
# NOTHING. It blocks until the FIRST latching event, prints one EVENT= line, and exits.
# The exit IS the wake. Fire-once semantics: the captain re-arms it as the FIRST act of
# every wake (see SKILL.md "Captain" — a re-arm left for the end of a wake gets forgotten).
#
# Events (first one wins) — DECISION-ONLY wakes (ratified 2026-07-03): the watcher fires
# only when the captain has a judgment to make, never for bookkeeping. Every commit is
# still checked by the machinery (Probity, the pre-commit gate, per-commit RoboRev) —
# just not by a big-context session.
#   EVENT=DONE                 <worktree>/DONE.marker appeared or CHANGED since arm time.
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
#                              captain mid-fix. CAUTION at the wake: an "F" can be a clean
#                              review missing the verdict sentinel (known mis-grade) — read
#                              the review BODY before treating it as a real FAIL.
#   EVENT=STALL                no activity past --stall-secs (default 900 = 15 min): newest commit on
#                              ANY branch, the orchestrator's newest transcript, and its
#                              MORNING-REPORT.md are ALL older than the dial. Silence is an
#                              alarm, so the watcher exits on the bad path too.
#
# Tip moves NO LONGER fire (was EVENT=MERGE): each new commit is appended to the per-slug
# digest .cbr-watch/<slug>.commits instead, for the captain to read at its next REAL wake.
# Waking a full-context captain per commit was the fleet's single biggest token waste, and
# the wake carried no decision — the machinery had already checked the commit.
#
# Watchdog mode (--watchdog): the dead-man over the watcher itself. Exits only when the
# slug's heartbeat file goes unrefreshed for 15 minutes — the forgot-to-re-arm condition.
# The watcher touches .cbr-watch/<slug>.heartbeat every poll, so a fresh heartbeat IS
# proof of life; the 15-minute age budget tolerates the brief watcher-less moment of
# every normal wake, which recurs constantly over a busy builder branch whose fire-once
# watcher exits on each commit. Heartbeats replaced ps scraping: in-situ watchdogs
# false-fired at exactly armed+15:00 across windows where watchers were provably alive,
# yet interactive and background probes of the same ps pipeline matched reliably — the
# discrepancy was never explained, so liveness now rests on the watcher proving itself
# via the filesystem, the same mechanism the stall check already trusts.
#
# Usage:
#   captain-watch.sh <slug> [--stall-secs N] [--fail-grace-secs N]
#                                               # fire-once watcher — ALWAYS background it;
#                                               # a foreground loop wedges the session
#   captain-watch.sh <slug> --watchdog --cycle <id>
#                                               # dead-man, backgrounded alongside the watcher,
#                                               # bound to the cycle id the watcher's armed line
#                                               # prints (bare --watchdog falls back to inference,
#                                               # which has one honestly ambiguous startup state)
#
# <slug> maps to the sibling worktree ../cockpit-<slug>, same as cbr.sh.

set -uo pipefail

die() { echo "captain-watch: $*" >&2; exit 2; }

slug="${1:-}"; [ -n "$slug" ] || die "usage: captain-watch.sh <slug> [--stall-secs N] [--fail-grace-secs N] [--watchdog [--cycle <id>]]"
shift
# A healthy builder commits and touches its transcript every few minutes, so 15 min of TOTAL
# silence is already a strong wedge signal — 30 min just delayed the wake that matters.
stall_secs=900 fail_grace_secs=600 watchdog=0 bound_cycle=""
while [ $# -gt 0 ]; do
  case "$1" in
    --stall-secs)      stall_secs="${2:-}"; shift 2 ;;
    --fail-grace-secs) fail_grace_secs="${2:-}"; shift 2 ;;
    --watchdog)        watchdog=1; shift ;;
    --cycle)           bound_cycle="${2:-}"; shift 2 ;;
    *) die "unknown arg '$1'" ;;
  esac
done
[ -n "$bound_cycle" ] && [ "$watchdog" -ne 1 ] && die "--cycle only applies to --watchdog (the watcher MINTS the cycle; it cannot be told one)"

# Root from the script's own location, NOT the invoker's cwd: watcher and watchdog
# rendezvous solely on the heartbeat path, so a watchdog launched from a different
# checkout (say, inside a cockpit-<slug> worktree) must still resolve the same file.
root="$(cd "$(dirname "$0")/../../.." && pwd -P)" || die "cannot resolve repo root from script location"

# The shared strand mechanics — marker identity among them. A watcher that
# cannot load them still watches, because a watcher that refuses to arm leaves a
# builder with nobody looking at it, which is the worse of the two failures. It
# says so out loud at arm time rather than running quietly unguarded.
CBR_STRAND_LIB="$(dirname "$0")/../references/core/scripts/strand-lib.sh"
if [ -f "$CBR_STRAND_LIB" ]; then
  . "$CBR_STRAND_LIB"
else
  cbr_marker_counts_as_done() { [ -f "$1" ]; }
  cbr_guard_note="WARNING: shared strand library not found at $CBR_STRAND_LIB — marker-identity guard UNAVAILABLE, an inherited marker can false-latch"
fi

# Poll interval. A dial rather than a constant so the loop can be exercised by a
# test in seconds instead of minutes; the default is the operational value.
poll_secs="${CBR_WATCH_POLL_SECONDS:-60}"
wt="$(dirname "$root")/cockpit-$slug"   # sibling of the repo, same mapping as cbr.sh

hb="$root/.cbr-watch/$slug.heartbeat"
# DONE is terminal for the watcher/watchdog PAIR: once the watcher latches it,
# the builder is finished and the tier above is mid-merge-gate, so the
# watchdog's "re-arm BOTH" page is a false alarm there. The mechanism is a
# cycle id, not a clock: the watcher mints one at arm, the watchdog captures
# the current one at ITS arm, and the sentinel the watcher leaves at the DONE
# latch names the cycle it completed — a watchdog retires only when the
# sentinel names the cycle it captured. Nobody ever deletes the sentinel
# (deletion races a fix-round re-arm against a sleeping watchdog and strands
# it), and no timestamps are compared (whole-second mtimes make a same-second
# arm-vs-latch ambiguous in both directions). A fix round mints a new cycle,
# so its watchdog ignores the old cycle's sentinel by content, exactly.
done_latched="$root/.cbr-watch/$slug.done-latched"
cycle_file="$root/.cbr-watch/$slug.cycle"
sentinel_cycle() { sed -n 's/^cycle=//p' "$done_latched" 2>/dev/null | head -1; }
mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }

# ---- watchdog mode ----------------------------------------------------------
if [ "$watchdog" -eq 1 ]; then
  # Baseline from arm time so a heartbeat already stale when the watchdog arms
  # (watcher fired long ago, captain never re-armed) still gets the full 15-minute
  # grace before the alarm, instead of firing on the first check.
  armed_ts="$(date +%s)"
  page_secs="${CBR_WATCHDOG_PAGE_SECONDS:-900}"
  # WHICH cycle this watchdog guards. The exact answer is --cycle <id>, copied
  # from the watcher's own "armed: ... cycle=<id>" line: with it there is no
  # inference at all — retire the moment the sentinel names that id (even if
  # it already does at arm: the arm-er read the id off a live watcher, so a
  # sentinel naming it IS that pair's completion), and retire as a no-action
  # supersession when the cycle file moves on to a different id (a newer pair
  # guards now; this watchdog's cycle can no longer complete).
  #
  # WITHOUT --cycle the files must be read, and one state is genuinely
  # ambiguous, because both files persist across cycles: cycle file and
  # sentinel naming the SAME id at arm is either a pair that completed just
  # before this watchdog started reading (retiring is right) or a
  # watchdog-first re-arm over an old finished cycle (retiring abandons the
  # incoming watcher). Bare mode treats it as history and waits for the next
  # cycle to mint — but when nothing mints before the page deadline it emits
  # an AMBIGUOUS-DONE no-action wake naming both readings, never the
  # mandatory re-arm page: a mandatory page whose honest answer can be
  # "ignore it" trains the reader to ignore the real ones.
  if [ -n "$bound_cycle" ]; then
    my_cycle="$bound_cycle" hist="" explicit=1
  else
    my_cycle="$(cat "$cycle_file" 2>/dev/null || true)"
    hist="" explicit=0
    [ -n "$my_cycle" ] && [ "$(sentinel_cycle)" = "$my_cycle" ] && hist="$my_cycle"
  fi
  echo "watchdog armed: slug=$slug cycle=${my_cycle:-pending}${hist:+ (already completed — waiting for the next cycle)} (fires only when the heartbeat is stale for 15 min)"
  while true; do
    if [ "$explicit" -eq 1 ]; then
      if [ "$(sentinel_cycle)" = "$my_cycle" ]; then
        echo "EVENT=WATCH-DONE slug=$slug cycle=$my_cycle — watcher latched DONE; builder finished, NO re-arm needed"
        exit 0
      fi
      cur="$(cat "$cycle_file" 2>/dev/null || true)"
      if [ -n "$cur" ] && [ "$cur" != "$my_cycle" ]; then
        echo "EVENT=WATCH-SUPERSEDED slug=$slug cycle=$my_cycle — a newer watch cycle ($cur) has been armed; that pair guards now. Retiring, NO ACTION needed"
        exit 0
      fi
    fi
    sleep "$poll_secs"
    # closeout reaps the worktree + watch files — that is stream death by design, not a
    # missing watcher. Exit as an explicit no-action wake instead of paging for a re-arm.
    if [ ! -d "$wt" ] && [ ! -f "$hb" ]; then
      echo "EVENT=WATCH-REAPED slug=$slug — stream closed out; watchdog retiring, NO ACTION needed"
      exit 0
    fi
    if [ "$explicit" -eq 0 ]; then
      # Only a completion of THE CYCLE THIS WATCHDOG GUARDS retires it — never
      # one that predates it, and never an older cycle's: either mistake leaves
      # a re-armed watcher running with no dead-man at all. Checked BEFORE the
      # rebind below: a fix-round re-arm can land between two wakes, and
      # rebinding first would discard the completed cycle's retirement signal.
      if [ -n "$my_cycle" ] && [ "$my_cycle" != "$hist" ] && [ "$(sentinel_cycle)" = "$my_cycle" ]; then
        echo "EVENT=WATCH-DONE slug=$slug cycle=$my_cycle — watcher latched DONE; builder finished, NO re-arm needed"
        exit 0
      fi
      cur="$(cat "$cycle_file" 2>/dev/null || true)"
      [ "$cur" != "$my_cycle" ] && { my_cycle="$cur"; hist=""; }
    fi
    last="$(mtime "$hb")"
    [ "$last" -lt "$armed_ts" ] && last="$armed_ts"
    if [ $(( $(date +%s) - last )) -gt "$page_secs" ]; then
      if [ "$explicit" -eq 0 ] && [ -n "$hist" ] && [ "$my_cycle" = "$hist" ]; then
        echo "EVENT=WATCH-AMBIGUOUS-DONE slug=$slug cycle=$my_cycle — this cycle was already completed when the watchdog armed and no new cycle appeared since. Either the pair finished as armed (then: no action) or a fix-round watcher was never armed (then: arm the watcher FIRST, then the watchdog — or bind it exactly with --cycle <id> from the watcher's armed line). Check cbr.sh status $slug to tell which."
        exit 0
      fi
      echo "EVENT=WATCHER-UNARMED-15MIN slug=$slug — re-arm BOTH now (this is mandatory, not advisory): cbr.sh watch $slug, then bind its dead-man with the cycle id the watcher's armed line prints: cbr.sh watch $slug --watchdog --cycle <id>. A dead stall watcher is never waived — check the builder with cbr.sh status $slug first."
      exit 0
    fi
  done
fi

# ---- watcher mode -----------------------------------------------------------
[ -d "$wt" ] || die "worktree '$wt' does not exist — provision the orchestrator first"
wt_real="$(cd "$wt" && pwd -P)"
branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD)" || die "cannot read the worktree's branch"
# Marker identity needs the branch NAME, and needs to know when there isn't one.
# `rev-parse --abbrev-ref HEAD` prints the literal string HEAD on a detached
# worktree — non-empty, so it reads as a branch called HEAD, and every marker
# naming a real branch then looks foreign and DONE never fires again.
# `branch --show-current` prints nothing there, which is the honest answer and
# the one cbr_marker_counts_as_done is built to take.
watched_branch="$(git -C "$wt" branch --show-current 2>/dev/null || true)"
tip="$(git -C "$wt" rev-parse "$branch")" || die "cannot resolve the branch tip"

# Claude project transcript dir for the worktree: path with / and . mapped to -
tdir="$HOME/.claude/projects/$(printf '%s' "$wt_real" | tr '/.' '--')"

np_hash()   { git hash-object "$wt/NEEDS-OPERATOR.md" 2>/dev/null || echo none; }
done_hash() { git hash-object "$wt/DONE.marker"    2>/dev/null || echo none; }

# Open-FAIL reviews on the watched branch, older than the grace window. Prints one line
# per qualifying review ("<id> <sha8> <age_s>s"); empty output = nothing to fire on.
# roborev prints literal `null` for an empty --open list (known trap) — python treats
# that as no rows. Any parse/CLI failure degrades to empty (never a false page); the
# roborev-clean gate remains the hard backstop.
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
done_base="$(done_hash)"
digest="$root/.cbr-watch/$slug.commits"
mkdir -p "$(dirname "$hb")" && touch "$hb"
# Mint this watch cycle's id — pid+random keeps two same-second arms distinct.
cycle="$(date +%s)-$$-$RANDOM"
printf '%s\n' "$cycle" > "$cycle_file"
echo "armed: slug=$slug cycle=$cycle branch=$branch watched-branch=${watched_branch:-none-detached} tip=${tip:0:8} needs-operator=${np_base:0:8} done-marker=${done_base:0:8} stall-secs=$stall_secs fail-grace-secs=$fail_grace_secs digest=$digest"
echo "arm the dead-man BOUND to this cycle: cbr.sh watch $slug --watchdog --cycle $cycle"
[ -n "${cbr_guard_note:-}" ] && echo "$cbr_guard_note"
[ "$done_base" != none ] && echo "note: stale DONE.marker present at arm — DONE fires only when its content CHANGES (fix-round semantics)"

while true; do
  touch "$hb"
  done_now="$(done_hash)"
  # A changed marker is not enough: after a merge the worktree can be carrying a
  # marker that belongs to a strand which finished days ago, and latching on it
  # reports THIS build complete while leaving its builder unwatched.
  if [ "$done_now" != "$done_base" ] && [ "$done_now" != none ]; then
    if cbr_marker_counts_as_done "$wt/DONE.marker" "$watched_branch"; then
      printf 'cycle=%s\n%s\n' "$cycle" "$(tail -1 "$wt/DONE.marker" 2>/dev/null)" > "$done_latched"
      echo "EVENT=DONE $(tail -1 "$wt/DONE.marker")"
      exit 0
    fi
    # Re-baseline, or every later poll re-reports the same inherited marker.
    echo "note: DONE.marker changed but names another strand ($(head -1 "$wt/DONE.marker")) — not latching; watching on"
    done_base="$done_now"
  fi

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
