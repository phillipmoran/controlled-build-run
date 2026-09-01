#!/usr/bin/env bash
# The review wall stands at the merge boundary, and ONLY there.
#
#   prove-NO — a merge with an open blocking finding on the merged branch
#     refuses; a merge with no completed branch review at the merged tip
#     refuses; a fix-round chain past the 3-round cap refuses without a
#     recorded escalation ruling; an unreachable reviewer refuses.
#   the wall is DOWN off the boundary — an ordinary (non-merge) commit
#     passes the gate even while a FAIL review is open.
#   prove-YES — a clean branch (branch review done at the tip, no blockers)
#     merges, and leftover bookkeeping jobs are fold-closed as superseded.
set -euo pipefail

# GITHEAD_<hex> included: when this suite runs INSIDE a real merge's own
# pre-merge-commit hook (the battery gating a live merge), git's exported
# merge-head variable would otherwise leak into the fixture gate and turn
# the ordinary-commit case into a phantom merge.
for v in $(env | sed -nE 's/^(GIT_[A-Z_]*|GITHEAD_[0-9a-f]*)=.*/\1/p'); do unset "$v"; done

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
kit="$(cd "$here/.." && pwd)"
gate="$root/skills/cbr-core/scripts/merge-review-gate.sh"
[ -f "$gate" ] || gate="$kit/skill/claude-controlled-build-run/references/core/scripts/merge-review-gate.sh"

tmp="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
fail() { echo "merge-review-gate.test FAIL: $1" >&2; exit 1; }
[ -f "$gate" ] || fail "missing input: $gate"

# --- stub roborev: answers from $STATE, logs mutating calls -----------------
mkdir -p "$tmp/bin"
cat > "$tmp/bin/roborev" <<'SH'
#!/usr/bin/env bash
case "$1" in
  list)
    echo "$*" >> "$STATE/calls.log"
    if [[ "$*" == *--open* ]]; then cat "$STATE/open.json"; else cat "$STATE/all.json"; fi ;;
  respond|close)
    echo "$*" >> "$STATE/actions.log"
    [ -e "$STATE/fail-mutations" ] && exit 1 ;;
esac
exit 0
SH
chmod +x "$tmp/bin/roborev"
export STATE="$tmp/state"; mkdir -p "$STATE"; : > "$STATE/actions.log"

# --- fixture repo with a real in-progress merge -----------------------------
repo="$tmp/repo"; mkdir -p "$repo"
g() { git -C "$repo" -c user.email=t@t -c user.name=t "$@"; }
git -C "$repo" init -q -b main
echo base > "$repo/f"; g add -A; g commit -qm base
g checkout -qb stream/gate
echo work > "$repo/f"; g commit -qam "feat: work"
tip="$(g rev-parse HEAD)"
g checkout -q main

MERGE_SRC=stream/gate
start_merge() {
  g merge --no-ff --no-commit "$MERGE_SRC" >/dev/null 2>&1 || true
  git -C "$repo" rev-parse -q --verify MERGE_HEAD >/dev/null || fail "fixture broke: no MERGE_HEAD"
}
abort_merge() { g merge --abort 2>/dev/null || true; }

run_gate() { ( cd "$repo" && PATH="$tmp/bin:$PATH" "$gate" ); }

# --- prove-NO: open blocking finding refuses the merge ----------------------
printf '[{"id":9,"git_ref":"%s","status":"done","verdict":"FAIL"}]\n' "${tip:0:7}" > "$STATE/open.json"
printf '[{"id":8,"git_ref":"%s..%s","status":"done","verdict":"PASS"}]\n' "$(g merge-base main "$tip" | cut -c1-7)" "${tip:0:7}" > "$STATE/all.json"
start_merge
rc=0; out="$(run_gate 2>&1)" || rc=$?
[ "$rc" -ne 0 ] || fail "a merge with an open FAIL review on the branch was allowed: $out"
grep -q '9' <<<"$out" || fail "the refusal does not name the blocking job: $out"
# both queries must be scoped to the merged branch — an unscoped list lets
# another branch's identical-range review satisfy this branch's homework
grep -q -- '--branch stream/gate' "$STATE/calls.log" || fail "review queries not scoped to the merged branch: $(cat "$STATE/calls.log")"
if grep -v -- '--branch stream/gate' "$STATE/calls.log" | grep -q 'list'; then
  fail "an unscoped review list query survives: $(cat "$STATE/calls.log")"
fi

