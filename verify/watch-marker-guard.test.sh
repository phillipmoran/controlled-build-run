#!/usr/bin/env bash
# Regression: a completion marker inherited from a DIFFERENT strand must not
# latch either captain watcher.
#
# The failure this pins was observed live. A strand's completion marker merges
# onto the base branch with its work and stays there. The next strand folds the
# base into its own branch and inherits a marker announcing that a build which
# finished days ago is complete. If the watcher reads that marker as its own,
# the builder is unwatched for the rest of its run and the human is told a
# build finished on the day it started.
#
# The guard is structural now: the marker is NAMED for its branch
# (DONE-<sanitized-branch>.marker, via cbr_done_marker_name), so a sibling's
# marker is a differently-named file the watcher never reads. What is left to
# prove at read time is durability — an uncommitted latch dies with the
# worktree and claims nothing to anyone outside it.
#
# Three halves:
#   PREDICATE — naming and the counts-as-done decision, including the cases
#   where it must NOT refuse to latch (own committed marker; detached head
#   falling back to the legacy bare name).
#   END TO END — each watcher actually run against a worktree carrying a
#   sibling's marker (must keep watching), its own uncommitted marker (must
#   refuse, and say why), and its own committed marker (must fire).
#   WIRING — neither watcher may derive the name or reach a DONE decision
#   without the shared library.
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

command -v cbr_done_marker_name >/dev/null \
  || fail "the shared library has no cbr_done_marker_name — the watchers have no single answer to 'what file is my completion'"
command -v cbr_marker_counts_as_done >/dev/null \
  || fail "the shared library has no cbr_marker_counts_as_done — the watchers have no single answer to 'is this marker a completion'"

# ---------------------------------------------------------------------------
# PREDICATE — naming
# ---------------------------------------------------------------------------
[ "$(cbr_done_marker_name stream/mine)" = "DONE-stream-mine.marker" ] \
  || fail "cbr_done_marker_name stream/mine gave '$(cbr_done_marker_name stream/mine)' — the name must be derived from the branch, or every strand shares one file and the inherited-marker false latch is back"
[ "$(cbr_done_marker_name '')" = "DONE.marker" ] \
  || fail "an empty branch (detached head) did not fall back to the legacy bare name — a watcher with no branch would watch a file nothing writes, disarming DONE for the whole run"
[ "$(cbr_done_marker_name stream/mine)" != "$(cbr_done_marker_name stream/sibling)" ] \
  || fail "two different branches mapped to the same marker name — the structural guard is gone"

# Branch names are far more permissive than the characters this project happens
# to use; whatever the branch, the derived name must be a single safe filename.
for odd in 'stream/sibling+fix' 'stream/user@host' 'feature/ünïcode' 'stream/a.b~c' \
           'stream/foo.lock' 'stream/@{x' 'stream//foo' 'stream/.hidden'; do
  n="$(cbr_done_marker_name "$odd")"
  case "$n" in
    DONE-*.marker) : ;;
    *) fail "cbr_done_marker_name '$odd' gave '$n' — not the DONE-<slug>.marker shape" ;;
  esac
  printf '%s' "$n" | LC_ALL=C grep -q '[^A-Za-z0-9._-]' \
    && fail "cbr_done_marker_name '$odd' gave '$n' — unsanitized bytes in a filename the watcher and provision reset both glob for"
done

# ---------------------------------------------------------------------------
# PREDICATE — counts-as-done (identity is the filename; durability the commit)
# ---------------------------------------------------------------------------
prepo="$tmp/p"; mkdir -p "$prepo"
git -C "$prepo" init -q -b stream/mine
pgit() { git -C "$prepo" -c user.email=t@t -c user.name=t "$@"; }
echo x > "$prepo/f"; pgit add -A >/dev/null; pgit commit -qm base

own="$prepo/$(cbr_done_marker_name stream/mine)"
sib="$prepo/$(cbr_done_marker_name stream/sibling)"

cbr_marker_counts_as_done "$own" stream/mine \
  && fail "an ABSENT marker counted as done"

printf 'stream/mine — COMPLETE 2026-08-31\n' > "$own"
cbr_marker_counts_as_done "$own" stream/mine \
  && fail "an UNCOMMITTED marker counted as done — a latch that dies with the worktree was read as a completion"
