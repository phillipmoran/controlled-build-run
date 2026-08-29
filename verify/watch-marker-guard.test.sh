#!/usr/bin/env bash
# Regression: a DONE.marker that names a DIFFERENT strand must not latch either
# captain watcher.
#
# The failure this pins was observed live. A strand's completion marker merges
# onto the base branch with its work and stays there. The next strand folds the
# base into its own branch and inherits a marker announcing that a build which
# finished days ago is complete. Its watcher — armed before that merge, so its
# baseline was "no marker" — sees the marker appear, fires EVENT=DONE, and exits.
# The builder is then unwatched for the rest of its run, and the human is told a
# build is finished on the day it started.
#
# Closeout removing the marker from the base is the cure; this guard is the
# backstop, and a system this cheap to get wrong deserves both.
#
# Three halves:
#   PREDICATE — the shared marker-identity decision, including the cases where
#   it must NOT refuse to latch (own branch, and legacy markers naming none).
#   END TO END — each watcher is actually run against a worktree carrying a
#   sibling's marker, and must still be watching afterwards; then against its
#   own, which must fire. A guard proven only at the predicate is a guard the
#   watcher might not be calling.
#   WIRING — neither watcher may reach a DONE decision without it.
set -euo pipefail

for v in $(env | sed -n 's/^\(GIT_[A-Z_]*\)=.*/\1/p'); do unset "$v"; done

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
kit="$(cd "$here/.." && pwd)"

lib="$root/skills/cbr-core/scripts/strand-lib.sh"
claude_watch="$root/skills/claude-controlled-build-run/scripts/captain-watch.sh"
codex_watch="$root/skills/codex-controlled-build-run/scripts/captain-watch-codex.sh"
[ -f "$lib" ]          || lib="$kit/skill/claude-controlled-build-run/references/core/scripts/strand-lib.sh"
[ -f "$claude_watch" ] || claude_watch="$kit/skill/claude-controlled-build-run/scripts/captain-watch.sh"
[ -f "$codex_watch" ]  || codex_watch="$kit/skill/codex-controlled-build-run/scripts/captain-watch-codex.sh"

tmp="$(cd "$(mktemp -d)" && pwd -P)"
sleeper=""
cleanup() {
  local rc=$?
  [ -n "$sleeper" ] && { kill "$sleeper" 2>/dev/null || true; wait "$sleeper" 2>/dev/null || true; }
  rm -rf "$tmp"
  exit "$rc"
}
trap cleanup EXIT
fail() { echo "watch-marker-guard.test FAIL: $1" >&2; exit 1; }

for f in "$lib" "$claude_watch" "$codex_watch"; do [ -f "$f" ] || fail "missing input: $f"; done
# shellcheck source=/dev/null
. "$lib"

command -v cbr_marker_counts_as_done >/dev/null \
  || fail "the shared library has no cbr_marker_counts_as_done — the watchers have no single answer to 'is this marker mine'"

# ---------------------------------------------------------------------------
# PREDICATE
# ---------------------------------------------------------------------------
m="$tmp/DONE.marker"

printf 'stream/mine — COMPLETE 2026-08-19\n\nall green\n' > "$m"
cbr_marker_counts_as_done "$m" stream/mine \
  || fail "a marker naming this very branch did not count as done — the guard broke the thing it protects"

printf 'stream/sibling — COMPLETE 2026-08-14\n\nall green\n' > "$m"
cbr_marker_counts_as_done "$m" stream/mine \
  && fail "a sibling strand's marker counted as done — this is the inherited-marker false latch itself"

# Markers predate the convention that they name their branch. One that names
# none is treated as OURS: refusing to latch on it would silently disarm the
# completion signal for every older harness, which is a worse failure than the
# one being fixed and a much quieter one.
printf 'COMPLETE — all phases green\n' > "$m"
cbr_marker_counts_as_done "$m" stream/mine \
  || fail "a legacy marker naming no branch was treated as foreign — that silently disarms DONE for every marker written before the convention"

