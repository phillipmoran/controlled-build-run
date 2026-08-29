#!/usr/bin/env bash
# Regression for the shared, provider-neutral closeout mechanics library
# (skills/cbr-core/scripts/strand-lib.sh), which BOTH harness leaves call.
#
# Each case pins one gap observed live on 2026-08-19:
#   archive     — the strand's records must come from its final COMMIT, because
#                 by closeout time the worktree copy is identical to the base's
#                 (so a cmp-skip drops it) or already gone.
#   marker      — a merged strand's completion marker must not survive on the
#                 base branch, where the next strand inherits it via merge.
#   reground    — the base's root plan must stop naming the dead strand branch,
#                 or the plan-coherence gate fails the base's next commit.
#   marker id   — a marker whose first line names ANOTHER branch is not this
#                 strand's completion signal; one that names no branch at all is
#                 (older markers predate the convention and must keep working).
#   liveness    — a process rooted anywhere under a folder proves it is in use,
#                 with no session registry involved.
#   honesty     — a record that exists and cannot be saved, and a path that
#                 cannot be staged, must FAIL. Closeout deletes the worktree and
#                 the branch moments later, so a silent skip there is the same
#                 class of quiet loss this whole strand exists to remove.
# Hermetic: everything happens in a scratch repo; the real repo is untouched.
set -euo pipefail

# pre-commit exports GIT_DIR/GIT_INDEX_FILE/GIT_WORK_TREE to hook processes;
# inherited, the fixture's git calls would operate on the HOST repo's index.
for v in $(env | sed -n 's/^\(GIT_[A-Z_]*\)=.*/\1/p'); do unset "$v"; done

# Test the CANONICAL source when we are in the source repo (kit/ is a build
# artifact of it); fall back to the kit's own mirror so a port can run this too.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
lib="$root/skills/cbr-core/scripts/strand-lib.sh"
[ -f "$lib" ] || lib="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/skill/claude-controlled-build-run/references/core/scripts/strand-lib.sh"

# Canonicalise: on macOS mktemp hands back /var/... while git and `pwd -P` report
# /private/var/..., so a path assertion would otherwise never match.
tmp="$(cd "$(mktemp -d)" && pwd -P)"
sleeper=""
cleanup() {
  # Preserve the script's real status: `wait` on a killed child yields 143, and
  # letting that escape the trap would report a passing run as a failure.
  local rc=$?
  # `wait` after the kill: without it the shell prints its own "Terminated"
  # job notice to stderr, which reads like a test failure in a gate log.
  # `|| true` on both: under `set -e` a `wait` that reports the kill signal
  # aborts the trap before the cleanup below and becomes the exit status.
  if [ -n "$sleeper" ]; then kill "$sleeper" 2>/dev/null || true; wait "$sleeper" 2>/dev/null || true; fi
  rm -rf "$tmp"
  exit "$rc"
}
trap cleanup EXIT
fail() { echo "strand-lib.test FAIL: $1" >&2; exit 1; }

[ -f "$lib" ] || fail "shared closeout library not found (looked for skills/cbr-core/scripts/strand-lib.sh)"
# shellcheck source=/dev/null
. "$lib"

git="git -C $tmp/repo -c user.email=t@t -c user.name=t"
mkdir -p "$tmp/repo"
git -C "$tmp/repo" init -q -b main
echo base > "$tmp/repo/f.txt"
printf '# task_plan.md\n\n**Branch:** main\n' > "$tmp/repo/task_plan.md"
$git add -A && $git commit -qm base

# A strand branch whose final commit carries the full record set. The worktree
# copies are then made IDENTICAL to the base's, which is exactly the post-merge
# state in which the old cmp-based archiver silently copied nothing.
$git checkout -q -b stream/recorded
printf '# task_plan.md\n\n**Branch:** stream/recorded\n\nthe strand plan\n' > "$tmp/repo/task_plan.md"
printf 'the strand progress log\n' > "$tmp/repo/progress.md"
printf 'the strand findings\n' > "$tmp/repo/findings.md"
printf 'stream/recorded — COMPLETE 2026-08-19\n\nall phases green\n' > "$tmp/repo/DONE.marker"
$git add -A && $git commit -qm 'strand records'
$git checkout -q main
$git merge -q --no-ff -m 'merge strand' stream/recorded