# queued (incomplete) review is also a blocker
printf '[{"id":10,"git_ref":"%s","status":"queued"}]\n' "${tip:0:7}" > "$STATE/open.json"
rc=0; out="$(run_gate 2>&1)" || rc=$?
[ "$rc" -ne 0 ] || fail "a merge with a still-queued review was allowed: $out"

# --- prove-NO: no completed branch review at the merged tip -----------------
printf 'null\n' > "$STATE/open.json"
printf '[{"id":8,"git_ref":"aaa1111..bbb2222","status":"done","verdict":"PASS"}]\n' > "$STATE/all.json"
rc=0; out="$(run_gate 2>&1)" || rc=$?
[ "$rc" -ne 0 ] || fail "a merge with no branch review ending at the merged tip was allowed: $out"
grep -qi 'branch review' <<<"$out" || fail "the refusal does not say what is missing: $out"

# --- prove-NO: a PARTIAL-range review ending at the tip does not count -------
# (ends at the merged tip but starts past the merge-base: only the last commit
# was reviewed, not the branch)
printf '[{"id":8,"git_ref":"%s..%s","status":"done","verdict":"PASS"}]\n' "${tip:0:7}" "${tip:0:7}" > "$STATE/all.json"
rc=0; out="$(run_gate 2>&1)" || rc=$?
[ "$rc" -ne 0 ] || fail "a partial-range review (start != merge-base) satisfied the wall: $out"

# --- prove-NO: two branches on one tip is an ambiguity, not a guess ---------
g branch -q stream/alias "$MERGE_SRC"
rc=0; out="$(run_gate 2>&1)" || rc=$?
[ "$rc" -ne 0 ] || fail "an ambiguous multi-ref tip was waved through on a guessed branch: $out"
grep -q 'CBR_MERGE_BRANCH' <<<"$out" || fail "the ambiguity refusal does not name the escape hatch: $out"
rc=0; out="$( cd "$repo" && PATH="$tmp/bin:$PATH" CBR_MERGE_BRANCH=stream/gate "$gate" 2>&1 )" || rc=$?
grep -q 'CBR_MERGE_BRANCH' <<<"$out" && fail "naming the branch did not resolve the ambiguity: $out"
g branch -q -D stream/alias

# --- prove-NO: reviewer unreachable refuses ---------------------------------
rc=0; out="$( cd "$repo" && PATH="$tmp/nobin:/usr/bin:/bin" "$gate" 2>&1 )" || rc=$?
[ "$rc" -ne 0 ] || fail "an unverifiable wall (no roborev on PATH) waved the merge through: $out"
abort_merge

# --- the wall is DOWN off the boundary --------------------------------------
printf '[{"id":9,"git_ref":"%s","status":"done","verdict":"FAIL"}]\n' "${tip:0:7}" > "$STATE/open.json"
rc=0; out="$(run_gate 2>&1)" || rc=$?
[ "$rc" -eq 0 ] || fail "an ordinary commit (no MERGE_HEAD) was held by the review gate — the per-commit wall was supposed to come down: $out"

# --- round cap: >3 review-fix commits TOTAL in the range need a ruling ------
# an ordinary commit interleaved mid-chain must NOT reset the count
g checkout -q stream/gate
for i in 1 2; do
  echo "fix$i" >> "$repo/f"; g commit -qam "fix(core): review 900$i — round $i"
done
echo feature >> "$repo/f"; g commit -qam "feat: ordinary work between rounds"
# the alternate sanctioned spelling counts toward the same total
echo "fix3" >> "$repo/f"; g commit -qam "fix(core): RoboRev 9003 — round 3"
# so does the plural batched form (a real batch commit once evaded the count)
echo "fix4" >> "$repo/f"; g commit -qam "fix(core): reviews 9004/9005 — batched round 4"
tip="$(g rev-parse HEAD)"
g checkout -q main
printf 'null\n' > "$STATE/open.json"
printf '[{"id":8,"git_ref":"%s..%s","status":"done","verdict":"PASS"}]\n' "$(g merge-base main "$tip" | cut -c1-7)" "${tip:0:7}" > "$STATE/all.json"
start_merge
rc=0; out="$(run_gate 2>&1)" || rc=$?
[ "$rc" -ne 0 ] || fail "a 4-round fix chain merged with no escalation ruling on file: $out"
grep -qi 'cap' <<<"$out" || fail "the round-cap refusal does not say so: $out"
g config branch.stream/gate.cbrEscalation "test ruling: proceed (fixture)"
rc=0; out="$(run_gate 2>&1)" || rc=$?
[ "$rc" -eq 0 ] || fail "a recorded escalation ruling did not unlock the round cap: $out"
g config --unset branch.stream/gate.cbrEscalation
abort_merge

