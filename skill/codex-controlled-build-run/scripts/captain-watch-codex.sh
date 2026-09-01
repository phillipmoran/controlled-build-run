#!/usr/bin/env bash
# Fire-once watcher for one registered Codex strand. (The separate --watchdog
# dead-man retired with the 2026-08-31 control-plane diet: the silence tripwire
# supersedes it. The heartbeat stays — status/doctor read its freshness.)
set -euo pipefail

slug="${1:-}"; shift || true
[ -n "$slug" ] || { echo "usage: captain-watch-codex.sh <slug>" >&2; exit 2; }
# Retired options must fail loudly, not arm an ordinary watcher: automation
# still passing --watchdog would otherwise run a silent duplicate.
[ $# -eq 0 ] || { echo "captain-watch-codex: unknown argument '$1' (--watchdog retired 2026-08-31, control-plane diet)" >&2; exit 2; }
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
[ -f "$CBR_STRAND_LIB" ] || CBR_STRAND_LIB="$(cd "$(dirname "$0")" && pwd)/../../cbr-core/scripts/strand-lib.sh"
if [ -f "$CBR_STRAND_LIB" ]; then
  . "$CBR_STRAND_LIB"
else
  cbr_marker_counts_as_done() { [ -f "$1" ]; }
  cbr_done_marker_name() { echo "DONE.marker"; }
  echo "WATCH-NOTE marker guard UNAVAILABLE (no $CBR_STRAND_LIB) — an uncommitted marker can false-latch"
fi

# The branch this watcher is watching. The completion marker is named FOR the
# branch (strand-lib cbr_done_marker_name), so an inherited marker has a
# different name and can never false-latch this watcher.
watched_branch="$(git -C "$wt" branch --show-current 2>/dev/null || true)"
done_name="$(cbr_done_marker_name "$watched_branch")"
done_marker_is_ours() { cbr_marker_counts_as_done "$wt/$done_name" "$watched_branch"; }
alive() {
  [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null
}


# The terminal facts that RELEASE a builder from the stop gate. A watcher blind
# to them turns a deliberate handoff into an unexplained stall — the builder is
# allowed to go quiet and nobody is told why.
park0="$(digest "$wt/NEEDS-HUMAN.md")"; hb0="$(digest "$wt/CONTROL-PLANE-BROKEN.marker")"
sug0="$(digest "$wt/STOP-UNGUARDED.marker")"
done0="$(digest "$wt/$done_name")"; ask0="$(digest "$wt/ASK-ORCH.md")"
done_noted=
printf 'done=%s\nask=%s\narmed=%s\n' "$done0" "$ask0" "$(date +%s)" >"$state"
rm -f "$needs_arm"

while :; do
  now="$(date +%s)"; printf '%s\n' "$now" >"$heartbeat"
  done1="$(digest "$wt/$done_name")"; ask1="$(digest "$wt/ASK-ORCH.md")"
  if [ "$done1" != "$done0" ]; then
    if done_marker_is_ours; then echo "WATCH-EVENT done-changed slug=$slug hash=$done1"; exit 0; fi
    # The watched file is the branch's own marker name, so the only refusal
    # left is an uncommitted latch — the middle of a write-then-commit, whose
    # finishing commit does not change the file. Keep the baseline (re-basing
    # would deafen the watcher to its completion) and dedupe the note.
    if [ "$done1" != "$done_noted" ]; then
      echo "WATCH-NOTE done-marker-uncommitted slug=$slug branch=${watched_branch:-unknown} — not latching; watching on"
      done_noted="$done1"
    fi
  fi
  if [ "$ask1" != "$ask0" ]; then echo "WATCH-EVENT question-changed slug=$slug hash=$ask1"; exit 0; fi
  if [ "$(digest "$wt/NEEDS-HUMAN.md")" != "$park0" ]; then echo "WATCH-EVENT needs-human slug=$slug"; exit 0; fi
  if [ "$(digest "$wt/CONTROL-PLANE-BROKEN.marker")" != "$hb0" ]; then echo "WATCH-EVENT control_plane_broken slug=$slug"; exit 0; fi
  if [ "$(digest "$wt/STOP-UNGUARDED.marker")" != "$sug0" ]; then echo "WATCH-EVENT stop-unguarded slug=$slug — the builder stopped without a terminal fact and the gate could not hold it"; exit 0; fi
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
