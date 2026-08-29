#!/usr/bin/env bash
# Regression: the watchdog must not page for a re-arm after its watcher
# latched DONE.
#
# The failure was observed live on a downstream deployment (2026-08-26): the
# stall watcher exited cleanly on EVENT=DONE, and 15 minutes later the paired
# watchdog fired WATCHER-UNARMED-15MIN with mandatory "re-arm BOTH now"
# language — while the builder it protects was finished and the orchestrator
# was mid-merge-gate. A page whose only honest answer is "ignore it" trains
# the reader to ignore the real ones.
#
# The mechanism under test: the watcher mints a cycle id at arm; the watchdog
# captures the current id at ITS arm; the sentinel the watcher leaves at the
# DONE latch names the cycle it completed; a watchdog retires only when the
# sentinel names its captured cycle. Content, not clocks: whole-second mtimes
# make a same-second arm-vs-latch ambiguous, and deleting the sentinel races
# a fix-round re-arm against a sleeping watchdog — so the sentinel persists
# and the cycle id is the boundary.
set -euo pipefail

for v in $(env | sed -n 's/^\(GIT_[A-Z_]*\)=.*/\1/p'); do unset "$v"; done

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
kit="$(cd "$here/.." && pwd)"

lib="$root/skills/cbr-core/scripts/strand-lib.sh"
claude_watch="$root/skills/claude-controlled-build-run/scripts/captain-watch.sh"
[ -f "$lib" ]          || lib="$kit/skill/claude-controlled-build-run/references/core/scripts/strand-lib.sh"
[ -f "$claude_watch" ] || claude_watch="$kit/skill/claude-controlled-build-run/scripts/captain-watch.sh"

tmp="$(cd "$(mktemp -d)" && pwd -P)"
cleanup() { local rc=$?; rm -rf "$tmp"; exit "$rc"; }
trap cleanup EXIT
fail() { echo "watchdog-done.test FAIL: $1" >&2; exit 1; }

for f in "$lib" "$claude_watch"; do [ -f "$f" ] || fail "missing input: $f"; done

# Fixture repo laid out the way the watcher resolves its paths from the
# script's own location, with the library where the leaf expects to find it.
repo="$tmp/repo"; wt="$tmp/cockpit-wdslug"
mkdir -p "$repo" "$wt"
git -C "$repo" init -q -b main
echo x > "$repo/f"; git -C "$repo" -c user.email=t@t -c user.name=t add -A
git -C "$repo" -c user.email=t@t -c user.name=t commit -qm base
git -C "$wt" init -q -b stream/wdslug
echo y > "$wt/f"; git -C "$wt" -c user.email=t@t -c user.name=t add -A
git -C "$wt" -c user.email=t@t -c user.name=t commit -qm work
mkdir -p "$repo/skills/claude-controlled-build-run/scripts" \
         "$repo/skills/claude-controlled-build-run/references/core/scripts" \
         "$repo/.cbr-watch" "$tmp/nobin"
cp "$claude_watch" "$repo/skills/claude-controlled-build-run/scripts/captain-watch.sh"
cp "$lib" "$repo/skills/claude-controlled-build-run/references/core/scripts/strand-lib.sh"
chmod +x "$repo/skills/claude-controlled-build-run/scripts/captain-watch.sh"
watch_bin="$repo/skills/claude-controlled-build-run/scripts/captain-watch.sh"
sentinel="$repo/.cbr-watch/wdslug.done-latched"

run_watcher() { # run_watcher <secs> [marker line written 2s in]
  rm -f "$wt/DONE.marker"
  CBR_WATCH_POLL_SECONDS=1 PATH="$tmp/nobin:$PATH" \
    "$watch_bin" wdslug --stall-secs 86400 --fail-grace-secs 86400 >"$tmp/w.out" 2>&1 &
  local pid=$! writer= killer=
  if [ -n "${2:-}" ]; then
    ( sleep 2; printf '%s\n' "$2" > "$wt/DONE.marker" ) & writer=$!
  fi
  ( sleep "$1"; kill "$pid" 2>/dev/null || true ) & killer=$!
  wait "$pid" 2>/dev/null || true
  kill $killer $writer 2>/dev/null || true
  cat "$tmp/w.out"
}