# ---- case 1: archive reads the strand's final COMMIT, not the working tree ----
# Sabotage the working tree exactly as reality does: the merge already put the
# strand's copies on main, so a worktree-vs-base comparison sees no difference.
rm -f "$tmp/repo/progress.md"
printf 'CLOBBERED\n' > "$tmp/repo/findings.md"

dest="$tmp/repo/archive/recorded"
out="$(cbr_archive_strand_records "$tmp/repo" stream/recorded "$dest" \
        task_plan.md progress.md findings.md DONE.marker)" \
  || fail "cbr_archive_strand_records exited non-zero: $out"

for f in task_plan.md progress.md findings.md DONE.marker; do
  [ -f "$dest/$f" ] || fail "archive is missing $f — it must come from the strand's final commit"
done
grep -q 'the strand plan'        "$dest/task_plan.md" || fail "archived task_plan.md is not the strand's version"
grep -q 'the strand progress log' "$dest/progress.md"  || fail "archived progress.md is not the strand's version (deleted from the worktree)"
grep -q 'the strand findings'     "$dest/findings.md"  || fail "archived findings.md is not the strand's version (clobbered in the worktree)"
grep -q 'archived=4' <<<"$out"    || fail "expected archived=4 in output, got: $out"

# A record file the strand never had is simply absent — not an error, not an
# empty file (an empty archived plan reads as "the builder wrote nothing").
out2="$(cbr_archive_strand_records "$tmp/repo" stream/recorded "$tmp/repo/archive/partial" \
          task_plan.md NOPE.md)" || fail "archiving a missing record file must not fail"
[ -e "$tmp/repo/archive/partial/NOPE.md" ] && fail "a record the strand never had must not be created in the archive"
grep -q 'archived=1' <<<"$out2" || fail "expected archived=1 for the partial set, got: $out2"

# Called with no file list at all, the library falls back to its own default
# record set — the path every caller that just wants "the usual records" takes,
# so it cannot go unexercised.
outd="$(cbr_archive_strand_records "$tmp/repo" stream/recorded "$tmp/repo/archive/defaults")" \
  || fail "archiving with the default record list must succeed: $outd"
for f in task_plan.md progress.md findings.md DONE.marker; do
  [ -f "$tmp/repo/archive/defaults/$f" ] || fail "the default record list did not archive $f"
done
grep -q 'archived=4' <<<"$outd" || fail "expected archived=4 from the default record list, got: $outd"

# ---- case 2: the completion marker does not survive on the base branch ----
[ -f "$tmp/repo/DONE.marker" ] || fail "fixture wrong: the merge should have carried DONE.marker onto main"
mout="$(cbr_remove_marker_from_base "$tmp/repo" DONE.marker)" || fail "cbr_remove_marker_from_base failed: $mout"
[ -e "$tmp/repo/DONE.marker" ] && fail "DONE.marker still on the base branch's working tree"
$git diff --cached --name-only | grep -qx 'DONE.marker' \
  || fail "the marker removal must be STAGED so it rides the closeout commit"
grep -q 'marker=removed' <<<"$mout" || fail "expected marker=removed, got: $mout"

# Idempotent: closeout runs again, or the marker was never merged. No error.
mout2="$(cbr_remove_marker_from_base "$tmp/repo" DONE.marker)" || fail "second removal must be a clean no-op"
grep -q 'marker=absent' <<<"$mout2" || fail "expected marker=absent on the second run, got: $mout2"

# ---- case 3: the base's root plan stops naming the dead strand branch ----
grep -q '^\*\*Branch:\*\* stream/recorded' "$tmp/repo/task_plan.md" \
  || fail "fixture wrong: the merge should have left the strand's Branch line on main"