rm -f "$m"
cbr_marker_counts_as_done "$m" stream/mine \
  && fail "an absent marker counted as done"

# Branch names are far more permissive than the characters this project happens
# to use. A name the parser cannot read is not reported as unparseable — it is
# reported as naming nobody, which the watchers read as "mine", so an allowlist
# of characters silently re-opens the very hole this guard closes.
for odd in 'stream/sibling+fix' 'stream/user@host' 'feature/ünïcode' 'stream/a.b~c' \
           'stream/foo.lock' 'stream/foo/' 'stream/@{x' 'stream//foo' 'stream/.hidden'; do
  printf '%s — COMPLETE 2026-08-14\n' "$odd" > "$m"
  named="$(cbr_marker_branch "$m")"
  case "$odd" in
    *'~'*|*.lock|*/|*'@{'*|*//*|*/.*)
      # git rejects every one of these as a ref, so the honest answer is that
      # the token names nobody. Getting this wrong in the other direction is the
      # expensive case: a token accepted as a branch name that no real branch
      # can ever equal is permanently foreign, and DONE never fires again.
      [ -z "$named" ] \
        || fail "'$odd' is not a valid git ref and must not be read as a branch name (got '$named') — a name nothing can match disarms completion for the whole run" ;;
    *)
      [ "$named" = "$odd" ] \
        || fail "cbr_marker_branch could not read the valid branch name '$odd' (got '${named:-nothing}') — an unreadable marker counts as ours, so this is a sibling's marker latching"
      cbr_marker_counts_as_done "$m" stream/mine \
        && fail "a sibling marker naming '$odd' counted as done for stream/mine" ;;
  esac
done

# ---------------------------------------------------------------------------
# END TO END — each watcher, actually running
# ---------------------------------------------------------------------------
# A fixture repo laid out the way each watcher resolves its own paths from the
# location of the script, with the library where the leaf expects to find it.
build_repo() { # build_repo <repo> <worktree> <branch>
  local repo="$1" wt="$2" br="$3"
  mkdir -p "$repo" "$wt"
  git -C "$repo" init -q -b main
  echo x > "$repo/f"; git -C "$repo" -c user.email=t@t -c user.name=t add -A
  git -C "$repo" -c user.email=t@t -c user.name=t commit -qm base
  git -C "$wt" init -q -b "$br"
  echo y > "$wt/f"; git -C "$wt" -c user.email=t@t -c user.name=t add -A
  git -C "$wt" -c user.email=t@t -c user.name=t commit -qm work
}

# --- the Claude watcher ---
crepo="$tmp/c/repo"; cwt="$tmp/c/cockpit-guardslug"
build_repo "$crepo" "$cwt" stream/guardslug
mkdir -p "$crepo/skills/claude-controlled-build-run/scripts" \
         "$crepo/skills/claude-controlled-build-run/references/core/scripts"
cp "$claude_watch" "$crepo/skills/claude-controlled-build-run/scripts/captain-watch.sh"
cp "$lib" "$crepo/skills/claude-controlled-build-run/references/core/scripts/strand-lib.sh"
chmod +x "$crepo/skills/claude-controlled-build-run/scripts/captain-watch.sh"

# The marker must appear AFTER the watcher arms: both watchers baseline the
# marker at arm time and latch on a CHANGE, so a marker already in place when
# they start is, correctly, not an event at all.
run_claude() { # run_claude <secs> <marker line written 2s in>
  rm -f "$cwt/DONE.marker"
  CBR_WATCH_POLL_SECONDS=1 PATH="$tmp/nobin:$PATH" \
    "$crepo/skills/claude-controlled-build-run/scripts/captain-watch.sh" guardslug \
      --stall-secs 86400 --fail-grace-secs 86400 >"$tmp/c.out" 2>&1 &
  local pid=$!
  ( sleep 2; printf '%s\n' "$2" > "$cwt/DONE.marker" ) &
  local writer=$!
  ( sleep "$1"; kill "$pid" 2>/dev/null || true ) &
  local killer=$!
  wait "$pid" 2>/dev/null || true
  kill "$killer" "$writer" 2>/dev/null || true
  cat "$tmp/c.out"
}
mkdir -p "$tmp/nobin"   # keeps roborev out of the fixture's PATH