# --- latching DONE must leave the sentinel -----------------------------------
out="$(run_watcher 8 'stream/wdslug — COMPLETE 2026-08-26')"
grep -q 'EVENT=DONE' <<<"$out" || fail "fixture broken: the watcher never latched its own DONE: $out"
[ -f "$sentinel" ] || fail "the watcher latched DONE but left no sentinel — the watchdog has nothing to retire on and will page a false WATCHER-UNARMED after the builder finished"
grep -q 'COMPLETE' "$sentinel" || fail "the sentinel does not carry the marker line — a reader cannot tell WHICH completion retired the watchdog"

# --- a watchdog retires on a DONE latched in its own cycle -------------------
# Deliberately compressed into one second wherever possible: watchdog arm,
# DONE latch, and fix-round re-arm all race each other with NO boundary
# sleeps, because both prior designs died in exactly these gaps (deletion
# lost the sentinel to a fast re-arm; second-resolution mtimes made a
# same-second latch invisible forever).
cyclef="$repo/.cbr-watch/wdslug.cycle"
rm -f "$sentinel" "$cyclef" "$wt/DONE.marker"
CBR_WATCH_POLL_SECONDS=1 PATH="$tmp/nobin:$PATH" \
  "$watch_bin" wdslug --stall-secs 86400 --fail-grace-secs 86400 >"$tmp/w2.out" 2>&1 &
wpid=$!
n=0; until [ -f "$cyclef" ] || [ "$n" -ge 50 ]; do sleep 0.2; n=$((n+1)); done
[ -f "$cyclef" ] || fail "the watcher never minted a cycle id — the watchdog has no cycle to guard"
cycle_a="$(cat "$cyclef")"
set +e
( CBR_WATCH_POLL_SECONDS=1 "$watch_bin" wdslug --watchdog >"$tmp/d.out" 2>&1 ) &
dpid=$!
printf 'stream/wdslug — COMPLETE 2026-08-26\n' > "$wt/DONE.marker"   # same second as the arm
wait "$wpid" 2>/dev/null                                             # watcher latches and exits
run_watcher 3 >/dev/null                                             # instant fix-round re-arm, mid-race
( sleep 8; kill "$dpid" 2>/dev/null ) & dkiller=$!
wait "$dpid"; drc=$?
kill "$dkiller" 2>/dev/null; wait "$dkiller" 2>/dev/null
set -e
grep -q 'EVENT=DONE' "$tmp/w2.out" || fail "fixture broken: the cycle-A watcher never latched: $(cat "$tmp/w2.out")"
grep -q "^cycle=$cycle_a\$" "$sentinel" \
  || fail "the sentinel does not name the cycle that completed — the watchdog cannot tell whose DONE this is: $(cat "$sentinel")"
grep -q 'EVENT=WATCH-DONE' "$tmp/d.out" \
  || fail "a DONE latched the same second the watchdog armed (with an instant watcher re-arm racing it) did not retire the watchdog — post-DONE it will still page for a re-arm: $(cat "$tmp/d.out")"
[ "$drc" -eq 0 ] || fail "the watchdog's DONE retirement exited $drc — a nonzero exit turns a no-action wake into an alarm"
grep -q 'WATCHER-UNARMED' "$tmp/d.out" \
  && fail "the watchdog paged WATCHER-UNARMED in the same run it retired — two contradictory instructions to the same reader"
[ -f "$sentinel" ] \
  || fail "something deleted the sentinel — deletion is the race this design exists to remove"

# --- a fresh watchdog must NOT retire on a PREVIOUS cycle's sentinel ---------
# run_watcher above minted cycle B; the sentinel still names cycle A.
[ "$(cat "$cyclef")" = "$cycle_a" ] && fail "fixture broken: the re-arm did not mint a new cycle"
set +e
( CBR_WATCH_POLL_SECONDS=1 "$watch_bin" wdslug --watchdog >"$tmp/g.out" 2>&1 ) &
gpid=$!
( sleep 4; kill "$gpid" 2>/dev/null ) & gkiller=$!
wait "$gpid" 2>/dev/null
set -e
kill "$gkiller" 2>/dev/null || true; wait "$gkiller" 2>/dev/null || true
grep -q 'watchdog armed' "$tmp/g.out" \
  || fail "the fix-round watchdog did not arm: $(cat "$tmp/g.out")"
grep -q 'EVENT=WATCH-DONE' "$tmp/g.out" \
  && fail "a fresh watchdog retired on the previous cycle's sentinel — the re-armed watcher now runs with no dead-man at all"

