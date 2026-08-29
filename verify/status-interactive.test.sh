#!/usr/bin/env bash
# Regression: `status` must not call a strand DEAD because it cannot find a
# BACKGROUND session for it.
#
# Observed live on 2026-08-19: a strand being driven by an interactive desktop
# session reported `verdict=died`. It was not dead, it was simply not in the
# background-session registry — the only place either leaf's status looked. The
# consequences of believing it are all destructive: a dispatcher relaunches a
# second builder onto the same worktree, or reaps a worktree with live work in
# it, on the strength of a verdict that was never about liveness at all.
#
# Ground truth for "somebody is working here" is a live process rooted in the
# folder. Both leaves must consult it before pronouncing death, and both must
# say WHICH fact they found — a session they know about, or a process they do
# not.
set -euo pipefail

for v in $(env | sed -n 's/^\(GIT_[A-Z_]*\)=.*/\1/p'); do unset "$v"; done

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
kit="$(cd "$here/.." && pwd)"

lib="$root/skills/cbr-core/scripts/strand-lib.sh"
claude_leaf="$root/skills/claude-controlled-build-run/scripts/cbr.sh"
codex_leaf="$root/skills/codex-controlled-build-run/scripts/cbr-codex.sh"
[ -f "$lib" ]         || lib="$kit/skill/claude-controlled-build-run/references/core/scripts/strand-lib.sh"
[ -f "$claude_leaf" ] || claude_leaf="$kit/skill/claude-controlled-build-run/scripts/cbr.sh"
[ -f "$codex_leaf" ]  || codex_leaf="$kit/skill/codex-controlled-build-run/scripts/cbr-codex.sh"

tmp="$(cd "$(mktemp -d)" && pwd -P)"
sleeper=""
cleanup() {
  local rc=$?
  [ -n "$sleeper" ] && { kill "$sleeper" 2>/dev/null || true; wait "$sleeper" 2>/dev/null || true; }
  rm -rf "$tmp"
  exit "$rc"
}
trap cleanup EXIT
fail() { echo "status-interactive.test FAIL: $1" >&2; exit 1; }

for f in "$lib" "$claude_leaf" "$codex_leaf"; do [ -f "$f" ] || fail "missing input: $f"; done

# A stand-in for the background-session registry that knows about nothing, which
# is exactly the situation an interactive session produces.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/claude" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = "agents" ] && { echo '[]'; exit 0; }
exit 0
SH
chmod +x "$tmp/bin/claude"

# ---------------------------------------------------------------------------
# The Claude leaf
# ---------------------------------------------------------------------------
crepo="$tmp/c/repo"; cwt="$tmp/c/cockpit-livecheck"
mkdir -p "$crepo/skills/claude-controlled-build-run/scripts" \
         "$crepo/skills/claude-controlled-build-run/references/core/scripts" "$cwt"
cp "$claude_leaf" "$crepo/skills/claude-controlled-build-run/scripts/cbr.sh"
cp "$lib" "$crepo/skills/claude-controlled-build-run/references/core/scripts/strand-lib.sh"
chmod +x "$crepo/skills/claude-controlled-build-run/scripts/cbr.sh"
git -C "$crepo" init -q -b main
echo x > "$crepo/f"; git -C "$crepo" -c user.email=t@t -c user.name=t add -A
git -C "$crepo" -c user.email=t@t -c user.name=t commit -qm base
git -C "$cwt" init -q -b cbr/livecheck
printf '## Readback\n\nmission\nscope\nOUT\n' > "$cwt/progress.md"
echo y > "$cwt/f"; git -C "$cwt" -c user.email=t@t -c user.name=t add -A
git -C "$cwt" -c user.email=t@t -c user.name=t commit -qm work

claude_status() {
  set +e
  ( cd "$crepo" && PATH="$tmp/bin:$PATH" \
      "$crepo/skills/claude-controlled-build-run/scripts/cbr.sh" status livecheck ) \
    >"$tmp/c.out" 2>&1
  echo $? > "$tmp/c.rc"
  set -e
  cat "$tmp/c.out"
}

# No session in the registry AND nothing running in the folder: nobody is there.
out="$(claude_status)"
grep -q 'verdict=died' <<<"$out" \
  || fail "with no session and no process, status stopped reporting a dead builder: $out"

