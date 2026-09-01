#!/usr/bin/env bash
# Stop-before-DONE: a stream builder may not end its session with the work
# unfinished and no terminal marker to say so.
#
# The failure this exists for is a builder that stops looking finished. Phases
# left unchecked, or a completion latch never committed, and the session simply
# ends — the watcher sees a stopped session and cannot tell COMPLETE from DIED,
# so the strand is either reaped with real work in it or left waiting on a
# builder that is never coming back.
#
# The predicate is implemented ONCE, in the neutral core, and each leaf's hook
# is I/O translation only. That is not tidiness: the two leaves speak different
# hook payloads and pin different operator-park filenames, and a predicate
# copied into both is a predicate that will only ever be fixed in one.
#
# Hermetic: scratch worktrees; the real repo is untouched.
set -euo pipefail

for v in $(env | sed -n 's/^\(GIT_[A-Z_]*\)=.*/\1/p'); do unset "$v"; done

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
kit="$(cd "$here/.." && pwd)"

pred="$root/skills/cbr-core/scripts/stop-predicate.sh"
[ -f "$pred" ] || pred="$kit/skill/claude-controlled-build-run/references/core/scripts/stop-predicate.sh"
claude_hook="$root/skills/claude-controlled-build-run/templates/hooks/builder-stop-check.sh"
[ -f "$claude_hook" ] || claude_hook="$kit/skill/claude-controlled-build-run/templates/hooks/builder-stop-check.sh"
codex_hook="$root/skills/codex-controlled-build-run/templates/hooks/builder-stop-check.sh"
[ -f "$codex_hook" ] || codex_hook="$kit/skill/codex-controlled-build-run/templates/hooks/builder-stop-check.sh"

tmp="$(cd "$(mktemp -d)" && pwd -P)"
cleanup() { local rc=$?; rm -rf "$tmp"; exit "$rc"; }
trap cleanup EXIT
fail() { echo "stop-before-done.test FAIL: $1" >&2; exit 1; }

[ -x "$pred" ] || fail "the shared stop predicate is missing or not executable: $pred"

# The law and its acceptance row, in the neutral core — a gate the law never
# states is a local habit, and it will not survive a port.
law="$root/skills/cbr-core/modes/fleet.md"
[ -f "$law" ] || law="$kit/skill/claude-controlled-build-run/references/core/modes/fleet.md"
grep -qi 'stop-before-done' "$law" || fail "core law does not state the stop-before-DONE invariant"

# A worktree in a named phase state. `phases` is checked|unchecked. Markers are
# COMMITTED, because that is what the law asks for and what a watcher outside
# the worktree can read; a marker named with a leading `~` is written to the
# working tree and left uncommitted, which is how the negative cases are built.
make_wt() { # name phases [ [~]marker-file ...]
  local name="$1" phases="$2"; shift 2
  local d="$tmp/$name"
  mkdir -p "$d"
  git -C "$d" init -q -b main
  git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  git -C "$d" checkout -q -b stream/"$name"
  if [ "$phases" = checked ]; then
    printf '# plan\n\n- [x] **P1 — done.**\n- [x] **P2 — done.**\n' > "$d/task_plan.md"
  else
    printf '# plan\n\n- [x] **P1 — done.**\n- [ ] **P2 — not done.**\n' > "$d/task_plan.md"
  fi
  local m
  for m in "$@"; do printf 'x\n' > "$d/${m#\~}"; done
  git -C "$d" add task_plan.md >/dev/null 2>&1
  for m in "$@"; do
    case "$m" in ~*) ;; *) git -C "$d" add "$m" >/dev/null 2>&1 ;; esac
  done
  git -C "$d" -c user.email=t@t -c user.name=t commit -q -m state
  printf '%s' "$d"
}

verdict() { # worktree park-filename  -> prints allow|block
  local d="$1" park="$2" rc=0
  ( cd "$d" && "$pred" --worktree "$d" --park-file "$park" >"$tmp/out.txt" 2>&1 ) || rc=$?
  [ "$rc" -eq 0 ] && echo allow || echo block
}

# --- (a) every phase checked, no completion latch --------------------------
# The tempting one to allow. It must block: the latch is what turns "the
# session ended" into "the work is COMPLETE", and a plan checked off in the
# working tree is not a fact any watcher can read.
d="$(make_wt a checked)"
[ "$(verdict "$d" NEEDS-OPERATOR.md)" = block ] \
  || fail "a builder with every phase checked but no DONE.marker was allowed to stop — nothing distinguishes it from a death"