# --- watchdog-first re-arm: a completed cycle found at arm is history --------
# Both files persist, so a watchdog armed BEFORE its replacement watcher finds
# the previous cycle's id with a sentinel already naming it. Retiring on that
# is a false instant-retire (the new watcher runs with no dead-man); staying
# bound to it forever goes deaf to the new cycle's DONE. It must do neither:
# wait past the completed cycle, rebind when the new watcher mints, retire on
# the new cycle's completion.
out="$(run_watcher 8 'stream/wdslug — COMPLETE 2026-08-26')"
grep -q 'EVENT=DONE' <<<"$out" || fail "fixture broken: the cycle-C watcher never latched: $out"
cycle_c="$(cat "$cyclef")"
grep -q "^cycle=$cycle_c\$" "$sentinel" || fail "fixture broken: sentinel does not name cycle C"
set +e
( CBR_WATCH_POLL_SECONDS=1 "$watch_bin" wdslug --watchdog >"$tmp/h.out" 2>&1 ) &
hpid=$!
sleep 3
grep -q 'EVENT=WATCH-DONE' "$tmp/h.out" \
  && fail "a watchdog armed AFTER cycle C completed retired on C's sentinel — the next watcher will run with no dead-man at all: $(cat "$tmp/h.out")"
grep -q 'already completed' "$tmp/h.out" \
  || fail "the watchdog did not say it is waiting past the completed cycle — silence here is indistinguishable from being bound to it: $(cat "$tmp/h.out")"
rm -f "$wt/DONE.marker"
CBR_WATCH_POLL_SECONDS=1 PATH="$tmp/nobin:$PATH" \
  "$watch_bin" wdslug --stall-secs 86400 --fail-grace-secs 86400 >"$tmp/w3.out" 2>&1 &
w3pid=$!
n=0; until [ "$(cat "$cyclef")" != "$cycle_c" ] || [ "$n" -ge 50 ]; do sleep 0.2; n=$((n+1)); done
[ "$(cat "$cyclef")" != "$cycle_c" ] || fail "fixture broken: the replacement watcher never minted a new cycle"
printf 'stream/wdslug — COMPLETE 2026-08-26 round two\n' > "$wt/DONE.marker"
wait "$w3pid" 2>/dev/null
( sleep 8; kill "$hpid" 2>/dev/null ) & hkiller=$!
wait "$hpid"; hrc=$?
kill "$hkiller" 2>/dev/null; wait "$hkiller" 2>/dev/null
set -e
grep -q 'EVENT=WATCH-DONE' "$tmp/h.out" \
  || fail "the watchdog stayed bound to the completed old cycle and went deaf to the new watcher's DONE — post-DONE it will page a false WATCHER-UNARMED: $(cat "$tmp/h.out")"
[ "$hrc" -eq 0 ] || fail "the rebound watchdog's retirement exited $hrc"

# --- explicit binding: the ambiguity killer ----------------------------------
# --cycle <id> is the exact handshake: no inference from persistent files.
# The reviewer-demanded startup race first: the paired watcher completes
# ENTIRELY before its watchdog starts reading state — with the id in hand the
# watchdog must recognize its own pair's completion immediately, where bare
# mode can only call the same bytes history.
out="$(run_watcher 8 'stream/wdslug — COMPLETE 2026-08-26 explicit round')"
grep -q 'EVENT=DONE' <<<"$out" || fail "fixture broken: the explicit-round watcher never latched: $out"
# The id is taken from the watcher's own armed line — the documented
# procedure — not from the internal cycle file: an operator can only bind
# what the output hands them.
cycle_e="$(sed -n 's/^armed: slug=wdslug cycle=\([^ ]*\).*/\1/p' <<<"$out")"
[ -n "$cycle_e" ] \
  || fail "the watcher's armed line does not print its minted cycle id — the documented --cycle workflow has nothing to copy: $out"
grep -q -- "--watchdog --cycle $cycle_e" <<<"$out" \
  || fail "the watcher does not print the exact dead-man arm command for its cycle — the operator is left to reconstruct the binding by hand: $out"
grep -q "^cycle=$cycle_e\$" "$sentinel" || fail "fixture broken: sentinel does not name the explicit-round cycle"
set +e
( CBR_WATCH_POLL_SECONDS=1 "$watch_bin" wdslug --watchdog --cycle "$cycle_e" >"$tmp/e.out" 2>&1 ) &
epid=$!
( sleep 5; kill "$epid" 2>/dev/null ) & ekiller=$!
wait "$epid"; erc=$?
kill "$ekiller" 2>/dev/null; wait "$ekiller" 2>/dev/null
set -e
grep -q 'EVENT=WATCH-DONE' "$tmp/e.out" \
  || fail "a watchdog bound with --cycle to a pair that completed before it started did not retire — the explicit handshake does not close the startup race it exists for: $(cat "$tmp/e.out")"
