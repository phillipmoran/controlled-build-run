#!/usr/bin/env bash
# Fire-once watcher and independent dead-man for one registered Codex strand.
set -euo pipefail

slug="${1:-}"; shift || true
[ -n "$slug" ] || { echo "usage: captain-watch-codex.sh <slug> [--watchdog]" >&2; exit 2; }
watchdog=0
[ "${1:-}" = "--watchdog" ] && watchdog=1
poll="${CBR_WATCH_POLL_SECONDS:-15}"
review_tmp=""
trap '[ -n "$review_tmp" ] && rm -f "$review_tmp" || true' EXIT

root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 2
common="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)"
primary="$(dirname "$common")"
run="$primary/.cbr-codex/runs/$slug"
watch="$primary/.cbr-codex/watch"
mkdir -p "$watch"
[ -d "$run" ] || { echo "WATCH-EVENT registry-missing slug=$slug"; exit 2; }
wt="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["worktree"])' "$run/meta.json")"
state="$watch/$slug.state"
heartbeat="$watch/$slug.heartbeat"
needs_arm="$watch/$slug.needs-arm"
stall="$(python3 - "$root/.cbr-codex.json" <<'PY'
import json,sys
try: print(int(json.load(open(sys.argv[1])).get("stallSeconds",900)))
except Exception: print(900)
PY
)"
deadman="$(python3 - "$root/.cbr-codex.json" <<'PY'
import json,sys
try: print(int(json.load(open(sys.argv[1])).get("watchdogSeconds",900)))
except Exception: print(900)
PY
)"

epoch() { python3 - "$1" <<'PY'
import os,sys
try: print(int(os.stat(sys.argv[1]).st_mtime))
except OSError: print(0)
PY
}
digest() { [ -f "$1" ] && shasum -a 256 "$1" | awk '{print $1}' || printf absent; }

# The shared strand mechanics — marker identity among them. A watcher that
# cannot load them still watches: refusing to arm leaves a builder with nobody
# looking at it, which is the worse failure. It says so out loud instead of
# running quietly unguarded.
CBR_STRAND_LIB="$(cd "$(dirname "$0")" && pwd)/../references/cbr-core/scripts/strand-lib.sh"
if [ -f "$CBR_STRAND_LIB" ]; then
  . "$CBR_STRAND_LIB"
else
  cbr_marker_counts_as_done() { [ -f "$1" ]; }
  echo "WATCH-NOTE marker-identity guard UNAVAILABLE (no $CBR_STRAND_LIB) — an inherited marker can false-latch"
fi

# The branch this watcher is watching. A completion marker in the worktree is
# only this strand's if it names this branch: after a merge the worktree can be
# carrying one that belongs to a strand which finished days ago, and latching on
# it reports THIS build complete while leaving its builder unwatched.
watched_branch="$(git -C "$wt" branch --show-current 2>/dev/null || true)"
# The no-readable-branch case is the shared predicate's business, not this
# leaf's: it was law living as a private function in one harness.
done_marker_is_ours() { cbr_marker_counts_as_done "$wt/DONE.marker" "$watched_branch"; }
alive() {
  [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null
}

if [ "$watchdog" -eq 1 ]; then
  watchdog_started="$(date +%s)"
  while :; do
    [ -d "$run" ] || { echo "WATCHDOG-EVENT registry-retired slug=$slug"; exit 0; }
    now="$(date +%s)"; heartbeat_epoch="$(epoch "$heartbeat")"
    if [ "$heartbeat_epoch" -eq 0 ]; then age=$((now - watchdog_started)); else age=$((now - heartbeat_epoch)); fi
    pid="$(cat "$run/pid" 2>/dev/null || true)"
    if ! alive "$pid" && done_marker_is_ours; then
      echo "WATCHDOG-EVENT retired slug=$slug"
      exit 0
    fi
    if [ "$age" -gt "$deadman" ]; then
      echo "WATCHDOG-EVENT stale-heartbeat slug=$slug age_seconds=$age"
      exit 1
    fi
    sleep "$poll"
  done
fi

done0="$(digest "$wt/DONE.marker")"; ask0="$(digest "$wt/ASK-ORCH.md")"
printf 'done=%s\nask=%s\narmed=%s\n' "$done0" "$ask0" "$(date +%s)" >"$state"
rm -f "$needs_arm"

while :; do
  now="$(date +%s)"; printf '%s\n' "$now" >"$heartbeat"
  done1="$(digest "$wt/DONE.marker")"; ask1="$(digest "$wt/ASK-ORCH.md")"
  if [ "$done1" != "$done0" ]; then
    if done_marker_is_ours; then echo "WATCH-EVENT done-changed slug=$slug hash=$done1"; exit 0; fi
    # Re-baseline, or every later poll re-reports the same inherited marker.
    echo "WATCH-NOTE done-marker-foreign slug=$slug branch=${watched_branch:-unknown} — not latching; watching on"
    done0="$done1"
  fi
  if [ "$ask1" != "$ask0" ]; then echo "WATCH-EVENT question-changed slug=$slug hash=$ask1"; exit 0; fi
  pid="$(cat "$run/pid" 2>/dev/null || true)"
  if ! alive "$pid"; then
    if done_marker_is_ours; then echo "WATCH-EVENT process-stopped-with-done slug=$slug pid=${pid:-absent}"; exit 0; fi
    echo "WATCH-EVENT process-died slug=$slug pid=${pid:-absent}"; exit 1
  fi
  event_age=$((now - $(epoch "$run/events.jsonl")))
  commit_epoch="$(git -C "$wt" log -1 --format=%ct 2>/dev/null || printf '%s' "$now")"
  commit_age=$((now - commit_epoch))
  if [ "$event_age" -gt "$stall" ] && [ "$commit_age" -gt "$stall" ]; then
    echo "WATCH-EVENT inactivity slug=$slug event_age=$event_age commit_age=$commit_age"
    exit 1
  fi
  branch="$(git -C "$wt" branch --show-current 2>/dev/null || true)"
  review_tmp="$(mktemp)"
  if command -v roborev >/dev/null && roborev list --open --json --branch "$branch" >"$review_tmp" 2>/dev/null && python3 - "$review_tmp" "$now" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("reviewFailGraceSeconds",600))' "$root/.cbr-codex.json")" <<'PY'
import datetime, json, sys
path = sys.argv[1]
now, grace = map(int, sys.argv[2:])
try: rows = json.load(open(path, encoding="utf-8")) or []
except Exception: raise SystemExit(1)
for row in rows:
    if row.get("verdict") != "F": continue
    raw = row.get("updated_at") or row.get("created_at") or ""
    try: then = int(datetime.datetime.fromisoformat(raw.replace("Z","+00:00")).timestamp())
    except Exception: then = now
    if now - then >= grace: raise SystemExit(0)
raise SystemExit(1)
PY
  then rm -f "$review_tmp"; echo "WATCH-EVENT aged-review-fail slug=$slug"; exit 1; fi
  rm -f "$review_tmp"; review_tmp=""
  sleep "$poll"
done