# Now something IS rooted in the worktree. The registry still knows nothing, and
# that combination is the live-interactive-session case.
( cd "$cwt" && exec sleep 600 ) & sleeper=$!
sleep 1
out="$(claude_status)"
grep -q 'verdict=died' <<<"$out" \
  && fail "a strand with a live process rooted in its worktree was reported DEAD — this is the false verdict that gets a second builder launched onto live work: $out"
grep -qi 'interactive' <<<"$out" \
  || fail "status did not name the fact it found (a live process, no registered session) — 'not dead' is only useful if the reader learns why: $out"
[ "$(cat "$tmp/c.rc")" = "0" ] \
  || fail "status exited non-zero for a strand that is demonstrably being worked on"

kill "$sleeper" 2>/dev/null || true; wait "$sleeper" 2>/dev/null || true; sleeper=""

# ---------------------------------------------------------------------------
# The Codex leaf — same blind spot, same fix, or the law lives in one harness
# ---------------------------------------------------------------------------
xrepo="$tmp/x/repo"; xwt="$tmp/x/wt-livecheck"
mkdir -p "$tmp/x"
mkdir -p "$xrepo/skills/codex-controlled-build-run/scripts" \
         "$xrepo/skills/codex-controlled-build-run/references/cbr-core/scripts" \
         "$xrepo/.cbr-codex/runs/livecheck" "$xwt"
cp "$codex_leaf" "$xrepo/skills/codex-controlled-build-run/scripts/cbr-codex.sh"
cp "$lib" "$xrepo/skills/codex-controlled-build-run/references/cbr-core/scripts/strand-lib.sh"
chmod +x "$xrepo/skills/codex-controlled-build-run/scripts/cbr-codex.sh"
git -C "$xrepo" init -q -b main
echo x > "$xrepo/f"; git -C "$xrepo" -c user.email=t@t -c user.name=t add -A
git -C "$xrepo" -c user.email=t@t -c user.name=t commit -qm base
git -C "$xwt" init -q -b cbr/livecheck
echo y > "$xwt/f"; git -C "$xwt" -c user.email=t@t -c user.name=t add -A
git -C "$xwt" -c user.email=t@t -c user.name=t commit -qm work
printf '{"worktree":"%s"}\n' "$xwt" > "$xrepo/.cbr-codex/runs/livecheck/meta.json"
printf '{"worktreeParent":"..","worktreePrefix":"wt-"}\n' > "$xrepo/.cbr-codex.json"
touch "$xrepo/.cbr-codex/runs/livecheck/events.jsonl"
# A pid that is definitely not running: the registered session is gone.
echo 999999 > "$xrepo/.cbr-codex/runs/livecheck/pid"

codex_status() {
  set +e
  ( cd "$xrepo" && PATH="$tmp/bin:$PATH" \
      "$xrepo/skills/codex-controlled-build-run/scripts/cbr-codex.sh" status livecheck ) \
    >"$tmp/x.out" 2>&1
  echo $? > "$tmp/x.rc"
  set -e
  cat "$tmp/x.out"
}

out="$(codex_status)"
[ "$(cat "$tmp/x.rc")" = "0" ] \
  && fail "with a dead pid, no marker and nothing running, the Codex leaf stopped reporting a hard-dead fact: $out"

( cd "$xwt" && exec sleep 600 ) & sleeper=$!
sleep 1
out="$(codex_status)"
grep -qi 'interactive' <<<"$out" \
  || fail "the Codex leaf did not report the live process rooted in the worktree — the same blind spot, unfixed in the second leaf, is law living in one harness: $out"
[ "$(cat "$tmp/x.rc")" = "0" ] \
  || fail "the Codex leaf still exits hard-dead for a strand with a live process rooted in its worktree: $out"

kill "$sleeper" 2>/dev/null || true; wait "$sleeper" 2>/dev/null || true; sleeper=""