rout="$(cbr_reground_plan_branch "$tmp/repo/task_plan.md" main)" || fail "cbr_reground_plan_branch failed: $rout"
grep -q '^\*\*Branch:\*\* main$' "$tmp/repo/task_plan.md" || fail "the plan's Branch line was not regrounded to main"
grep -q 'the strand plan' "$tmp/repo/task_plan.md" || fail "reground must rewrite ONE line, not the file"
grep -q 'reground=changed' <<<"$rout" || fail "expected reground=changed, got: $rout"

rout2="$(cbr_reground_plan_branch "$tmp/repo/task_plan.md" main)" || fail "reground must be idempotent"
grep -q 'reground=unchanged' <<<"$rout2" || fail "expected reground=unchanged on the second run, got: $rout2"

rout3="$(cbr_reground_plan_branch "$tmp/repo/no-such-plan.md" main)" || fail "a missing plan must not fail closeout"
grep -q 'reground=absent' <<<"$rout3" || fail "expected reground=absent for a missing plan, got: $rout3"

# A Branch line may carry trailing prose — a worktree path, a base note. An
# implementation that rewrote the WHOLE line would still satisfy the assertions
# above, so the trailing text needs its own fixture or the claim is vacuous.
printf '# plan\n\n**Branch:** stream/recorded · base: main (worktree ../elsewhere)\n' > "$tmp/trailing.md"
rout4="$(cbr_reground_plan_branch "$tmp/trailing.md" main)" || fail "reground failed on a Branch line with trailing text: $rout4"
grep -q '^\*\*Branch:\*\* main · base: main (worktree \.\./elsewhere)$' "$tmp/trailing.md" \
  || fail "reground must swap the branch TOKEN and leave the rest of the line alone; got: $(sed -n '3p' "$tmp/trailing.md")"

# ---- case 4: a marker's first line identifies the strand that wrote it ----
printf 'stream/sibling — COMPLETE 2026-08-19\n\nbody\n' > "$tmp/foreign.marker"
printf 'stream/mine — COMPLETE 2026-08-19\n\nbody\n'    > "$tmp/mine.marker"
printf 's6-tdd-approve — DONE (2026-07-07)\n\nbody\n'   > "$tmp/legacy.marker"

[ "$(cbr_marker_branch "$tmp/foreign.marker")" = "stream/sibling" ] \
  || fail "cbr_marker_branch did not read the branch from the marker's first line"
[ -z "$(cbr_marker_branch "$tmp/legacy.marker")" ] \
  || fail "a marker naming no branch must yield an empty branch, not a guess"
[ -z "$(cbr_marker_branch "$tmp/absent.marker")" ] \
  || fail "a missing marker must yield an empty branch"

cbr_marker_is_foreign "$tmp/foreign.marker" stream/mine \
  || fail "a marker naming another branch must be judged foreign"
cbr_marker_is_foreign "$tmp/mine.marker" stream/mine \
  && fail "a marker naming THIS branch must not be judged foreign"
# Conservative direction: only a PROVEN mismatch is foreign. Markers predating
# the naming convention carry no branch, and treating them as foreign would
# silently stop the completion signal from ever firing.
cbr_marker_is_foreign "$tmp/legacy.marker" stream/mine \
  && fail "a marker naming no branch must NOT be judged foreign (older markers predate the convention)"
cbr_marker_is_foreign "$tmp/absent.marker" stream/mine \
  && fail "a missing marker must not be judged foreign — there is nothing to disown"

# ---- case 5: liveness is a process's cwd, no session registry involved ----
mkdir -p "$tmp/idle" "$tmp/busy/sub/deeper"
# stdio to /dev/null: a background child inheriting this script's stdout holds
# the caller's pipe open until it dies, which would stall a pre-commit hook.
( cd "$tmp/busy/sub/deeper" && exec sleep 60 ) >/dev/null 2>&1 &
sleeper=$!
sleep 1   # let the kernel register the child's cwd before lsof reads it

cwds="$(cbr_live_cwds)"
if command -v lsof >/dev/null 2>&1; then
  cbr_path_has_live_process "$tmp/busy" "$cwds" \
    || fail "a process rooted in a SUBDIRECTORY must count as living in the folder"
  cbr_path_has_live_process "$tmp/idle" "$cwds" \
    && fail "an idle folder must not report a live process"