[ "$erc" -eq 0 ] || fail "the explicit watchdog's retirement exited $erc"

# An explicitly-bound watchdog whose cycle was superseded retires as a
# no-action wake: its cycle can never complete once a newer pair guards.
set +e
( CBR_WATCH_POLL_SECONDS=1 "$watch_bin" wdslug --watchdog --cycle "bygone-0-0" >"$tmp/s.out" 2>&1 ) &
spid=$!
( sleep 5; kill "$spid" 2>/dev/null ) & skiller=$!
wait "$spid"; src=$?
kill "$skiller" 2>/dev/null; wait "$skiller" 2>/dev/null
set -e
grep -q 'EVENT=WATCH-SUPERSEDED' "$tmp/s.out" \
  || fail "a watchdog bound to a superseded cycle did not retire — it would idle forever on a cycle that can no longer complete, then page: $(cat "$tmp/s.out")"
[ "$src" -eq 0 ] || fail "the superseded watchdog exited $src — supersession is a no-action wake, not an alarm"

# --- bare mode's page in the ambiguous state must name the ambiguity ---------
# cycle file and sentinel agree (the explicit round completed), no new cycle
# ever appears: the deadline event must be AMBIGUOUS-DONE with both readings,
# never the mandatory re-arm page — a mandatory page whose honest answer can
# be "ignore it" trains the reader to ignore the real ones.
set +e
( CBR_WATCH_POLL_SECONDS=1 CBR_WATCHDOG_PAGE_SECONDS=2 "$watch_bin" wdslug --watchdog >"$tmp/a.out" 2>&1 ) &
apid=$!
( sleep 8; kill "$apid" 2>/dev/null ) & akiller=$!
wait "$apid"; arc=$?
kill "$akiller" 2>/dev/null; wait "$akiller" 2>/dev/null
set -e
grep -q 'EVENT=WATCH-AMBIGUOUS-DONE' "$tmp/a.out" \
  || fail "bare mode's deadline in the completed-at-arm state did not emit the ambiguous no-action wake: $(cat "$tmp/a.out")"
grep -q 'WATCHER-UNARMED' "$tmp/a.out" \
  && fail "bare mode paged the mandatory re-arm in a state whose honest answer can be 'the pair finished' — that is the false page this whole mechanism exists to kill"
[ "$arc" -eq 0 ] || fail "the ambiguous-done wake exited $arc"

# --- and the REAL unarmed page must survive all of this ----------------------
rm -f "$sentinel" "$cyclef" "$repo/.cbr-watch/wdslug.heartbeat"
set +e
( CBR_WATCH_POLL_SECONDS=1 CBR_WATCHDOG_PAGE_SECONDS=2 "$watch_bin" wdslug --watchdog >"$tmp/u.out" 2>&1 ) &
upid=$!
( sleep 8; kill "$upid" 2>/dev/null ) & ukiller=$!
wait "$upid" 2>/dev/null
set -e
kill "$ukiller" 2>/dev/null || true; wait "$ukiller" 2>/dev/null || true
grep -q 'EVENT=WATCHER-UNARMED' "$tmp/u.out" \
  || fail "with no watcher, no cycle, and no heartbeat, the watchdog never paged — the DONE machinery has eaten the alarm it was built around: $(cat "$tmp/u.out")"

# --- doc lint: no operational surface may prescribe bare dead-man arming -----
# The handshake only exists if the workflow reaches it: an arm instruction
# anywhere that says `watch <slug> --watchdog` without `--cycle` re-opens the
# ambiguous startup state for every operator who follows it. Descriptive
# mentions of the watchdog are fine; PRESCRIPTIONS (watch + slug + --watchdog
# on one line) must carry the binding.
leaf_dir="$(cd "$(dirname "$claude_watch")/.." && pwd)"
lint_files=""
for f in "$leaf_dir/SKILL.md" "$leaf_dir/references/claude.md" \
         "$leaf_dir/references/acceptance-checklist.md" \
         "$leaf_dir/scripts/cbr.sh" "$claude_watch"; do
  [ -f "$f" ] && lint_files="$lint_files $f"