# --- (b) unchecked phases with a DONE.marker already sitting there ---------
# The marker is not a password. Work that is demonstrably unfinished blocks
# even when a latch from some earlier state is lying around.
d="$(make_wt b unchecked DONE-stream-b.marker)"
[ "$(verdict "$d" NEEDS-OPERATOR.md)" = block ] \
  || fail "an unchecked plan was allowed to stop because a stale DONE.marker was present"

# --- (c) the terminal blockers, each named by the LEAF'S OWN pin -----------
# Parameterized on purpose: hardcoding one leaf's filename would mean the other
# leaf's operator park silently fails to release its builder.
for park in NEEDS-OPERATOR.md NEEDS-HUMAN.md; do
  d="$(make_wt "c-$park" unchecked "$park")"
  [ "$(verdict "$d" "$park")" = allow ] \
    || fail "$park did not release a stopped builder for the leaf that pins that name"
  # ...and the OTHER leaf's spelling must not release it — a park file is only
  # terminal for the control plane that told the human to write it.
  other=NEEDS-HUMAN.md; [ "$park" = NEEDS-HUMAN.md ] && other=NEEDS-OPERATOR.md
  d="$(make_wt "c-x-$park" unchecked "$park")"
  [ "$(verdict "$d" "$other")" = block ] \
    || fail "a park file spelled $park released a builder whose leaf pins $other"
done

# The two escape hatches deliberately do NOT require a commit, and the fixture
# pins that asymmetry so nobody "fixes" it later: they are read off the
# filesystem by the same watcher that polls ASK-ORCH.md, and a control plane broken
# enough to fail its own commit gates would otherwise trap the session with no
# way out — which is the wedge the whole fail-open design exists to avoid.
d="$(make_wt d-untracked unchecked ~CONTROL-PLANE-BROKEN.marker)"
[ "$(verdict "$d" NEEDS-OPERATOR.md)" = allow ] \
  || fail "an uncommitted CONTROL-PLANE-BROKEN.marker did not release — a control plane too broken to commit would trap its builder"
d="$(make_wt c-untracked unchecked ~NEEDS-OPERATOR.md)"
[ "$(verdict "$d" NEEDS-OPERATOR.md)" = allow ] \
  || fail "an uncommitted park file did not release — the same trap, reached through the human handoff"

d="$(make_wt d unchecked CONTROL-PLANE-BROKEN.marker)"
[ "$(verdict "$d" NEEDS-OPERATOR.md)" = allow ] \
  || fail "CONTROL-PLANE-BROKEN.marker did not release a stopped builder — a broken control plane cannot finish its phases"

# An uncommitted latch is not a fact. The claim this marker makes — the work
# is COMPLETE — is read from the repository by whoever decides whether the
# strand can be reaped; a file sitting only in the working tree tells them
# nothing and dies with the worktree.
d="$(make_wt e-untracked checked ~DONE-stream-e-untracked.marker)"
[ "$(verdict "$d" NEEDS-OPERATOR.md)" = block ] \
  || fail "an uncommitted DONE.marker released the gate — the completion claim never reaches the repository"

d="$(make_wt e checked DONE-stream-e.marker)"
[ "$(verdict "$d" NEEDS-OPERATOR.md)" = allow ] \
  || fail "a finished builder with its latch committed was still blocked from stopping"

# The latch is the branch's OWN marker name. A bare legacy DONE.marker on a
# stream branch is nobody's completion claim — most often it is inherited from
# a merged sibling, which is the false release the per-branch rename removes.
d="$(make_wt e-legacy checked DONE.marker)"
[ "$(verdict "$d" NEEDS-OPERATOR.md)" = block ] \
  || fail "a committed bare DONE.marker released a stream builder — an inherited legacy marker is a completion claim again"

# The FIX ROUND, which is the shape this gate meets most often: a latch was
# committed, the checkpoint came back with findings, another round of work
# happened, and the marker is rewritten. The path has been tracked the whole
# time, so a predicate that asks whether the FILE is committed says yes while
# the claim in front of it has reached nobody.
d="$(make_wt e-rewrite checked DONE-stream-e-rewrite.marker)"
printf 'round two — rewritten and not committed\n' > "$d/DONE-stream-e-rewrite.marker"
[ "$(verdict "$d" NEEDS-OPERATOR.md)" = block ] \
  || fail "a REWRITTEN DONE.marker released the gate while uncommitted — the path was in HEAD, the completion claim was not, and a fix round is exactly when that happens"