pgit add "$(basename "$own")" >/dev/null; pgit commit -qm latch >/dev/null
cbr_marker_counts_as_done "$own" stream/mine \
  || fail "the branch's own committed marker did not count as done — the guard broke the thing it protects"

# A sibling's marker: right shape, committed, wrong NAME for this branch.
printf 'stream/sibling — COMPLETE 2026-08-14\n' > "$sib"
pgit add "$(basename "$sib")" >/dev/null; pgit commit -qm sibling >/dev/null
cbr_marker_counts_as_done "$sib" stream/mine \
  && fail "a sibling strand's committed marker counted as done for stream/mine — this is the inherited-marker false latch itself"

# Detached head: no branch, legacy bare name, still latches once committed.
legacy="$prepo/DONE.marker"
printf 'COMPLETE — all phases green\n' > "$legacy"
pgit add DONE.marker >/dev/null; pgit commit -qm legacy >/dev/null
cbr_marker_counts_as_done "$legacy" "" \
  || fail "with no branch to compare against, the committed legacy marker did not count — that disarms DONE for every detached-head run"
( cbr_marker_counts_as_done "$legacy" "" >/dev/null 2>&1; echo alive > "$tmp/survived" ) || true
[ -f "$tmp/survived" ] \
  || fail "calling the predicate with an empty branch aborted the caller — a guard that kills the watcher is an outage, not a guard"

# ---------------------------------------------------------------------------
# END TO END — each watcher, actually running
# ---------------------------------------------------------------------------
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

own_name="DONE-stream-guardslug.marker"
sib_name="DONE-stream-elsewhere.marker"

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
run_claude() { # run_claude <secs> <marker name> <marker line> [commit|nocommit|gap] [note grep] [prearmed line]
  # gap: write the marker, let the watcher SEE it uncommitted, then commit —
  # the ordinary builder sequence with a poll landing inside it.
  # prearmed: leave a COMMITTED marker in place before the watcher arms, so the
  # case that follows is a rewrite of a tracked file rather than a first write.
  local mname="$2"
  rm -f "$cwt"/DONE*.marker
  git -C "$cwt" rm -q --cached "DONE*.marker" >/dev/null 2>&1 || true
  git -C "$cwt" -c user.email=t@t -c user.name=t commit -qm drop-marker >/dev/null 2>&1 || true
  if [ -n "${6:-}" ]; then
    printf '%s\n' "$6" > "$cwt/$mname"
    git -C "$cwt" -c user.email=t@t -c user.name=t add "$mname" >/dev/null 2>&1
    git -C "$cwt" -c user.email=t@t -c user.name=t commit -qm prearmed >/dev/null 2>&1
  fi
  rm -f "$tmp/c.gap"
  : > "$tmp/c.out"
  CBR_WATCH_POLL_SECONDS=1 PATH="$tmp/nobin:$PATH" \
    "$crepo/skills/claude-controlled-build-run/scripts/captain-watch.sh" guardslug \
      --stall-secs 86400 --fail-grace-secs 86400 >"$tmp/c.out" 2>&1 &
  local pid=$!
  ( n=0
    until grep -q '^armed: ' "$tmp/c.out" 2>/dev/null || [ "$n" -ge 300 ]; do
      sleep 0.2; n=$((n+1))
    done
    printf '%s\n' "$3" > "$cwt/$mname"
    if [ "${4:-commit}" = gap ]; then
      # Waited on, not slept through: what has to happen before the commit is a
      # POLL, and the verdict on it is RECORDED — a writer that times out and
      # commits anyway turns the case into one the race was never run in.
      n=0
      until grep -q 'not a committed latch' "$tmp/c.out" 2>/dev/null || [ "$n" -ge 300 ]; do
        sleep 0.2; n=$((n+1))
      done
      if grep -q 'not a committed latch' "$tmp/c.out" 2>/dev/null
        then printf 'seen\n' > "$tmp/c.gap"
        else printf 'unseen\n' > "$tmp/c.gap"
      fi
    fi
    if [ "${4:-commit}" != nocommit ]; then
      git -C "$cwt" -c user.email=t@t -c user.name=t add "$mname" >/dev/null 2>&1
      git -C "$cwt" -c user.email=t@t -c user.name=t commit -qm done >/dev/null 2>&1
    fi ) >/dev/null 2>&1 &
  local writer=$!
  # A ceiling, not a schedule: the watcher exits on its own when it latches;
  # where it deliberately does not, the note (or the bound) ends the case.
  ( n=0; bound=$(( $1 * ${CBR_TEST_CEILING_SCALE:-6} * 5 ))
    while [ "$n" -lt "$bound" ]; do
      if [ -n "${5:-}" ] && grep -q "$5" "$tmp/c.out" 2>/dev/null; then break; fi
      sleep 0.2; n=$((n+1))
    done
    kill "$pid" 2>/dev/null || true ) >/dev/null 2>&1 &
  local killer=$!
  wait "$pid" 2>/dev/null || true
  kill "$killer" "$writer" 2>/dev/null || true
  cat "$tmp/c.out"
}
mkdir -p "$tmp/nobin"   # keeps roborev out of the fixture's PATH