else
  echo "strand-lib.test: lsof absent — liveness case skipped (cannot prove absence of life)"
fi

# A TOOL THAT EXISTS AND FAILS is the same state as one that is missing. The
# pipeline `lsof | sed` reports SED's status, and sed succeeds beautifully on no
# input, so a broken lsof — a wrapper, an alternate build that rejects these
# flags, a hardened host — used to come back as a clean, empty answer: "nobody is
# anywhere", the answer that authorises a reap.
mkdir -p "$tmp/brokenbin"
cat > "$tmp/brokenbin/lsof" <<'SH'
#!/usr/bin/env bash
echo "lsof: WARNING: cannot open the process table" >&2
exit 1
SH
chmod +x "$tmp/brokenbin/lsof"
set +e
( PATH="$tmp/brokenbin:$PATH"; cbr_live_cwds >/dev/null 2>&1 )
brc=$?
( PATH="$tmp/brokenbin:$PATH"; cbr_path_has_live_process "$tmp/busy" >/dev/null 2>&1 )
bprc=$?
set -e
[ "$brc" -eq 2 ] \
  || fail "an lsof that exists and FAILS returned $brc, not 2 — a broken tool is 'could not look', and anything else lets it answer 'nobody is there'"
[ "$bprc" -eq 2 ] \
  || fail "with a broken lsof the occupancy predicate answered $bprc for a folder that demonstrably has a process in it — this is the reap-authorising direction"

# A path that exists but cannot be entered is also a question this predicate did
# not get to ask; only a path that does not exist holds nobody for certain.
mkdir -p "$tmp/sealed/inner"
chmod 000 "$tmp/sealed"
set +e
cbr_path_has_live_process "$tmp/sealed/inner" >/dev/null 2>&1
srrc=$?
set -e
chmod 755 "$tmp/sealed"
[ "$srrc" -eq 2 ] \
  || fail "a path that cannot be entered answered $srrc rather than 2 — 'I could not look in there' must not read as 'nobody is in there'"

# ---- case 6: merged-ness is a git fact ----
cbr_branch_is_merged "$tmp/repo" stream/recorded main || fail "a merged branch must read as merged"
$git branch -q stream/unmerged
$git checkout -q stream/unmerged
echo more > "$tmp/repo/g.txt"; $git add -A && $git commit -qm 'unmerged work'
$git checkout -q main
cbr_branch_is_merged "$tmp/repo" stream/unmerged main && fail "an unmerged branch must not read as merged"

# ---- case 7: a record that exists but cannot be written FAILS THE CLOSEOUT ----
# The whole point of this library is that a strand's records are not lost
# quietly. A skipped-and-counted-anyway write would reproduce, inside the fix,
# the exact class of bug the fix exists to remove.
ro="$tmp/readonly"
mkdir -p "$ro"
chmod 500 "$ro"
if [ -w "$ro" ]; then
  echo "strand-lib.test: running as a user who ignores directory permissions — unwritable-archive case skipped"
else
  if out3="$(cbr_archive_strand_records "$tmp/repo" stream/recorded "$ro/dest" task_plan.md 2>&1)"; then
    fail "archiving into an unwritable destination must fail, not report success: $out3"
  fi
fi
chmod 700 "$ro"

# A destination that is already a DIRECTORY must fail, not be quietly swallowed:
# `mv` would drop the record INSIDE it and report success, leaving the archive
# path a directory while the count claimed a saved record.
mkdir -p "$tmp/repo/archive/dirslot/task_plan.md"
if outdir="$(cbr_archive_strand_records "$tmp/repo" stream/recorded "$tmp/repo/archive/dirslot" task_plan.md 2>&1)"; then
  fail "archiving onto a directory destination must fail, not report success: $outdir"
fi
[ -d "$tmp/repo/archive/dirslot/task_plan.md" ] || fail "the directory destination should have been left alone"
[ -e "$tmp/repo/archive/dirslot/task_plan.md/task_plan.md.cbr-part" ] \
  && fail "the record was moved INSIDE the directory — the rename was not rejected"