# Staged is not committed: an index entry dies with the worktree too.
git -C "$d" add DONE-stream-e-rewrite.marker >/dev/null 2>&1
[ "$(verdict "$d" NEEDS-OPERATOR.md)" = block ] \
  || fail "a STAGED DONE.marker released the gate — the index is not something a reader outside the worktree can see"
git -C "$d" -c user.email=t@t -c user.name=t commit -q -m 'commit the rewrite'
[ "$(verdict "$d" NEEDS-OPERATOR.md)" = allow ] \
  || fail "the committed rewrite did not release — the fix round can never end"

# The degraded path: the predicate without its shared library beside it. A
# release granted there is the worst kind, because the release is what a
# missing library must never be able to grant — the answer is unavailable, not
# yes, and this gate fails CLOSED on what it could not check.
lone="$tmp/lone"; mkdir -p "$lone"
cp "$pred" "$lone/stop-predicate.sh"; chmod +x "$lone/stop-predicate.sh"
d="$(make_wt e-lonepred checked DONE-stream-e-lonepred.marker)"
printf 'round two — rewritten and not committed\n' > "$d/DONE-stream-e-lonepred.marker"
rc=0
( cd "$d" && "$lone/stop-predicate.sh" --worktree "$d" --park-file NEEDS-OPERATOR.md >"$tmp/lone.out" 2>&1 ) || rc=$?
[ "$rc" -ne 0 ] \
  || fail "with its shared library absent, the predicate fell back to a check it had already outgrown and RELEASED a builder whose latch is uncommitted: $(cat "$tmp/lone.out")"

# --- (f) scope guard: this binds stream builders, nobody else --------------
d="$(make_wt f unchecked)"
git -C "$d" checkout -q -b integration/something
[ "$(verdict "$d" NEEDS-OPERATOR.md)" = allow ] \
  || fail "the predicate blocked a non-stream branch — an orchestrator or a human would be trapped in its own session"

# --- (g) a plan whose phases are written the way real plans write them -----
# The emphasis markers are the point: a predicate that only matches bare
# "- [ ] P2" reads every real plan in this repo as fully checked and never
# blocks anything.
d="$tmp/g"; mkdir -p "$d"; git -C "$d" init -q -b main; git -C "$d" checkout -q -b stream/g
printf '# plan\n\n- [ ] **P3 — invariant pair.** Builder-reachability...\n' > "$d/task_plan.md"
[ "$(verdict "$d" NEEDS-OPERATOR.md)" = block ] \
  || fail "an unchecked phase written with markdown emphasis was read as checked"

# --- (h) phase identifiers that are not P-then-digit ------------------------
# Real plans in this repo already use forms like `P-E` and `P5b`. A pattern
# that only understands `P` followed by a digit reads those plans as fully
# checked, and combined with a latch left over from an earlier state it hands
# back exactly the silent stop the gate exists to refuse.
for id in 'P-E' 'P5b' 'Phase 4' 'Stage2'; do
  d="$tmp/h-$(printf '%s' "$id" | tr -d ' ')"; mkdir -p "$d"
  git -C "$d" init -q -b main
  git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  git -C "$d" checkout -q -b stream/h
  printf '# plan\n\n- [ ] **%s — still open.**\n' "$id" > "$d/task_plan.md"
  printf 'x\n' > "$d/DONE-stream-h.marker"
  git -C "$d" add -A >/dev/null 2>&1
  git -C "$d" -c user.email=t@t -c user.name=t commit -q -m state
  [ "$(verdict "$d" NEEDS-OPERATOR.md)" = block ] \
    || fail "an open phase written '$id' was read as checked, and a stale latch let the builder stop"
done

# --- (i) a stream builder whose plan is gone ------------------------------
# Otherwise `rm task_plan.md` is the bypass for the entire gate.
d="$tmp/i"; mkdir -p "$d"
git -C "$d" init -q -b main
git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
git -C "$d" checkout -q -b stream/i
[ "$(verdict "$d" NEEDS-OPERATOR.md)" = block ] \
  || fail "a stream builder with no task_plan.md was allowed to stop — deleting the plan is then the bypass for the whole gate"