# A sibling's marker, committed and all: a different FILE. The watcher must
# still be watching when the bound ends. Absence of the event over a real
# observation window is the property — there is no note, because nothing the
# watcher reads ever changed.
out="$(run_claude 3 "$sib_name" 'stream/elsewhere — COMPLETE 2026-08-14')"
grep -q 'EVENT=DONE' <<<"$out" \
  && fail "the Claude watcher latched on $sib_name while watching stream/guardslug — the builder is now unwatched and the human has been told it finished: $out"
grep -q "done-marker" <<<"$out" || true

# The armed line must name the file actually being watched — the operator
# reads it to know what to commit.
grep -q '^armed: .*guardslug' <<<"$out" \
  || fail "fixture broken: the watcher never armed: $out"

out="$(run_claude 8 "$own_name" 'stream/guardslug — COMPLETE 2026-08-31')"
grep -q 'EVENT=DONE' <<<"$out" \
  || fail "the Claude watcher did not fire on its OWN committed marker $own_name — the per-branch rename disarmed the completion signal: $out"

# The legacy name is nobody's name on a branch: a builder still writing bare
# DONE.marker after the rename must NOT latch this watcher, or the rename
# guards nothing on the very worktrees it was built for.
out="$(run_claude 3 DONE.marker 'stream/guardslug — COMPLETE 2026-08-31')"
grep -q 'EVENT=DONE' <<<"$out" \
  && fail "the Claude watcher latched on bare DONE.marker while its branch has a per-branch name — any inherited legacy marker false-latches again: $out"

# The builder that writes its latch and dies before committing it.
out="$(run_claude 8 "$own_name" 'stream/guardslug — COMPLETE 2026-08-31' nocommit 'not a committed latch')"
grep -q 'EVENT=DONE' <<<"$out" \
  && fail "the Claude watcher reported DONE on an uncommitted marker — a builder that crashed before committing its latch is now recorded as finished: $out"
grep -q 'not a committed latch' <<<"$out" \
  || fail "the Claude watcher did not say WHY it kept watching past an uncommitted marker — silence reads the same as having given up: $out"

# Write-then-commit with a poll landing in the gap. The commit does not change
# the FILE, so a watcher that re-baselined on the uncommitted read has made
# itself permanently deaf to this completion.
out="$(run_claude 8 "$own_name" 'stream/guardslug — COMPLETE 2026-08-31' gap)"
[ "$(cat "$tmp/c.gap" 2>/dev/null)" = seen ] \
  || fail "the fixture committed without the watcher ever reporting the marker uncommitted — the write-poll-commit race was not run, so a pass here proves nothing: $out"
grep -q 'EVENT=DONE' <<<"$out" \
  || fail "the Claude watcher never latched a marker it saw uncommitted and then saw committed — the completion it was armed for can no longer reach it: $out"
[ "$(grep -c 'not a committed latch' <<<"$out")" -eq 1 ] \
  || fail "the Claude watcher did not report the uncommitted marker exactly once — either it went silent or it paged the reader on every poll for one unchanged fact: $out"

# The same race over a marker that is ALREADY tracked — the fix round.
out="$(run_claude 8 "$own_name" 'stream/guardslug — COMPLETE round two' gap '' 'stream/guardslug — COMPLETE 2026-08-31')"
[ "$(cat "$tmp/c.gap" 2>/dev/null)" = seen ] \
  || fail "the Claude watcher never called the REWRITE of a tracked marker uncommitted — a fix round's undurable latch is being read as a completion: $out"
grep -q 'EVENT=DONE.*round two' <<<"$out" \
  || fail "the Claude watcher did not latch the rewritten marker once it was committed: $out"

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
sleep 600 >/dev/null 2>&1 & sleeper=$!
echo "$sleeper" > "$xrepo/.cbr-codex/runs/guardslug/pid"