out="$(run_claude 8 'stream/elsewhere — COMPLETE 2026-08-14')"
grep -q 'EVENT=DONE' <<<"$out" \
  && fail "the Claude watcher latched on a marker naming stream/elsewhere while watching stream/guardslug — the builder is now unwatched and the human has been told it finished: $out"
# Absence of EVENT=DONE is not the property. A watcher that saw the foreign
# marker and quietly exited would also print nothing, and would abandon its
# builder just as completely — so the POSITIVE signal is what is asserted.
grep -q 'not latching; watching on' <<<"$out" \
  || fail "the Claude watcher did not report that it saw a foreign marker and kept watching — silence here is equally consistent with it having given up: $out"

out="$(run_claude 8 'stream/guardslug — COMPLETE 2026-08-19')"
grep -q 'EVENT=DONE' <<<"$out" \
  || fail "the Claude watcher did not fire on its OWN marker — the guard disarmed the completion signal: $out"

# --- the Codex watcher ---
xrepo="$tmp/x/repo"; xwt="$tmp/x/wt-guardslug"
build_repo "$xrepo" "$xwt" stream/guardslug
mkdir -p "$xrepo/skills/codex-controlled-build-run/scripts" \
         "$xrepo/skills/codex-controlled-build-run/references/cbr-core/scripts" \
         "$xrepo/.cbr-codex/runs/guardslug"
cp "$codex_watch" "$xrepo/skills/codex-controlled-build-run/scripts/captain-watch-codex.sh"
cp "$lib" "$xrepo/skills/codex-controlled-build-run/references/cbr-core/scripts/strand-lib.sh"
chmod +x "$xrepo/skills/codex-controlled-build-run/scripts/captain-watch-codex.sh"
printf '{"worktree":"%s"}\n' "$xwt" > "$xrepo/.cbr-codex/runs/guardslug/meta.json"
printf '{"reviewFailGraceSeconds":86400,"watchStallSeconds":86400}\n' > "$xrepo/.cbr-codex.json"
touch "$xrepo/.cbr-codex/runs/guardslug/events.jsonl"
# A live pid, so the watcher does not exit down the process-died path instead.
sleep 600 & sleeper=$!
echo "$sleeper" > "$xrepo/.cbr-codex/runs/guardslug/pid"

run_codex() { # run_codex <secs> <marker line written 2s in>
  rm -f "$xwt/DONE.marker"
  ( cd "$xrepo" && CBR_WATCH_POLL_SECONDS=1 PATH="$tmp/nobin:$PATH" \
      "$xrepo/skills/codex-controlled-build-run/scripts/captain-watch-codex.sh" guardslug ) \
      >"$tmp/x.out" 2>&1 &
  local pid=$!
  ( sleep 2; printf '%s\n' "$2" > "$xwt/DONE.marker" ) &
  local writer=$!
  ( sleep "$1"; kill "$pid" 2>/dev/null || true ) &
  local killer=$!
  wait "$pid" 2>/dev/null || true
  kill "$killer" "$writer" 2>/dev/null || true
  cat "$tmp/x.out"
}

out="$(run_codex 8 'stream/elsewhere — COMPLETE 2026-08-14')"
grep -q 'done-changed\|process-stopped-with-done' <<<"$out" \
  && fail "the Codex watcher latched on a marker naming stream/elsewhere while watching stream/guardslug: $out"
