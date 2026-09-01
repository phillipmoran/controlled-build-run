#!/usr/bin/env bash
# Process-health tripwires over the recorder event log (~/.cbr/events/*.jsonl).
# Read-only toward the log; the only side effect is a notification per trip.
#
# Four ratio checks, each a symptom of process eating product:
#   rounds        — >ROUNDS_MAX review-fix commits since the last integration
#   process-share — process-typed commits >PROCESS_SHARE_PCT% of the last
#                   COMMIT_WINDOW (evaluated only at >=MIN_COMMITS sample)
#   silence       — no agent/tool/commit/user activity for >SILENCE_MIN
#                   minutes while review obligations are open
#   no-product    — >=ACTIVE_HOURS_MIN distinct active hours with zero
#                   product commits since the last integration
#
# Exit 0 when nothing trips, 1 when anything does. Each trip is delivered
# through $CBR_TRIPWIRE_NOTIFY (a command receiving the message as one arg);
# the default posts a desktop notification and appends to ~/.cbr/tripwires.log.
set -euo pipefail

# --- thresholds (one block; self-calibrating later — seeded from the PR-4
# --- boundary loop, where 13 review reruns and a >50% process-commit day
# --- were measured as waste worth paging over) ------------------------------
ROUNDS_MAX=3
PROCESS_SHARE_PCT=50
COMMIT_WINDOW=20
MIN_COMMITS=10
SILENCE_MIN=30
ACTIVE_HOURS_MIN=3

log=""
now_ms=""
while [ $# -gt 0 ]; do
  case "$1" in
    --log) log="$2"; shift 2 ;;
    --now) now_ms="$2"; shift 2 ;;
    *) echo "tripwires: unknown arg $1" >&2; exit 2 ;;
  esac
done
if [ -z "$log" ]; then
  # the recorder keys the log by the PRIMARY worktree path with both '/' and
  # '.' mapped to '-' (slugifyPath); a linked worktree must resolve to the
  # primary's log, not its own path
  root="$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
  [ -n "$root" ] || root="$(pwd)"
  log="$HOME/.cbr/events/$(printf '%s' "$root" | tr '/.' '--').jsonl"
fi
[ -f "$log" ] || exit 0   # no recorder log: nothing to measure, fail open
[ -n "$now_ms" ] || now_ms="$(( $(date +%s) * 1000 ))"

notify() {
  if [ -n "${CBR_TRIPWIRE_NOTIFY:-}" ]; then
    "$CBR_TRIPWIRE_NOTIFY" "$1"
  else
    mkdir -p "$HOME/.cbr"
    printf '%s %s\n' "$(date -u +%FT%TZ)" "$1" >> "$HOME/.cbr/tripwires.log"
    command -v osascript >/dev/null 2>&1 && \
      osascript -e "display notification \"$1\" with title \"CBR tripwire\"" \
      >/dev/null 2>&1 || true
  fi
}

# the heredoc runs outside $() — the stock macOS bash 3.2 misparses
# quoted heredocs inside command substitution
trips_out="$(mktemp)"
trap 'rm -f "$trips_out"' EXIT
python3 - "$log" "$now_ms" \
  "$ROUNDS_MAX" "$PROCESS_SHARE_PCT" "$COMMIT_WINDOW" "$MIN_COMMITS" \
  "$SILENCE_MIN" "$ACTIVE_HOURS_MIN" > "$trips_out" <<'PY'
import json, re, sys

log, now_ms = sys.argv[1], int(sys.argv[2])
rounds_max, share_pct, window, min_commits, silence_min, active_hours_min = (
    int(a) for a in sys.argv[3:9])

events = []
with open(log, encoding="utf-8", errors="replace") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            events.append(json.loads(line))
        except ValueError:
            continue  # a torn tail line is not a health signal

# scope every ratio to the stretch since the last integration — a merged
# stream's fix chain is settled history, not a live symptom
def is_merge(e):
    if e.get("event_type") in ("stream.merged", "stream.integrated"):
        return True
    # the recorder's merge-unparsed warning certifies a real merge commit it
    # could not attribute to a branch; as a TIME boundary for these ratios the
    # merge fact is what matters, so a warning-only merge still resets the
    # window — otherwise the rounds wire cries wolf forever after any locally
    # merged PR whose subject the recorder cannot parse
    return e.get("event_type") == "log.message" and ":merge-unparsed" in e.get("event_id", "")

last_merge = max((e.get("event_time", 0) for e in events if is_merge(e)), default=0)
since = [e for e in events if e.get("event_time", 0) >= last_merge]

REVIEW_FIX = re.compile(r"(review|roborev)s? [0-9]", re.I)
PROCESS = re.compile(r"^(docs|chore|build|ci|config|records)[(:]")

commits = [e for e in since if e.get("event_type") == "commit.created"]
commits.sort(key=lambda e: e.get("event_time", 0))
msgs = [(e.get("payload") or {}).get("message", "") for e in commits]

trips = []

fix_rounds = sum(1 for m in msgs if REVIEW_FIX.search(m))
if fix_rounds > rounds_max:
    trips.append(f"rounds {fix_rounds} review-fix commits since last merge (cap {rounds_max})")

recent = msgs[-window:]
if len(recent) >= min_commits:
    process = sum(1 for m in recent if PROCESS.match(m) or "[records]" in m)
    share = 100 * process // len(recent)
    if share > share_pct:
        trips.append(f"process-share {process}/{len(recent)} recent commits are process ({share}%)")

ACTIVITY = {"agent.working", "tool.invoked", "commit.created", "user.message"}
last_activity = max((e.get("event_time", 0) for e in since
                     if e.get("event_type") in ACTIVITY), default=0)
open_counts = [((e.get("payload") or {}).get("open_count", 0))
               for e in since if e.get("event_type") == "review.obligation"]
open_work = open_counts[-1] if open_counts else 0
if last_activity and open_work > 0:
    quiet_min = (now_ms - last_activity) // 60000
    if quiet_min > silence_min:
        trips.append(f"silence {quiet_min}min quiet with {open_work} open review obligation(s)")

active_hours = {e.get("event_time", 0) // 3600000 for e in since
                if e.get("event_type") in ("agent.working", "tool.invoked")}
product = sum(1 for m in msgs if not (PROCESS.match(m) or "[records]" in m))
if len(active_hours) >= active_hours_min and product == 0:
    trips.append(f"no-product {len(active_hours)} active hours, zero product commits")

for t in trips:
    print(t)
PY

[ -s "$trips_out" ] || exit 0
while IFS= read -r t; do
  notify "TRIP $t"
done < "$trips_out"
exit 1