run_codex() { # run_codex <secs> <marker name> <marker line> [commit|nocommit|gap] [note grep] [prearmed line]
  local mname="$2"
  rm -f "$xwt"/DONE*.marker
  git -C "$xwt" rm -q --cached "DONE*.marker" >/dev/null 2>&1 || true
  git -C "$xwt" -c user.email=t@t -c user.name=t commit -qm drop-marker >/dev/null 2>&1 || true
  # This run's arm, not the last one's: the state file is what says the watcher
  # has taken its baseline.
  rm -f "$xrepo/.cbr-codex/watch/guardslug.state"
  : > "$tmp/x.out"
  if [ -n "${6:-}" ]; then
    printf '%s\n' "$6" > "$xwt/$mname"
    git -C "$xwt" -c user.email=t@t -c user.name=t add "$mname" >/dev/null 2>&1
    git -C "$xwt" -c user.email=t@t -c user.name=t commit -qm prearmed >/dev/null 2>&1
  fi
  rm -f "$tmp/x.gap"
  # exec, so the pid below is the WATCHER, not a wrapper subshell — killing a
  # wrapper leaves the watcher alive and writing into the next case's output.
  ( cd "$xrepo" && exec env CBR_WATCH_POLL_SECONDS=1 PATH="$tmp/nobin:$PATH" \
      "$xrepo/skills/codex-controlled-build-run/scripts/captain-watch-codex.sh" guardslug ) \
      >"$tmp/x.out" 2>&1 &
  local pid=$!
  ( n=0
    until [ -f "$xrepo/.cbr-codex/watch/guardslug.state" ] || [ "$n" -ge 300 ]; do
      sleep 0.2; n=$((n+1))
    done
    printf '%s\n' "$3" > "$xwt/$mname"
    if [ "${4:-commit}" = gap ]; then
      n=0
      until grep -q 'done-marker-uncommitted' "$tmp/x.out" 2>/dev/null || [ "$n" -ge 300 ]; do
        sleep 0.2; n=$((n+1))
      done
      if grep -q 'done-marker-uncommitted' "$tmp/x.out" 2>/dev/null
        then printf 'seen\n' > "$tmp/x.gap"
        else printf 'unseen\n' > "$tmp/x.gap"
      fi
    fi
    if [ "${4:-commit}" != nocommit ]; then
      git -C "$xwt" -c user.email=t@t -c user.name=t add "$mname" >/dev/null 2>&1
      git -C "$xwt" -c user.email=t@t -c user.name=t commit -qm done >/dev/null 2>&1
    fi ) >/dev/null 2>&1 &
  local writer=$!
  ( n=0; bound=$(( $1 * ${CBR_TEST_CEILING_SCALE:-6} * 5 ))
    while [ "$n" -lt "$bound" ]; do
      if [ -n "${5:-}" ] && grep -q "$5" "$tmp/x.out" 2>/dev/null; then break; fi
      sleep 0.2; n=$((n+1))
    done
    kill "$pid" 2>/dev/null || true ) >/dev/null 2>&1 &
  local killer=$!
  wait "$pid" 2>/dev/null || true
  kill "$killer" "$writer" 2>/dev/null || true
  cat "$tmp/x.out"
}

out="$(run_codex 3 "$sib_name" 'stream/elsewhere — COMPLETE 2026-08-14')"
grep -q 'done-changed\|process-stopped-with-done' <<<"$out" \
  && fail "the Codex watcher latched on $sib_name while watching stream/guardslug: $out"

out="$(run_codex 8 "$own_name" 'stream/guardslug — COMPLETE 2026-08-31')"
grep -q 'done-changed' <<<"$out" \
  || fail "the Codex watcher did not fire on its OWN committed marker $own_name: $out"

out="$(run_codex 3 DONE.marker 'stream/guardslug — COMPLETE 2026-08-31')"
grep -q 'done-changed' <<<"$out" \
  && fail "the Codex watcher latched on bare DONE.marker while its branch has a per-branch name: $out"

out="$(run_codex 8 "$own_name" 'stream/guardslug — COMPLETE 2026-08-31' nocommit 'done-marker-uncommitted')"
grep -q 'done-changed' <<<"$out" \
  && fail "the Codex watcher reported done on an uncommitted marker: $out"