# ---------------------------------------------------------------------------
# "COULD NOT LOOK" IS NOT "NOBODY IS THERE"
# ---------------------------------------------------------------------------
# The merge-ownership rule turns a death verdict into permission to take a
# strand over (build-loop.md step 9), which makes a wrong death expensive in a
# new way. A machine that cannot inspect its process table must therefore say so
# rather than answer the question as "idle" — the direction that authorises a
# reap.
mkdir -p "$tmp/nolsof"
cat > "$tmp/nolsof/claude" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = "agents" ] && { echo '[]'; exit 0; }
exit 0
SH
chmod +x "$tmp/nolsof/claude"
# A PATH holding only what the leaves genuinely need, minus lsof.
for c in bash sh env git python3 awk sed grep head tail cat mktemp dirname basename find sort wc tr date stat rm mkdir cp mv ln chmod ls printf uname id; do
  p="$(command -v "$c" 2>/dev/null)" && ln -sf "$p" "$tmp/nolsof/$c"
done

out="$( set +e; ( cd "$crepo" && PATH="$tmp/nolsof" \
  "$crepo/skills/claude-controlled-build-run/scripts/cbr.sh" status livecheck ) 2>&1; set -e )"
grep -q 'verdict=died' <<<"$out" \
  && fail "with no way to inspect processes, the Claude leaf still pronounced the builder DEAD — an unanswerable liveness question answered as death is exactly what licenses a takeover: $out"
grep -q 'live_process=unknown' <<<"$out" \
  || fail "the Claude leaf did not report that liveness was UNPROVEN: $out"

out="$( set +e; ( cd "$xrepo" && PATH="$tmp/nolsof" \
  "$xrepo/skills/codex-controlled-build-run/scripts/cbr-codex.sh" status livecheck ) 2>&1; set -e )"
grep -q 'live_process=unknown' <<<"$out" \
  || fail "the Codex leaf reported a liveness answer it could not have obtained: $out"

# An UNPROVABLE occupancy answer is a hard fact only when nothing else answers
# the question. A strand whose registered session is demonstrably RUNNING is
# alive whatever the process table says, and failing status for it would page an
# orchestrator on every poll, forever, on any host without a usable lsof — while
# the other leaf returns 0 for the same situation. One law, two answers.
# A review daemon that answers, so the ONLY unanswerable fact in this run is
# occupancy — otherwise an unreadable review list would supply the hard fact and
# the assertion would prove nothing about the one under test.
printf '#!/usr/bin/env bash\necho "[]"\n' > "$tmp/nolsof/roborev"; chmod +x "$tmp/nolsof/roborev"
( exec sleep 600 ) >/dev/null 2>&1 & sleeper=$!
echo "$sleeper" > "$xrepo/.cbr-codex/runs/livecheck/pid"
set +e
( cd "$xrepo" && PATH="$tmp/nolsof" \
    "$xrepo/skills/codex-controlled-build-run/scripts/cbr-codex.sh" status livecheck ) >"$tmp/xa.out" 2>&1
xarc=$?
set -e
kill "$sleeper" 2>/dev/null || true; wait "$sleeper" 2>/dev/null || true; sleeper=""
echo 999999 > "$xrepo/.cbr-codex/runs/livecheck/pid"
[ "$xarc" -eq 0 ] \
  || fail "the Codex leaf reported a hard-dead fact for a strand whose registered session is RUNNING, because it could not inspect the process table — every poll on such a host is now a false page: $(cat "$tmp/xa.out")"

# ---------------------------------------------------------------------------
# A DEAD SESSION IS NOT AN IDLE FOLDER
# ---------------------------------------------------------------------------
# The observed shape: a background builder crashes, a human picks the worktree up
# interactively and carries on. The takeover rule wants BOTH facts, so every path
# that reaches a death verdict must ask the occupancy question — not only the
# path where no session was ever registered.
for st in failed stopped; do
  cat > "$tmp/bin/claude" <<SH
#!/usr/bin/env bash
[ "\${1:-}" = "agents" ] && { printf '[{"kind":"background","sessionId":"deadbeef01","state":"$st","cwd":"%s"}]\n' "$(cd "$cwt" && pwd -P)"; exit 0; }
exit 0
SH
  chmod +x "$tmp/bin/claude"

  out="$(claude_status)"
  grep -q 'verdict=died' <<<"$out" \
    || fail "with session state=$st, no marker and nothing in the folder, status should still report a dead builder: $out"

  ( cd "$cwt" && exec sleep 600 ) & sleeper=$!
  sleep 1
  out="$(claude_status)"
  kill "$sleeper" 2>/dev/null || true; wait "$sleeper" 2>/dev/null || true; sleeper=""
  grep -q 'verdict=died' <<<"$out" \
    && fail "session state=$st plus a LIVE process in the worktree was called dead — the registered session died and somebody picked the strand up; this licenses a takeover of live work: $out"
  grep -q 'live_process=yes' <<<"$out" \
    || fail "the state=$st path did not report the occupancy fact the takeover rule requires: $out"