done
# Prescriptions wrap across lines in the prose docs, so the match unit is the
# PARAGRAPH (blank-line separated), newlines collapsed, not the line — a
# line-based lint is blind to exactly the passages it exists to guard. Within
# a paragraph each `--watchdog` is judged on its own: the text before it must
# not be a watch-command invocation left unbound, whatever a NEIGHBORING bound
# command says — a paragraph-wide `--cycle` check lets one bound prescription
# launder a bare one beside it. A prescription is recognized by COMMAND SHAPE,
# not by the argument spelling: an explicit script invocation with any
# argument (`cbr.sh watch payments`, `captain-watch.sh <slug>`) or a bare
# `watch <placeholder>` — so a concrete slug or a renamed placeholder cannot
# slip past a lint that only knew the word "slug". Plain prose about "the
# watch script" stays exempt: it has neither shape.
lint_bare() {
  awk 'BEGIN{RS=""}
    { p=$0; gsub(/\n[[:space:]]*/," ",p)
      n=split(p, seg, /--watchdog/)
      for (i=1; i<n; i++)
        if (seg[i] ~ /((cbr\.sh +watch|captain-watch\.sh) +[[:alnum:]<$_]|(^|[^[:alnum:]_-])watch +<[^>|]*>)[^|]*$/ \
            && seg[i+1] !~ /^[`[:space:][]*--cycle/) {
          printf "%s: %.160s\n", FILENAME, p; break
        }
    }' "$@"
}
# The lint must be proven able to fail: a multiline bare prescription that a
# line-based grep cannot see.
printf 'arm the trap with `cbr.sh watch <slug>`\nand `--watchdog` as its dead-man.\n' > "$tmp/bare-doc.md"
[ -n "$(lint_bare "$tmp/bare-doc.md")" ] \
  || fail "the doc lint passed a multiline bare-watchdog prescription — it cannot catch the wrapped prose it exists to guard"
printf 'arm the trap with `cbr.sh watch <slug>`\nand `--watchdog --cycle <id>` as its dead-man.\n' > "$tmp/bound-doc.md"
[ -z "$(lint_bare "$tmp/bound-doc.md")" ] \
  || fail "the doc lint flagged a correctly bound multiline prescription"
# A bound prescription must not launder a bare one in the same paragraph —
# bare first is the exact shape a greedy paragraph-wide match waves through.
printf 'run `cbr.sh watch <slug> --watchdog` now,\nand later re-arm with `cbr.sh watch <slug>`\nplus `--watchdog --cycle <id>`.\n' > "$tmp/mixed-doc.md"
[ -n "$(lint_bare "$tmp/mixed-doc.md")" ] \
  || fail "the doc lint passed a paragraph mixing a bare prescription with a bound one — a neighboring --cycle must not exempt a bare arm"
# The prescription is recognized by command shape, not argument spelling: a
# concrete slug and a renamed placeholder must both be caught bare.
printf 'run `cbr.sh watch payments --watchdog`\nto arm the dead-man.\n' > "$tmp/concrete-doc.md"
[ -n "$(lint_bare "$tmp/concrete-doc.md")" ] \
  || fail "the doc lint passed a bare prescription with a concrete slug — it only knew the word slug"
printf 'arm with `cbr.sh watch <stream>`\nand `--watchdog` as its dead-man.\n' > "$tmp/altph-doc.md"
[ -n "$(lint_bare "$tmp/altph-doc.md")" ] \
  || fail "the doc lint passed a bare prescription with a non-slug placeholder"
# Prose ABOUT the watch script is not a prescription and must stay exempt.
printf 'The watch script logs commits; its dead-man is `--watchdog`\nat 15 min and needs no binding here.\n' > "$tmp/prose-doc.md"
[ -z "$(lint_bare "$tmp/prose-doc.md")" ] \
  || fail "the doc lint flagged descriptive prose about the watch script as a prescription"
# shellcheck disable=SC2086
bare="$(lint_bare $lint_files 2>/dev/null || true)"
[ -z "$bare" ] \
  || fail "an operational surface still prescribes bare --watchdog arming — every operator following it bypasses the cycle handshake: $bare"

echo "watchdog-done.test PASS (cycle-id sentinel; same-second + instant-re-arm races; watchdog-first waits past history; --cycle closes the startup race and supersession; ambiguous deadline is a no-action wake; the real unarmed page still fires; no doc prescribes bare arming)"