grep -q 'done-marker-uncommitted' <<<"$out" \
  || fail "the Codex watcher did not report that the marker it saw was uncommitted: $out"

out="$(run_codex 8 "$own_name" 'stream/guardslug — COMPLETE 2026-08-31' gap)"
[ "$(cat "$tmp/x.gap" 2>/dev/null)" = seen ] \
  || fail "the fixture committed without the Codex watcher ever reporting the marker uncommitted — the race was not run: $out"
grep -q 'done-changed' <<<"$out" \
  || fail "the Codex watcher never latched a marker it saw uncommitted and then saw committed: $out"
[ "$(grep -c 'done-marker-uncommitted' <<<"$out")" -eq 1 ] \
  || fail "the Codex watcher did not report the uncommitted marker exactly once: $out"

out="$(run_codex 8 "$own_name" 'stream/guardslug — COMPLETE round two' gap '' 'stream/guardslug — COMPLETE 2026-08-31')"
[ "$(cat "$tmp/x.gap" 2>/dev/null)" = seen ] \
  || fail "the Codex watcher never called the REWRITE of a tracked marker uncommitted — a fix round's undurable latch is being read as a completion: $out"
grep -q 'done-changed' <<<"$out" \
  || fail "the Codex watcher did not latch the rewritten marker once it was committed: $out"

# ---------------------------------------------------------------------------
# RETIRED OPTIONS FAIL LOUDLY — never arm an ordinary watcher in disguise
# ---------------------------------------------------------------------------
# Automation still passing --watchdog (retired 2026-08-31) must get a hard
# refusal BEFORE any watcher state or heartbeat exists: a silent duplicate
# watcher keeps the heartbeat fresh after the real one exits, so the strand
# reads as watched when nobody is watching.
rm -f "$xrepo/.cbr-codex/watch/guardslug.state" "$xrepo/.cbr-codex/watch/guardslug.heartbeat"
rc=0
out="$( cd "$xrepo" && "$xrepo/skills/codex-controlled-build-run/scripts/captain-watch-codex.sh" guardslug --watchdog 2>&1 )" || rc=$?
[ "$rc" -eq 2 ] \
  || fail "the Codex watcher accepted the retired --watchdog argument (rc=$rc) — a silent duplicate watcher is armed where a refusal was owed: $out"
[ -f "$xrepo/.cbr-codex/watch/guardslug.state" ] || [ -f "$xrepo/.cbr-codex/watch/guardslug.heartbeat" ] \
  && fail "the retired-argument refusal still left watcher state behind — the refusal came after arming, not before"

# ---------------------------------------------------------------------------
# A WATCHER WITH NO BRANCH MUST STILL LATCH — on the legacy bare name
# ---------------------------------------------------------------------------
# A worktree on a detached head has no branch name, so the derived name falls
# back to bare DONE.marker. A watcher that instead derived a name from the
# literal word HEAD would watch a file nothing writes and go silently deaf.
git -C "$cwt" checkout -q --detach
out="$(run_claude 8 DONE.marker 'COMPLETE — detached')"
grep -q 'EVENT=DONE' <<<"$out" \
  || fail "on a detached head the Claude watcher never fired DONE on the legacy bare marker — it derived a name from the literal word HEAD and disarmed itself: $out"
git -C "$cwt" checkout -q stream/guardslug

git -C "$xwt" checkout -q --detach
out="$(run_codex 8 DONE.marker 'COMPLETE — detached')"
grep -q 'done-changed' <<<"$out" \
  || fail "on a detached head the Codex watcher never fired DONE on the legacy bare marker: $out"
git -C "$xwt" checkout -q stream/guardslug

# ---------------------------------------------------------------------------
# LAUNCH GATE — a prompt that never names the exact marker must not dispatch
# ---------------------------------------------------------------------------
# The launch commands print the marker contract, but printing after dispatch
# is advice to nobody: the builder is already running the uncorrectable
# prompt. Both leaves must refuse BEFORE dispatch, naming the exact filename.
claude_cbr="$root/skills/claude-controlled-build-run/scripts/cbr.sh"
codex_cbr="$root/skills/codex-controlled-build-run/scripts/cbr-codex.sh"
[ -f "$claude_cbr" ] || claude_cbr="$kit/skill/claude-controlled-build-run/scripts/cbr.sh"
[ -f "$codex_cbr" ]  || codex_cbr="$kit/skill/codex-controlled-build-run/scripts/cbr-codex.sh"