done

# Restore the knows-nothing registry for anything that follows.
cat > "$tmp/bin/claude" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = "agents" ] && { echo '[]'; exit 0; }
exit 0
SH
chmod +x "$tmp/bin/claude"

# ---------------------------------------------------------------------------
# LAUNCH REFUSES AN OCCUPIED WORKTREE, AND REFUSES AN UNPROVEN ONE
# ---------------------------------------------------------------------------
# The other half of the harm: a second writer dispatched into a worktree somebody
# is already working in races on the git index. One writer per worktree, and a
# rule that evaporates when lsof is missing is not a rule.
printf 'prompt\n' > "$tmp/prompt.md"

( cd "$cwt" && exec sleep 600 ) & sleeper=$!
sleep 1
out="$( set +e; ( cd "$crepo" && PATH="$tmp/bin:$PATH" \
  "$crepo/skills/claude-controlled-build-run/scripts/cbr.sh" launch livecheck \
    --prompt-file "$tmp/prompt.md" --model m --effort medium ) 2>&1; set -e )"
grep -qi 'refusing to dispatch a second writer' <<<"$out" \
  || fail "the Claude leaf dispatched into a worktree with a live process rooted in it: $out"
kill "$sleeper" 2>/dev/null || true; wait "$sleeper" 2>/dev/null || true; sleeper=""

out="$( set +e; ( cd "$crepo" && PATH="$tmp/nolsof" \
  "$crepo/skills/claude-controlled-build-run/scripts/cbr.sh" launch livecheck \
    --prompt-file "$tmp/prompt.md" --model m --effort medium ) 2>&1; set -e )"
grep -qi 'could not be inspected' <<<"$out" \
  || fail "with no way to inspect processes the Claude leaf did not refuse to dispatch — a one-writer rule that evaporates with a missing tool is not a rule: $out"

# The Codex leaf gets a real launch attempt, not a grep. A grep is satisfied by a
# leaf that consults the predicate and ignores the answer, or that asks after it
# has already dispatched. Reaching the occupancy check needs a fixture that
# survives every earlier gate: a provisioned worktree, a vetted hook hash, a
# builder model, and no registry of its own.
xdwt="$tmp/x/wt-dispatch"
mkdir -p "$xdwt/.cbr-codex"
git -C "$xdwt" init -q -b cbr/dispatch
echo y > "$xdwt/f"; git -C "$xdwt" -c user.email=t@t -c user.name=t add -A
git -C "$xdwt" -c user.email=t@t -c user.name=t commit -qm work
printf '{"result":"PASS"}\n' > "$xdwt/.cbr-codex/provision.json"
printf '{"worktreeParent":"..","worktreePrefix":"wt-","models":{"builder":"m"}}\n' > "$xrepo/.cbr-codex.json"
# The fixture has no .codex hooks at all, so the vetted hash is the hash of
# nothing — computed, not transcribed, so it tracks the leaf's own definition.
python3 -c 'import hashlib; print(hashlib.sha256().hexdigest())' > "$xrepo/.cbr-codex/hook-trust.sha256"
xdrun="$xrepo/.cbr-codex/runs/dispatch"

# Nothing in this fixture may reach a real builder binary: the override case
# below is SUPPOSED to get past the guard, and what lies past the guard is a
# dispatch. A stub in front of the search path keeps the launch honest and inert.
for d in "$tmp/bin" "$tmp/nolsof"; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/codex"; chmod +x "$d/codex"
done

codex_launch() {
  set +e
  ( cd "$xrepo" && PATH="$1" env "${2:-IGNORE=1}" \
      "$xrepo/skills/codex-controlled-build-run/scripts/cbr-codex.sh" launch dispatch \
        --prompt-file "$tmp/prompt.md" --model m ) >"$tmp/xl.out" 2>&1
  echo $? > "$tmp/xl.rc"
  set -e
  cat "$tmp/xl.out"
}