grep -q 'done-marker-foreign' <<<"$out" \
  || fail "the Codex watcher did not report that it saw a foreign marker and kept watching: $out"

out="$(run_codex 8 'stream/guardslug — COMPLETE 2026-08-19')"
grep -q 'done-changed' <<<"$out" \
  || fail "the Codex watcher did not fire on its OWN marker — the guard disarmed the completion signal: $out"

# ---------------------------------------------------------------------------
# A WATCHER WITH NO BRANCH TO COMPARE AGAINST MUST STILL LATCH
# ---------------------------------------------------------------------------
# The mirror image of the guard, and the more dangerous half: a worktree on a
# detached head has no branch name, so a watcher that treats "no branch" as "not
# mine" finds EVERY marker foreign and never fires again — silently, for the
# rest of the run. Proven for both leaves, because a fallback written into one
# leaf's private helper is exactly the law-in-one-harness this strand exists to
# stop.
cbr_marker_counts_as_done "$m" "" \
  || fail "with no branch to compare against, the predicate refused to latch — that disarms DONE for the whole run"

printf 'stream/mine — COMPLETE\n' > "$m"
( cbr_marker_counts_as_done "$m" "" >/dev/null 2>&1; echo alive > "$tmp/survived" ) || true
[ -f "$tmp/survived" ] \
  || fail "calling the predicate with an empty branch aborted the caller — a guard that kills the watcher is an outage, not a guard"

git -C "$cwt" checkout -q --detach
out="$(run_claude 8 'stream/guardslug — COMPLETE 2026-08-19')"
grep -q 'EVENT=DONE' <<<"$out" \
  || fail "on a detached head the Claude watcher never fired DONE — it read its own branch as the literal word HEAD, found every marker foreign, and disarmed itself: $out"
git -C "$cwt" checkout -q stream/guardslug

git -C "$xwt" checkout -q --detach
out="$(run_codex 8 'stream/guardslug — COMPLETE 2026-08-19')"
grep -q 'done-changed' <<<"$out" \
  || fail "on a detached head the Codex watcher never fired DONE: $out"
git -C "$xwt" checkout -q stream/guardslug

# ---------------------------------------------------------------------------
# WIRING
# ---------------------------------------------------------------------------
bash -n "$claude_watch" || fail "the Claude watcher does not parse"
bash -n "$codex_watch"  || fail "the Codex watcher does not parse"

for w in "$claude_watch" "$codex_watch"; do
  n="$(basename "$w")"
  grep -q 'strand-lib\.sh' "$w" || fail "$n never sources the shared strand library"
  # Both watchers DEFINE a fallback of that name, so a bare grep is satisfied by
  # the stub alone — an edit that deletes the call site would still pass.
  grep -qE 'cbr_marker_counts_as_done "' "$w" \
    || fail "$n never CALLS cbr_marker_counts_as_done with a marker — it can only be guarded by a private copy of the rule, which is how one leaf ships law the other does not"
done

# The Codex watcher treats a marker as proof of completion in two further places
# — a stopped process, and the watchdog's retirement — and a foreign marker is
# no more proof there than it is in the poll loop.
# One bare-existence test is legitimate and lives inside done_marker_is_ours, as
# the fallback for a worktree whose branch cannot be read. Anywhere ELSE it is a
# path that adopts an inherited marker as proof the builder finished.
stray="$(awk '
  /^done_marker_is_ours\(\)/ { infn = 1 }
  infn && /^}/               { infn = 0; next }
  !infn && /\[ -f "\$wt\/DONE\.marker" \]/ { print FNR": "$0 }
' "$codex_watch")"
[ -z "$stray" ] \
  && : || fail "the Codex watcher tests the marker by bare existence outside done_marker_is_ours — that path adopts an inherited marker as proof the builder finished: $stray"

echo "watch-marker-guard.test PASS (predicate, both watchers run against a sibling's marker and their own, both wired)"