printf 'Build the thing. When done, stop.\n' > "$tmp/prompt-bare.md"
printf 'Build the thing. Final commit: COMMIT %s.\n' "$own_name" > "$tmp/prompt-named.md"

# Claude leaf: worktree_path = ../cockpit-<slug> beside the repo — the crepo
# fixture already has that shape. PATH is stripped to the system dirs so the
# named-prompt run, having PASSED the gate, dies at its own 'claude not found'
# preflight instead of dispatching a real background session from a test.
rc=0; out="$( cd "$crepo" && env PATH=/usr/bin:/bin "$claude_cbr" launch guardslug --prompt-file "$tmp/prompt-bare.md" 2>&1 )" || rc=$?
[ "$rc" -ne 0 ] || fail "Claude launch accepted a dispatch prompt that never names the done marker: $out"
grep -qF "$own_name" <<<"$out" \
  || fail "the Claude launch refusal never names the exact expected marker ($own_name) — the operator is left to guess the sanitization the gate just enforced: $out"
rc=0; out="$( cd "$crepo" && env PATH=/usr/bin:/bin "$claude_cbr" launch guardslug --prompt-file "$tmp/prompt-named.md" 2>&1 )" || rc=$?
grep -q 'claude not found' <<<"$out" \
  || fail "with the exact marker in the prompt the Claude gate still refused (or died elsewhere than the expected claude-not-found preflight) — the contract check rejects compliant prompts: $out"

# Codex leaf: point worktree resolution at the existing xwt fixture; the
# named-prompt run must clear the gate and die at the LATER provision check.
printf '{"reviewFailGraceSeconds":86400,"watchStallSeconds":86400,"worktreePrefix":"wt-"}\n' > "$xrepo/.cbr-codex.json"
rc=0; out="$( cd "$xrepo" && env PATH="$tmp/nobin:$PATH" "$codex_cbr" launch guardslug --prompt-file "$tmp/prompt-bare.md" 2>&1 )" || rc=$?
[ "$rc" -ne 0 ] || fail "Codex launch accepted a dispatch prompt that never names the done marker: $out"
grep -qF "$own_name" <<<"$out" \
  || fail "the Codex launch refusal never names the exact expected marker ($own_name): $out"
rc=0; out="$( cd "$xrepo" && env PATH="$tmp/nobin:$PATH" "$codex_cbr" launch guardslug --prompt-file "$tmp/prompt-named.md" 2>&1 )" || rc=$?
grep -q 'provision PASS not recorded' <<<"$out" \
  || fail "with the exact marker in the prompt the Codex gate still refused (or died elsewhere than the expected provision check) — the contract check rejects compliant prompts: $out"
printf '{"reviewFailGraceSeconds":86400,"watchStallSeconds":86400}\n' > "$xrepo/.cbr-codex.json"

# ---------------------------------------------------------------------------
# WIRING
# ---------------------------------------------------------------------------
bash -n "$claude_watch" || fail "the Claude watcher does not parse"
bash -n "$codex_watch"  || fail "the Codex watcher does not parse"

for w in "$claude_watch" "$codex_watch"; do
  n="$(basename "$w")"
  grep -q 'strand-lib\.sh' "$w" || fail "$n never sources the shared strand library"
  # Both watchers DEFINE fallbacks of these names, so a bare grep is satisfied
  # by the stub alone — the CALL sites are what an edit could delete.
  grep -qE 'cbr_done_marker_name "' "$w" \
    || fail "$n never derives its marker name from cbr_done_marker_name — a private naming rule is how one leaf ships law the other does not"
  grep -qE 'cbr_marker_counts_as_done "' "$w" \
    || fail "$n never CALLS cbr_marker_counts_as_done with a marker — it can only be guarded by a private copy of the rule"
  # A literal fixed marker path anywhere in a decision would sidestep the
  # derived name. The only allowed literal is the fallback stub's echo.
  stray="$(grep -n '\$wt/DONE\.marker' "$w" || true)"
  [ -z "$stray" ] \
    || fail "$n still reads a fixed \$wt/DONE.marker path — that sidesteps the per-branch name: $stray"
done

echo "watch-marker-guard.test PASS (per-branch naming, both watchers run against a sibling's marker, an uncommitted latch, and their own, both wired)"