for c in bash sh env git python3 awk sed grep head tail cat mktemp dirname basename find sort wc tr date stat rm mkdir cp mv ln chmod ls printf uname id lsof nohup kill; do
  p="$(command -v "$c" 2>/dev/null)" && ln -sf "$p" "$tmp/bin/$c"
done

( cd "$xdwt" && exec sleep 600 ) & sleeper=$!
sleep 1
out="$(codex_launch "$tmp/bin")"
kill "$sleeper" 2>/dev/null || true; wait "$sleeper" 2>/dev/null || true; sleeper=""
[ "$(cat "$tmp/xl.rc")" = "0" ] \
  && fail "the Codex leaf dispatched into a worktree with a live process rooted in it: $out"
grep -qi 'refusing to dispatch a second writer into an occupied worktree' <<<"$out" \
  || fail "the Codex leaf stopped, but not for the occupancy reason — a refusal that is really some earlier gate firing proves nothing about the one-writer rule: $out"
[ -e "$xdrun" ] \
  && fail "the Codex leaf refused the dispatch but still created the run registry $xdrun — a half-launched strand the next command has to reconcile"

# Same launch, same fixture, no way to inspect the process table.
out="$(codex_launch "$tmp/nolsof")"
[ "$(cat "$tmp/xl.rc")" = "0" ] \
  && fail "with no way to inspect processes the Codex leaf dispatched anyway — a one-writer rule that evaporates with a missing tool is not a rule: $out"
grep -qi 'refusing to dispatch a second writer on an unproven answer' <<<"$out" \
  || fail "the Codex leaf refused for some other reason than the unprovable occupancy answer: $out"
[ -e "$xdrun" ] \
  && fail "the unproven-occupancy refusal still created the run registry $xdrun"

# And the operator override is real: the same unprovable case must get PAST the
# guard when a human asserts they have checked by hand, or the only way forward
# on a host without lsof is deleting the guard.
# Asserting only that the refusal is ABSENT would pass just as well for a launch
# that died one line earlier for some unrelated reason, so this asserts what only
# a launch that got PAST the guard can leave behind: the run registry, the copied
# prompt, and the dispatch metadata. The inert stub then fails the way an inert
# stub must — no thread — which is itself proof the dispatch was reached.
out="$(codex_launch "$tmp/nolsof" CBR_ALLOW_UNPROVEN_OCCUPANCY=1)"
grep -qi 'refusing to dispatch a second writer' <<<"$out" \
  && fail "CBR_ALLOW_UNPROVEN_OCCUPANCY=1 did not release the unprovable-occupancy refusal, so the documented escape hatch does not work: $out"
for artefact in "$xdrun/prompt.txt" "$xdrun/meta.json" "$xdrun/pid"; do
  [ -f "$artefact" ] \
    || fail "with the override set the launch left no $(basename "$artefact") in $xdrun — it stopped somewhere before the dispatch, so the escape hatch is not shown to work: $out"
done
grep -qi 'did not emit thread.started' <<<"$out" \
  || fail "the override launch did not fail the way a dispatched-but-inert builder fails, so it is not established that it reached the dispatch at all: $out"
rm -rf "$xdrun"

# ---------------------------------------------------------------------------
# WIRING — one implementation of "is anybody working here"
# ---------------------------------------------------------------------------
for leaf in "$claude_leaf" "$codex_leaf"; do
  n="$(basename "$leaf")"
  grep -qE 'cbr_path_has_live_process "' "$leaf" \
    || fail "$n never CALLS cbr_path_has_live_process with a path — it decides liveness some other way, and a second copy of this rule is how one leaf gets the fix and the other keeps the false verdict"
  # A bare grep is also satisfied by a leaf that DEFINES its own copy after
  # sourcing the library, shadowing the shared one while looking wired. That is
  # the same hole the marker-predicate check had, found the same way.
  grep -qE '^[[:space:]]*cbr_path_has_live_process[[:space:]]*\(\)' "$leaf" \
    && fail "$n defines its own cbr_path_has_live_process, shadowing the shared predicate — the leaf now carries a private copy of the liveness rule and the shared one is dead code in it"
done

echo "status-interactive.test PASS (both leaves: no session + live process = interactive, not dead)"