# --- prove-YES: clean branch merges, bookkeeping folds ----------------------
# a fresh branch, so the over-cap chain above does not bleed into this case
g checkout -q -b stream/clean main
echo done >> "$repo/clean.txt"; g add -A; g commit -qm "feat: finish"
tip="$(g rev-parse HEAD)"
g checkout -q main
printf '[{"id":12,"git_ref":"%s","status":"done","verdict":"PASS"}]\n' "${tip:0:7}" > "$STATE/open.json"
printf '[{"id":8,"git_ref":"%s..%s","status":"done","verdict":"PASS"}]\n' "$(g merge-base main "$tip" | cut -c1-7)" "${tip:0:7}" > "$STATE/all.json"
MERGE_SRC=stream/clean
: > "$STATE/actions.log"
start_merge
rc=0; out="$(run_gate 2>&1)" || rc=$?
[ "$rc" -eq 0 ] || fail "a clean branch (branch review done at tip, no blockers) was refused: $out"
grep -q 'respond --job 12' "$STATE/actions.log" || fail "the leftover clean job was not folded (no respond): $(cat "$STATE/actions.log")"
grep -q 'close 12' "$STATE/actions.log" || fail "the leftover clean job was not closed: $(cat "$STATE/actions.log")"

# --- prove-NO: a fold that cannot close blocks the merge --------------------
# (an open review must not survive behind the merge)
touch "$STATE/fail-mutations"
rc=0; out="$(run_gate 2>&1)" || rc=$?
[ "$rc" -ne 0 ] || fail "a failed fold-close still let the merge through: $out"
grep -q '12' <<<"$out" || fail "the failed-fold refusal does not name the job: $out"
rm -f "$STATE/fail-mutations"
abort_merge

# --- REAL HOOK PATH: an ordinary auto-committing merge is blocked ------------
# Not a manual invocation: an auto-committing `git merge` fires ONLY the
# pre-merge-commit hook — git has NO fallback to the pre-commit hook there
# (checked below, so a git that grew one would surface). The installed
# control plane gets that hook from `pre-commit install` via
# default_install_hook_types; here the gate stands in as the hook body.
g checkout -q -b stream/auto main
echo auto >> "$repo/auto.txt"; g add -A; g commit -qm "feat: auto" --no-verify
tip="$(g rev-parse HEAD)"
g checkout -q main
printf '[{"id":13,"git_ref":"%s","status":"done","verdict":"FAIL"}]\n' "${tip:0:7}" > "$STATE/open.json"
printf '[{"id":8,"git_ref":"%s..%s","status":"done","verdict":"PASS"}]\n' "$(g merge-base main "$tip" | cut -c1-7)" "${tip:0:7}" > "$STATE/all.json"
pre="$(g rev-parse HEAD)"
# no-fallback premise: with ONLY a pre-commit hook, the blocking merge sails —
# this is exactly the bypass the pre-merge-commit install type exists to close
printf '#!/bin/sh\nexec "%s"\n' "$gate" > "$repo/.git/hooks/pre-commit"
chmod +x "$repo/.git/hooks/pre-commit"
rc=0; out="$( cd "$repo" && PATH="$tmp/bin:$PATH" git -c user.email=t@t -c user.name=t merge --no-ff stream/auto -m 'merge auto' 2>&1 )" || rc=$?
[ "$rc" -eq 0 ] || { git -C "$repo" merge --abort 2>/dev/null || true; fail "git ran a pre-commit fallback on an auto-merge — the premise behind requiring the pre-merge-commit hook type changed; re-derive the wiring: $out"; }
g reset -q --hard "$pre"
# the wall: the same gate as the pre-merge-commit hook aborts the merge commit
printf '#!/bin/sh\nexec "%s"\n' "$gate" > "$repo/.git/hooks/pre-merge-commit"
chmod +x "$repo/.git/hooks/pre-merge-commit"
rc=0; out="$( cd "$repo" && PATH="$tmp/bin:$PATH" git -c user.email=t@t -c user.name=t merge --no-ff stream/auto -m 'merge auto' 2>&1 )" || rc=$?
[ "$rc" -ne 0 ] || fail "an ordinary auto-committing git merge completed past an open blocking review — the pre-merge-commit hook path never blocked: $out"
[ "$(g rev-parse HEAD)" = "$pre" ] || fail "the blocked merge still created a commit"
g merge --abort 2>/dev/null || true
printf 'null\n' > "$STATE/open.json"
rc=0; out="$( cd "$repo" && PATH="$tmp/bin:$PATH" git -c user.email=t@t -c user.name=t merge --no-ff stream/auto -m 'merge auto' 2>&1 )" || rc=$?
[ "$rc" -eq 0 ] || fail "a clean branch did not auto-merge through the real hook path: $out"
rm -f "$repo/.git/hooks/pre-commit" "$repo/.git/hooks/pre-merge-commit"