# --- BOTH LEAVES DELEGATE — the predicate exists once ----------------------
for h in "$claude_hook" "$codex_hook"; do
  [ -f "$h" ] || fail "leaf stop hook missing: $h"
  grep -q 'stop-predicate.sh' "$h" \
    || fail "$h does not delegate to the shared predicate — it has its own copy of the rule"
  grep -qE 'unchecked|DONE\.marker.*absent|grep -qE .\^- \\\[ \\\]' "$h" \
    && fail "$h still decides the verdict itself; a leaf hook is I/O translation only"
done
# --- the hook cannot decide: it must fail OPEN, and say so ----------------
# A hook whose predicate is missing or broken must not refuse the stop, because
# every way OUT of a refusal is read by that same predicate. Both cases are
# driven for real, by resolving the hook to a scratch worktree where the
# predicate is absent, then present-but-erroring.
for case in missing erroring; do
  d="$(make_wt "hook-$case" unchecked)"
  mkdir -p "$d/.claude/hooks" "$d/skills/cbr-core/scripts"
  cp "$claude_hook" "$d/.claude/hooks/builder-stop-check.sh"
  if [ "$case" = erroring ]; then
    printf '#!/usr/bin/env bash\necho "called wrong" >&2\nexit 2\n' > "$d/skills/cbr-core/scripts/stop-predicate.sh"
    chmod +x "$d/skills/cbr-core/scripts/stop-predicate.sh"
  fi
  rm -f "$d/STOP-UNGUARDED.marker"
  out="$( cd "$d" && printf '{"stop_hook_active":false}' | bash "$d/.claude/hooks/builder-stop-check.sh" 2>&1 )" || true
  grep -q '"block"\|"deny"' <<<"$out" \
    && fail "with a $case predicate the hook refused the stop — it also refuses every way out of that refusal, which is an unescapable session: $out"
  [ -f "$d/STOP-UNGUARDED.marker" ] \
    || fail "the hook disarmed itself ($case predicate) and left no observable trace — 'loud on the way out' is not true of a message sent to a discarded stream"
done

# --- every release the predicate honours must be WATCHED -------------------
# A terminal marker no watcher latches is a handoff to nobody: the builder is
# released, goes quiet, and the orchestrator learns about it minutes later as
# an unexplained stall it has to diagnose from scratch.
claude_watch="$root/skills/claude-controlled-build-run/scripts/captain-watch.sh"
[ -f "$claude_watch" ] || claude_watch="$kit/skill/claude-controlled-build-run/scripts/captain-watch.sh"
codex_watch="$root/skills/codex-controlled-build-run/scripts/captain-watch-codex.sh"
[ -f "$codex_watch" ] || codex_watch="$kit/skill/codex-controlled-build-run/scripts/captain-watch-codex.sh"
for pair in "$claude_watch:NEEDS-OPERATOR.md" "$codex_watch:NEEDS-HUMAN.md"; do
  w="${pair%%:*}"; park="${pair##*:}"
  [ -f "$w" ] || fail "watcher missing: $w"
  for marker in "$park" CONTROL-PLANE-BROKEN.marker STOP-UNGUARDED.marker; do
    grep -q "$marker" "$w" \
      || fail "$(basename "$w") never reads $marker, but the stop gate releases a builder on it — that handoff reaches nobody"
  done
done

# --- the LIVE wiring in this repo, not just the template ------------------
# The template is what a port installs; this file is what actually fires here.
# Canonical layout only: when this suite runs from the standalone package,
# $root is whatever directory happens to contain the package, and a
# .claude/settings.json found there belongs to some other repo — judging it
# would break hermeticity. The layout is identified structurally (this file
# sits at $root/kit/verify only in the source repo), not by the presence of
# installable pieces a target repo could legitimately carry.
live_settings="$root/.claude/settings.json"
if [ "$here" = "$root/kit/verify" ] && [ -f "$live_settings" ]; then
  python3 - "$live_settings" <<'PY' || fail "this repo's .claude/settings.json declares no Stop hook running builder-stop-check.sh — the gate is installed everywhere except where it is running"