# A git INSPECTION failure is not an absent record. cat-file exits 1 for "not in
# that tree" and something else entirely when git cannot answer, and folding the
# second into the first is how an unreadable repository reports a successful
# archive of nothing.
cp -R "$tmp/repo" "$tmp/broken"
chmod -R 000 "$tmp/broken/.git/objects" 2>/dev/null || true
if git -C "$tmp/broken" cat-file -e stream/recorded:task_plan.md 2>/dev/null; then
  echo "strand-lib.test: object store still readable (permissions ignored for this user) — git-inspection-failure case skipped"
else
  if outbroken="$(cbr_archive_strand_records "$tmp/broken" stream/recorded "$tmp/broken/archive/out" task_plan.md 2>&1)"; then
    fail "a repository git cannot read must fail the archive, not report archived=0 success: $outbroken"
  fi
fi
chmod -R 700 "$tmp/broken/.git/objects" 2>/dev/null || true

# ---- case 7b: the destination must be a real path inside the repository ----
# Guarding the destination alone is not enough: a symlink ANYWHERE above it
# redirects mkdir, mktemp and mv alike, and the closeout then stages a directory
# holding none of the bytes it wrote.
mkdir -p "$tmp/outside/loot"
ln -s "$tmp/outside" "$tmp/repo/archive/via-link"
if outesc="$(cbr_archive_strand_records "$tmp/repo" stream/recorded "$tmp/repo/archive/via-link/loot" task_plan.md 2>&1)"; then
  fail "records were archived through a symlinked ANCESTOR: $outesc"
fi
[ -e "$tmp/outside/loot/task_plan.md" ] \
  && fail "a record was written outside the repository, through a symlinked archive parent"

mkdir -p "$tmp/repo/archive/real"
if outdd="$(cbr_archive_strand_records "$tmp/repo" stream/recorded "$tmp/repo/archive/real/../../../escape" task_plan.md 2>&1)"; then
  fail "a destination that climbs out of the repository with .. was accepted: $outdd"
fi

# The containment rule must not reject an ordinary nested archive path, or it
# would refuse every real closeout.
outok="$(cbr_archive_strand_records "$tmp/repo" stream/recorded "$tmp/repo/docs/streams/archive/recorded" task_plan.md)" \
  || fail "an ordinary in-repo archive path was rejected: $outok"
[ -f "$tmp/repo/docs/streams/archive/recorded/task_plan.md" ] \
  || fail "the ordinary in-repo archive did not receive the record"

# ---- case 8: staging reports honestly ----
printf 'archived plan\n' > "$tmp/repo/staged-new.txt"
sout="$(cbr_stage_paths "$tmp/repo" staged-new.txt)" || fail "staging an existing file must succeed: $sout"
grep -q 'staged=1' <<<"$sout" || fail "expected staged=1, got: $sout"
$git diff --cached --name-only | grep -qx 'staged-new.txt' || fail "staged-new.txt was not actually staged"

# A DELETION is work too: `add -A <path>` must record a removal, or the closeout
# commit silently keeps a file the ritual removed.
$git commit -qm 'land staged file'
rm -f "$tmp/repo/staged-new.txt"
dout="$(cbr_stage_paths "$tmp/repo" staged-new.txt)" || fail "staging a deletion must succeed: $dout"
grep -q 'staged=1' <<<"$dout" || fail "expected staged=1 for a deletion, got: $dout"
$git diff --cached --name-only | grep -qx 'staged-new.txt' || fail "the deletion was not staged"
$git commit -qm 'land the deletion'

# A path git cannot stage is a failure the caller must see.
if sbad="$(cbr_stage_paths "$tmp/repo" "$tmp/outside-the-repo.txt" 2>&1)"; then
  fail "staging a path outside the repository must fail, not report success: $sbad"
fi

echo "strand-lib.test PASS (archive-from-commit, marker removal, reground, marker identity, liveness, merged-ness, honest failure)"