# --- prove-NO: an octopus auto-merge is refused (one branch per merge) ------
g checkout -q -b stream/octo1 main
echo o1 > "$repo/o1.txt"; g add -A; g commit -qm "feat: o1" --no-verify
g checkout -q -b stream/octo2 main
echo o2 > "$repo/o2.txt"; g add -A; g commit -qm "feat: o2" --no-verify
g checkout -q main
printf 'null\n' > "$STATE/open.json"
printf '#!/bin/sh\nexec "%s"\n' "$gate" > "$repo/.git/hooks/pre-merge-commit"
chmod +x "$repo/.git/hooks/pre-merge-commit"
rc=0; out="$( cd "$repo" && PATH="$tmp/bin:$PATH" git -c user.email=t@t -c user.name=t merge stream/octo1 stream/octo2 -m 'octopus' 2>&1 )" || rc=$?
[ "$rc" -ne 0 ] || fail "an octopus auto-merge sailed — only the first head's review homework was checked: $out"
# the refusal must be the multi-head guard itself, not an incidental
# missing-branch-review block on the first head
grep -qi 'octopus' <<<"$out" || fail "the octopus merge was refused for the wrong reason: $out"
g merge --abort 2>/dev/null || true
g reset -q --hard main
rm -f "$repo/.git/hooks/pre-merge-commit"

# --- SHA-256 repos are production too: the hook env exports 64-hex GITHEAD --
if git init -q --object-format=sha256 "$tmp/repo256" 2>/dev/null; then
  g2() { git -C "$tmp/repo256" -c user.email=t@t -c user.name=t "$@"; }
  g2 checkout -qb main 2>/dev/null || true
  echo base > "$tmp/repo256/f"; g2 add -A; g2 commit -qm base
  g2 checkout -qb stream/s256
  echo work > "$tmp/repo256/f"; g2 commit -qam "feat: work" --no-verify
  tip256="$(g2 rev-parse HEAD)"
  g2 checkout -q main
  printf '[{"id":14,"git_ref":"%s","status":"done","verdict":"FAIL"}]\n' "${tip256:0:7}" > "$STATE/open.json"
  printf '[{"id":8,"git_ref":"%s..%s","status":"done","verdict":"PASS"}]\n' "$(g2 merge-base main "$tip256" | cut -c1-7)" "${tip256:0:7}" > "$STATE/all.json"
  printf '#!/bin/sh\nexec "%s"\n' "$gate" > "$tmp/repo256/.git/hooks/pre-merge-commit"
  chmod +x "$tmp/repo256/.git/hooks/pre-merge-commit"
  rc=0; out="$( cd "$tmp/repo256" && PATH="$tmp/bin:$PATH" git -c user.email=t@t -c user.name=t merge --no-ff stream/s256 -m 'merge s256' 2>&1 )" || rc=$?
  [ "$rc" -ne 0 ] || fail "a SHA-256 repo's auto-merge sailed past an open blocking review — the 64-hex GITHEAD went unrecognized: $out"
  git -C "$tmp/repo256" merge --abort 2>/dev/null || true
fi

# --- WIRING: the gate rides pre-commit in the live config and both leaves ---
# An auto-committing `git merge` fires pre-merge-commit; git's fallback to the
# pre-commit hook holds only while NO pre-merge-commit hook exists, so every
# config must also install that type — the wall must not lean on the fallback.
for cfg in "$root/.pre-commit-config.yaml" \
           "$root/skills/claude-controlled-build-run/templates/pre-commit-config.yaml" \
           "$root/skills/codex-controlled-build-run/templates/pre-commit-config.yaml"; do
  [ -f "$cfg" ] || continue
  grep -q 'merge-review-gate' "$cfg" \
    || fail "$cfg never wires merge-review-gate — the wall exists but stands nowhere"
  grep -q 'pre-merge-commit' "$cfg" \
    || fail "$cfg does not install the pre-merge-commit hook type — an auto-committing merge bypasses the wall the moment any pre-merge-commit hook appears"
done

echo "merge-review-gate.test PASS (blocked: open finding, queued review, missing branch review, no reviewer, over-cap chain; open: ordinary commit; clean merge folds bookkeeping)"