import json, sys
cfg = json.load(open(sys.argv[1]))
blocks = cfg.get("hooks", {}).get("Stop", [])
cmds = [h.get("command", "") for b in blocks for h in b.get("hooks", [])]
sys.exit(0 if any("builder-stop-check.sh" in c for c in cmds) else 1)
PY
  live_hook="$root/.claude/hooks/builder-stop-check.sh"
  [ -f "$live_hook" ] || fail "this repo declares the Stop hook but $live_hook does not exist"
  cmp -s "$live_hook" "$claude_hook" \
    || fail "the live stop hook has drifted from the skill template — the gate that fires here is not the gate that ships"
fi

grep -q 'NEEDS-OPERATOR' "$claude_hook" || fail "the claude leaf hook does not pin its operator-park filename"
grep -q 'NEEDS-HUMAN' "$codex_hook"  || fail "the codex leaf hook does not pin its operator-park filename"

# --- the leaf hooks RUN, against a real payload ----------------------------
d="$(make_wt h checked)"
out="$( cd "$d" && printf '{"stop_hook_active":false}' | bash "$claude_hook" 2>&1 )" || true
grep -q '"block"\|"deny"' <<<"$out" \
  || fail "the claude leaf hook did not emit a blocking verdict for an unfinished builder: $out"
rm -f "$d/STOP-UNGUARDED.marker"
out="$( cd "$d" && printf '{"stop_hook_active":true}' | bash "$claude_hook" 2>&1 )" || true
grep -q '"block"\|"deny"' <<<"$out" \
  && fail "the claude leaf hook blocked again while its own block was already active — that is the infinite loop"
# The bypass is real and necessary, so it must be a FACT rather than a silence:
# without it the invariant is "refuse the first stop, then let the builder go
# quiet with the plan wide open", and nothing outside the worktree ever knows.
[ -f "$d/STOP-UNGUARDED.marker" ] \
  || fail "the second stop went through with the plan unfinished and left no trace — the gate is bypassable in two stops, invisibly"
out="$( cd "$d" && printf '{"stop_hook_active":false}' | bash "$codex_hook" 2>&1 )" || true
grep -q '"block"' <<<"$out" \
  || fail "the codex leaf hook did not emit a blocking verdict for an unfinished builder: $out"

# --- the hook is WIRED, not merely written ---------------------------------
# A stop gate that exists as a template nobody installs is a gate that has
# never fired. Each leaf must declare it on its own Stop event, and the
# provisioner must put it in every worktree it births.
claude_settings="$root/skills/claude-controlled-build-run/templates/claude-settings.json"
[ -f "$claude_settings" ] || claude_settings="$kit/skill/claude-controlled-build-run/templates/claude-settings.json"
python3 - "$claude_settings" <<'PY' || fail "the claude leaf's settings template does not declare a Stop hook running builder-stop-check.sh"
import json, sys
cfg = json.load(open(sys.argv[1]))
blocks = cfg.get("hooks", {}).get("Stop", [])
cmds = [h.get("command", "") for b in blocks for h in b.get("hooks", [])]
sys.exit(0 if any("builder-stop-check.sh" in c for c in cmds) else 1)
PY
codex_hooks_json="$root/skills/codex-controlled-build-run/templates/codex-hooks.json"
[ -f "$codex_hooks_json" ] || codex_hooks_json="$kit/skill/codex-controlled-build-run/templates/codex-hooks.json"
grep -q 'builder-stop-check.sh' "$codex_hooks_json" \
  || fail "the codex leaf's hooks template does not run builder-stop-check.sh"
cbr="$root/skills/claude-controlled-build-run/scripts/cbr.sh"
[ -f "$cbr" ] || cbr="$kit/skill/claude-controlled-build-run/scripts/cbr.sh"
grep -qE '^ *put hooks/builder-stop-check\.sh ' "$cbr" \
  || fail "provision does not install the stop hook — a newborn builder would be born ungated"
grep -q 'builder-stop-check.sh' <<<"$(sed -n '/^  for h in roborev-gate.sh/,/^  done/p' "$cbr")" \
  || fail "doctor does not check the stop hook, so it can go missing silently"

echo "stop-before-done.test PASS (one shared predicate; checked-no-latch and unchecked-stale-latch both block; each leaf's OWN park pin releases and the other's does not; control-plane-broken releases; non-stream out of scope; real plan emphasis parsed; both leaf hooks delegate, run, and are wired by each leaf; the latch must be committed, the escape hatches deliberately need not be; non-numeric phase ids counted)"
