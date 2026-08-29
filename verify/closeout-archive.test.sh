#!/usr/bin/env bash
# Regression for the three duties closeout owes the base branch
# (skills/cbr-core/build-loop.md step 9) and for BOTH leaves being wired to the
# one shared implementation of them.
#
# Two halves, deliberately:
#
#   BEHAVIOUR — cbr_closeout_base_duties is exercised end to end against a
#   scratch repo in the exact post-merge state that defeated the old archivers.
#   This is where the duties are actually proven.
#
#   WIRING — each leaf's closeout is asserted to source the shared library and
#   call that function, and to no longer carry its own private archiver. A
#   passing behaviour half means nothing if a leaf still runs its own copy;
#   that is precisely how one leaf shipped law the other did not.
#
# Hermetic: everything happens in a scratch repo; the real repo is untouched.
set -euo pipefail

# pre-commit exports GIT_DIR/GIT_INDEX_FILE/GIT_WORK_TREE to hook processes;
# inherited, the fixture's git calls would operate on the HOST repo's index.
for v in $(env | sed -n 's/^\(GIT_[A-Z_]*\)=.*/\1/p'); do unset "$v"; done

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
kit="$(cd "$here/.." && pwd)"

# Test the CANONICAL sources when we are in the source repo (kit/ is a build
# artifact of it); fall back to the kit's own mirrors so a port can run this too.
lib="$root/skills/cbr-core/scripts/strand-lib.sh"
claude_leaf="$root/skills/claude-controlled-build-run/scripts/cbr.sh"
codex_leaf="$root/skills/codex-controlled-build-run/scripts/cbr-codex.sh"
[ -f "$lib" ]         || lib="$kit/skill/claude-controlled-build-run/references/core/scripts/strand-lib.sh"
[ -f "$claude_leaf" ] || claude_leaf="$kit/skill/claude-controlled-build-run/scripts/cbr.sh"
[ -f "$codex_leaf" ]  || codex_leaf="$kit/skill/codex-controlled-build-run/scripts/cbr-codex.sh"

tmp="$(cd "$(mktemp -d)" && pwd -P)"
cleanup() {
  local rc=$?
  [ -n "${occ_sleeper:-}" ] && { kill "$occ_sleeper" 2>/dev/null || true; wait "$occ_sleeper" 2>/dev/null || true; }
  rm -rf "$tmp"
  exit "$rc"
}
trap cleanup EXIT
fail() { echo "closeout-archive.test FAIL: $1" >&2; exit 1; }

for f in "$lib" "$claude_leaf" "$codex_leaf"; do
  [ -f "$f" ] || fail "missing input: $f"
done
# shellcheck source=/dev/null
. "$lib"

command -v cbr_closeout_base_duties >/dev/null \
  || fail "the shared library has no cbr_closeout_base_duties — the three base-branch duties have no single implementation for both leaves to call"

# ---------------------------------------------------------------------------
# BEHAVIOUR — the post-merge state, exactly as it happens
# ---------------------------------------------------------------------------
git="git -C $tmp/repo -c user.email=t@t -c user.name=t"
mkdir -p "$tmp/repo"
git -C "$tmp/repo" init -q -b main
printf '# task_plan.md\n\n**Branch:** main\n\nbase plan\n' > "$tmp/repo/task_plan.md"
echo base > "$tmp/repo/f.txt"
$git add -A && $git commit -qm base

$git checkout -q -b stream/dogfood
printf '# task_plan.md\n\n**Branch:** stream/dogfood\n\nthe strand plan\n' > "$tmp/repo/task_plan.md"
printf 'the strand progress log\n' > "$tmp/repo/progress.md"
printf 'the strand findings\n'     > "$tmp/repo/findings.md"
printf 'stream/dogfood — COMPLETE 2026-08-19\n\nall phases green\n' > "$tmp/repo/DONE.marker"
echo work > "$tmp/repo/f.txt"
$git add -A && $git commit -qm 'strand work + records'
$git checkout -q main
$git merge -q --no-ff -m 'merge the strand' stream/dogfood

# This is the state the duties must handle: the merge has put the strand's plan,
# its records AND its completion marker onto main, and main's root plan now
# names a branch that is about to be deleted.
[ -f "$tmp/repo/DONE.marker" ] || fail "fixture wrong: the merge should have carried DONE.marker onto main"
grep -q '^\*\*Branch:\*\* stream/dogfood' "$tmp/repo/task_plan.md" \
  || fail "fixture wrong: the merge should have left the strand's Branch line on main"

arch="$tmp/repo/docs/streams/archive/dogfood"
out="$(cbr_closeout_base_duties "$tmp/repo" stream/dogfood main "$arch" DONE.marker task_plan.md \
        task_plan.md progress.md findings.md DONE.marker)" \
  || fail "cbr_closeout_base_duties returned non-zero on a clean closeout: $out"

# Duty 1 — the records come out of the strand's final COMMIT.
for f in task_plan.md progress.md findings.md DONE.marker; do
  [ -f "$arch/$f" ] || fail "duty 1: archive is missing $f"
done
grep -q 'the strand plan'         "$arch/task_plan.md" || fail "duty 1: archived plan is not the strand's version"
grep -q 'the strand progress log' "$arch/progress.md"  || fail "duty 1: archived progress log is not the strand's version"
grep -q 'the strand findings'     "$arch/findings.md"  || fail "duty 1: archived findings are not the strand's version"
grep -q 'stream/dogfood'          "$arch/DONE.marker"  || fail "duty 1: archived marker is not the strand's version"

# Duty 2 — the marker does not survive on the base.
[ -e "$tmp/repo/DONE.marker" ] && fail "duty 2: DONE.marker still sits on the base branch"

# Duty 3 — the base's plan names the base again, and nothing else moved.
grep -q '^\*\*Branch:\*\* main$' "$tmp/repo/task_plan.md" \
  || fail "duty 3: the base plan still does not name the base branch"
grep -q 'the strand plan' "$tmp/repo/task_plan.md" \
  || fail "duty 3: reground rewrote more than the Branch line"

# All of it is STAGED, so it rides the closeout commit as one deliberate act
# instead of turning up later as debris in git status.
staged="$($git diff --cached --name-only)"
grep -qx 'task_plan.md' <<<"$staged" || fail "the reground was not staged"
grep -q  'docs/streams/archive/dogfood/progress.md' <<<"$staged" || fail "the archive was not staged"
# The marker's removal is asserted against the INDEX, not against a diff name
# list: the archived copy is byte-identical to the removed original, so git
# reports the pair as a RENAME and `--name-only` prints only the destination.
# What actually matters is that the base's staged tree no longer carries the
# marker at its root, and that survives however git chooses to describe it.
[ -z "$($git ls-files -- DONE.marker)" ] \
  || fail "the marker is still in the base's staged tree — the next strand would inherit it by merge"

grep -q 'archived=4'      <<<"$out" || fail "expected archived=4 in the summary, got: $out"
grep -q 'marker=removed'  <<<"$out" || fail "expected marker=removed in the summary, got: $out"
grep -q 'reground=changed' <<<"$out" || fail "expected reground=changed in the summary, got: $out"

# Idempotent: a re-run after the closeout commit is a clean no-op, because a
# ritual that only works once is a ritual nobody dares re-run.
$git commit -qm 'closeout'
out2="$(cbr_closeout_base_duties "$tmp/repo" stream/dogfood main "$arch" DONE.marker task_plan.md \
          task_plan.md progress.md findings.md DONE.marker)" \
  || fail "a second run of the duties must be a clean no-op: $out2"
grep -q 'marker=absent'     <<<"$out2" || fail "expected marker=absent on the second run, got: $out2"
grep -q 'reground=unchanged' <<<"$out2" || fail "expected reground=unchanged on the second run, got: $out2"

# ---------------------------------------------------------------------------
# FAIL-CLOSED — a failed archive leaves the base untouched, and invites a retry
# ---------------------------------------------------------------------------
# The duties run moments before the branch is deleted. If archival fails and the
# ritual carries on anyway, it removes the completion marker and regrounds the
# plan on behalf of an archive that does not exist — destroying the records it
# was there to save. The order is the safety property, so it is tested.
mkdir -p "$tmp/repo2"
git -C "$tmp/repo2" init -q -b main
printf '# task_plan.md\n\n**Branch:** stream/doomed\n' > "$tmp/repo2/task_plan.md"
printf 'stream/doomed — COMPLETE\n' > "$tmp/repo2/DONE.marker"
git2="git -C $tmp/repo2 -c user.email=t@t -c user.name=t"
$git2 add -A && $git2 commit -qm base
$git2 branch stream/doomed

# An unwritable parent is the cheapest honest way to make archival fail.
mkdir -p "$tmp/repo2/ro"; chmod 500 "$tmp/repo2/ro"
bad="$tmp/repo2/ro/archive"

set +e
out3="$(cbr_closeout_base_duties "$tmp/repo2" stream/doomed main "$bad" DONE.marker task_plan.md \
          task_plan.md DONE.marker 2>/dev/null)"
rc3=$?
set -e
chmod 700 "$tmp/repo2/ro"

[ "$rc3" -ne 0 ] || fail "the duties reported success even though archival failed"
[ -f "$tmp/repo2/DONE.marker" ] \
  || fail "fail-closed: the marker was removed from the base after archival FAILED — the records are gone and the marker with them"
grep -q '^\*\*Branch:\*\* stream/doomed' "$tmp/repo2/task_plan.md" \
  || fail "fail-closed: the base plan was regrounded after archival FAILED — the base was mutated for an archive that does not exist"
[ -z "$($git2 diff --cached --name-only)" ] \
  || fail "fail-closed: a failed closeout staged changes — a half-done ritual must not be committable by accident"
grep -q 'marker=skipped' <<<"$out3" \
  || fail "the summary must say the later duties were SKIPPED, not report them as done: $out3"

# And the retry it invites must work: same repo, same slug, a writable dest.
out4="$(cbr_closeout_base_duties "$tmp/repo2" stream/doomed main "$tmp/repo2/docs/streams/archive/doomed" \
          DONE.marker task_plan.md task_plan.md DONE.marker)" \
  || fail "closeout could not be re-run after a failed attempt: $out4"
[ -f "$tmp/repo2/docs/streams/archive/doomed/DONE.marker" ] \
  || fail "the retry did not archive the marker"
[ -e "$tmp/repo2/DONE.marker" ] && fail "the retry did not remove the marker from the base"
grep -q 'marker=removed' <<<"$out4" || fail "expected marker=removed on the retry, got: $out4"

# ---------------------------------------------------------------------------
# INHERITED RECORDS ARE NOT THE STRAND'S — THE ARCHIVE SKIPS THEM
# ---------------------------------------------------------------------------
# A worktree provisioned from a base that already carried ANOTHER strand's root
# records ends with those records sitting, byte-identical, in its own final
# commit. Archiving them stamps someone else's paperwork with this strand's
# name — RoboRev 3782 caught exactly that in two real archives. The rule: a
# candidate record whose bytes are unchanged since the strand's fork point was
# never this strand's work, so it stays out of the picture.
mkdir -p "$tmp/repo3"
git3="git -C $tmp/repo3 -c user.email=t@t -c user.name=t"
git -C "$tmp/repo3" init -q -b main
printf '# STATUS — stream: anim-junk\n\nleft behind by an older run\n' > "$tmp/repo3/STATUS.md"
printf '# limits — stream: anim-junk\n' > "$tmp/repo3/KNOWN-LIMITATIONS.md"
printf '# task_plan.md\n\n**Branch:** main\n\nbase plan\n' > "$tmp/repo3/task_plan.md"
$git3 add -A && $git3 commit -qm 'base carrying an older strand debris'

$git3 checkout -q -b stream/heir
printf '# task_plan.md\n\n**Branch:** stream/heir\n\nthe heir plan\n' > "$tmp/repo3/task_plan.md"
printf 'the heir progress log\n' > "$tmp/repo3/progress.md"
printf 'stream/heir — COMPLETE\n' > "$tmp/repo3/DONE.marker"
$git3 add -A && $git3 commit -qm 'heir work + records'
$git3 checkout -q main
$git3 merge -q --no-ff -m 'merge the heir' stream/heir

arch3="$tmp/repo3/docs/streams/archive/heir"
out5="$(cbr_closeout_base_duties "$tmp/repo3" stream/heir main "$arch3" DONE.marker task_plan.md \
         task_plan.md progress.md STATUS.md KNOWN-LIMITATIONS.md DONE.marker)" \
  || fail "duties failed on the inherited-junk fixture: $out5"
for f in task_plan.md progress.md DONE.marker; do
  [ -f "$arch3/$f" ] || fail "inherited-junk: the strand's own $f is missing from the archive"
done
[ -e "$arch3/STATUS.md" ] \
  && fail "inherited-junk: STATUS.md unchanged since the fork point belongs to an older strand and must not be archived as this one's"
[ -e "$arch3/KNOWN-LIMITATIONS.md" ] \
  && fail "inherited-junk: KNOWN-LIMITATIONS.md unchanged since the fork point must not be archived"
grep -q 'archived=3' <<<"$out5" \
  || fail "inherited-junk: archived= must count only the strand's own records, got: $out5"

# The filter is provenance, not a blocklist: the same filename authored BY the
# strand is its record and must still be saved.
$git3 commit -qm 'closeout heir'
$git3 checkout -q -b stream/heir2
printf '# STATUS — stream: heir2\n\nwritten by this very strand\n' > "$tmp/repo3/STATUS.md"
$git3 add -A && $git3 commit -qm 'heir2 rewrites STATUS'
$git3 checkout -q main
$git3 merge -q --no-ff -m 'merge heir2' stream/heir2
out6="$(cbr_closeout_base_duties "$tmp/repo3" stream/heir2 main "$tmp/repo3/docs/streams/archive/heir2" \
         DONE.marker task_plan.md STATUS.md)" \
  || fail "duties failed on the strand-authored STATUS fixture: $out6"
grep -q 'stream: heir2' "$tmp/repo3/docs/streams/archive/heir2/STATUS.md" 2>/dev/null \
  || fail "a STATUS.md the strand itself rewrote is its record and must be archived"

# A record-only commit landed on the branch AFTER its merge (the closeout paths
# permit this) moves the tip past every merge's second parent. The fork finder
# must still recognize the merge — an exact-tip match falls through to a
# merge-base that IS the merged tip, and the strand's real pre-merge records
# get miscalled "inherited" and dropped (RoboRev 3785).
$git3 commit -qm 'closeout heir2'
$git3 checkout -q -b stream/heir3
printf '# STATUS — stream: heir3\n\nauthored before the merge\n' > "$tmp/repo3/STATUS.md"
printf 'heir3 progress\n' > "$tmp/repo3/progress.md"
$git3 add -A && $git3 commit -qm 'heir3 records'
$git3 checkout -q main
$git3 merge -q --no-ff -m 'merge heir3' stream/heir3
$git3 checkout -q stream/heir3
printf 'heir3 progress\npost-merge closeout note\n' > "$tmp/repo3/progress.md"
$git3 add -A && $git3 commit -qm 'heir3 post-merge record-only commit'
$git3 checkout -q main
out7="$(cbr_closeout_base_duties "$tmp/repo3" stream/heir3 main "$tmp/repo3/docs/streams/archive/heir3" \
         DONE.marker task_plan.md STATUS.md progress.md KNOWN-LIMITATIONS.md)" \
  || fail "duties failed on the post-merge-commit fixture: $out7"
grep -q 'stream: heir3' "$tmp/repo3/docs/streams/archive/heir3/STATUS.md" 2>/dev/null \
  || fail "post-merge commit on the branch must not shrink the archive: pre-merge STATUS.md dropped"
grep -q 'post-merge closeout note' "$tmp/repo3/docs/streams/archive/heir3/progress.md" 2>/dev/null \
  || fail "post-merge commit: the tip's own progress.md must be what gets archived"
[ -e "$tmp/repo3/docs/streams/archive/heir3/KNOWN-LIMITATIONS.md" ] \
  && fail "post-merge commit: inherited KNOWN-LIMITATIONS.md must still be excluded"

# And a SECOND merge of the same strand (merge → record-only commit → merge
# again) must not either: a fork finder that latches the newest integration
# calls everything before the FIRST merge inherited (RoboRev 3792).
$git3 commit -qm 'closeout heir3'
$git3 merge -q --no-ff -m 'merge heir3 again' stream/heir3
out8="$(cbr_closeout_base_duties "$tmp/repo3" stream/heir3 main "$tmp/repo3/docs/streams/archive/heir3-again" \
         DONE.marker task_plan.md STATUS.md progress.md KNOWN-LIMITATIONS.md)" \
  || fail "duties failed on the twice-merged fixture: $out8"
grep -q 'stream: heir3' "$tmp/repo3/docs/streams/archive/heir3-again/STATUS.md" 2>/dev/null \
  || fail "twice-merged strand: records authored before its FIRST merge must still archive"
[ -e "$tmp/repo3/docs/streams/archive/heir3-again/KNOWN-LIMITATIONS.md" ] \
  && fail "twice-merged strand: inherited KNOWN-LIMITATIONS.md must still be excluded"

# When NO fork point can be established (disjoint histories — the walk finds
# no shared first-parent commit), provenance is unknown, and unknown must
# widen the archive: the filter disables and every candidate is saved. A
# finder that "helpfully" guesses a commit here can guess the merged tip and
# silently drop everything (RoboRev 3795).
$git3 commit -qm 'closeout heir3-again'
$git3 checkout -q --orphan stream/orphan
git -C "$tmp/repo3" rm -rqf . 2>/dev/null || true
printf '# task_plan.md\n\n**Branch:** stream/orphan\n\norphan plan\n' > "$tmp/repo3/task_plan.md"
printf 'orphan progress\n' > "$tmp/repo3/progress.md"
$git3 add -A && $git3 commit -qm 'orphan records'
$git3 checkout -q main
$git3 merge -q --no-ff --allow-unrelated-histories -X theirs -m 'merge orphan' stream/orphan >/dev/null 2>&1
cbr_strand_fork_point "$tmp/repo3" stream/orphan main >/dev/null 2>&1 \
  && fail "disjoint histories: fork-point finder must return failure, not a guess"
out9="$(cbr_closeout_base_duties "$tmp/repo3" stream/orphan main "$tmp/repo3/docs/streams/archive/orphan" \
         DONE.marker task_plan.md task_plan.md progress.md)" \
  || fail "duties failed on the disjoint-history fixture: $out9"
for f in task_plan.md progress.md; do
  [ -f "$tmp/repo3/docs/streams/archive/orphan/$f" ] \
    || fail "unknown fork point must archive UNFILTERED — $f was dropped"
done

# ---------------------------------------------------------------------------
# THE ARCHIVE IS ONE STRAND'S PICTURE, AND THE EXTRA RECORD FAILS LOUDLY
# ---------------------------------------------------------------------------
# Provenance: an archive directory is a retry only if it can be shown to be an
# interrupted attempt at archiving THIS run. Identity is the strand's final
# commit — see the namesake case below for why a name will not do.
prov="$tmp/prov"
mkdir -p "$prov"
sha="$($git rev-parse stream/dogfood)"
printf '%s\nstream/dogfood\n' "$sha" > "$prov/.cbr-archive-of"
cbr_archive_is_retry_of "$prov" "$tmp/repo" stream/dogfood \
  || fail "an archive stamped with this strand's own final commit is an interrupted retry and must be reusable"

printf '%s\nstream/dogfood\n' "2222222222222222222222222222222222222222" > "$prov/.cbr-archive-of"
cbr_archive_is_retry_of "$prov" "$tmp/repo" stream/dogfood \
  && fail "an archive stamped with a different commit was accepted as this run's retry"

: > "$prov/.cbr-archive-of"
cbr_archive_is_retry_of "$prov" "$tmp/repo" stream/dogfood \
  && fail "an empty provenance stamp proved nothing and was accepted anyway"

cbr_archive_is_retry_of "$tmp/never-existed" "$tmp/repo" stream/dogfood \
  && fail "a non-existent archive is not a retry"

# The predicate refuses a symlink on its own account, not only because the
# composite happens to check first — it is called from more than one place.
printf '%s\nstream/dogfood\n' "$sha" > "$prov/.cbr-archive-of"
ln -s "$prov" "$tmp/prov-link"
cbr_archive_is_retry_of "$tmp/prov-link" "$tmp/repo" stream/dogfood \
  && fail "a symlinked archive was accepted as a retry — following it writes records outside the path the closeout was given"

# Every write into an archive lands on a path an earlier run could have left
# debris on. A symlink there turns a write INTO the archive into a write
# somewhere else, so no redirect goes straight onto a predictable name.
printf 'do not clobber me\n' > "$tmp/outside-target"
# The decoy holds the RIGHT sha, so only the symlink itself can disqualify it —
# otherwise this assertion would pass for the boring reason that the target's
# contents happen not to look like a commit.
printf '%s\nstream/dogfood\n' "$sha" > "$tmp/decoy-stamp"
ln -sf "$tmp/decoy-stamp" "$prov/$CBR_ARCHIVE_STAMP"
cbr_archive_is_retry_of "$prov" "$tmp/repo" stream/dogfood \
  && fail "a symlinked provenance stamp was read as proof — that is 'prove this is mine' answered by a file of somebody else's choosing"
ln -sf "$tmp/outside-target" "$prov/$CBR_ARCHIVE_STAMP"
cbr_archive_stamp "$prov" "$tmp/repo" stream/dogfood \
  || fail "stamping over a symlinked stamp failed outright"
grep -q 'do not clobber me' "$tmp/outside-target" \
  || fail "stamping followed the symlink and overwrote a file outside the archive"
[ -L "$prov/$CBR_ARCHIVE_STAMP" ] \
  && fail "the stamp is still a symlink — the next write follows it again"

slots="$tmp/repo/docs/streams/archive/slots"
mkdir -p "$slots"
ln -sf "$tmp/outside-target" "$slots/task_plan.md.cbr-part"
ln -sf "$tmp/outside-target" "$slots/progress.md"
out8="$(cbr_archive_strand_records "$tmp/repo" stream/dogfood "$slots" task_plan.md progress.md)" \
  || fail "archival failed against an archive seeded with symlinks: $out8"
grep -q 'do not clobber me' "$tmp/outside-target" \
  || fail "a record was written through a stale .cbr-part symlink, outside the archive"
[ -L "$slots/progress.md" ] \
  && fail "an archived record is a symlink — the archive must hold the bytes, not a pointer to them"
grep -q 'the strand progress log' "$slots/progress.md" \
  || fail "the record that replaced the symlink is not the strand's own"

# The guard lives in the composite, so BOTH leaves inherit it — an archive that
# names another strand stops the closeout with the base untouched.
foreign="$tmp/repo/docs/streams/archive/foreign"
mkdir -p "$foreign"
printf 'stream/someone-else — COMPLETE 2026-03-01\n' > "$foreign/DONE.marker"
printf '%s\nstream/someone-else\n' "0000000000000000000000000000000000000000" > "$foreign/.cbr-archive-of"
set +e
out6="$(cbr_closeout_base_duties "$tmp/repo" stream/dogfood main "$foreign" DONE.marker task_plan.md \
          task_plan.md 2>/dev/null)"
rc8=$?
set -e
[ "$rc8" -ne 0 ] || fail "the duties wrote into an archive belonging to another run"
grep -q 'stream/someone-else' "$foreign/DONE.marker" \
  || fail "another strand's archived marker was overwritten — those records are its only copy"
grep -q 'marker=skipped' <<<"$out6" || fail "a refused archive must skip the later duties, got: $out6"

# The branch NAME is not provenance. Slugs are reused, and `stream/<slug>` comes
# back with them, so an archive of a strand that held this branch name months
# ago must still be refused — it is a different run, and its records are its
# only copy.
namesake="$tmp/repo/docs/streams/archive/namesake"
mkdir -p "$namesake"
printf 'stream/dogfood — COMPLETE 2026-03-01\n' > "$namesake/DONE.marker"
printf '%s\nstream/dogfood\n' "1111111111111111111111111111111111111111" > "$namesake/.cbr-archive-of"
set +e
cbr_archive_is_retry_of "$namesake" "$tmp/repo" stream/dogfood
rc10=$?
set -e
[ "$rc10" -ne 0 ] \
  || fail "an archive of an EARLIER strand on the same branch name was accepted as this run's retry — a name is not provenance"

# An archive with no stamp at all cannot prove anything, and unprovable is no.
unstamped="$tmp/repo/docs/streams/archive/unstamped"
mkdir -p "$unstamped"
printf 'stream/dogfood — COMPLETE\n' > "$unstamped/DONE.marker"
cbr_archive_is_retry_of "$unstamped" "$tmp/repo" stream/dogfood \
  && fail "an archive carrying no provenance stamp was assumed to be ours"

# A symlink is never the archive: following one writes records somewhere else
# and stages a directory holding none of them. Live and dangling alike.
mkdir -p "$tmp/elsewhere"
ln -s "$tmp/elsewhere" "$tmp/repo/docs/streams/archive/link-live"
ln -s "$tmp/nothing-here" "$tmp/repo/docs/streams/archive/link-dead"
for l in link-live link-dead; do
  set +e
  outl="$(cbr_closeout_base_duties "$tmp/repo" stream/dogfood main "$tmp/repo/docs/streams/archive/$l" \
            DONE.marker task_plan.md task_plan.md 2>/dev/null)"
  rcl=$?
  set -e
  [ "$rcl" -ne 0 ] || fail "the duties accepted a symlinked archive destination ($l)"
  grep -q 'marker=skipped' <<<"$outl" || fail "a refused symlink destination must skip the later duties, got: $outl"
done
[ -e "$tmp/elsewhere/task_plan.md" ] \
  && fail "records were written through a symlink, outside the archive path the closeout was given"

# Stale slots: a record the strand never wrote must not survive in the archive
# from an earlier run, or `archived=` describes one strand and the directory
# holds two. Every kind of entry counts — a dangling symlink is exactly what an
# interrupted run leaves behind, and it answers `-f` and `-e` with no.
printf 'left over from an older strand\n' > "$arch/STATUS.md"
ln -s "$tmp/gone" "$arch/ASK-ORCH.md"
out5="$(cbr_closeout_base_duties "$tmp/repo" stream/dogfood main "$arch" DONE.marker task_plan.md \
          task_plan.md progress.md findings.md STATUS.md ASK-ORCH.md)" \
  || fail "the duties failed while clearing a stale slot: $out5"
[ -e "$arch/STATUS.md" ] \
  && fail "a STATUS.md the strand never wrote survived in the archive — the archive is now a blend of two runs"
{ [ -e "$arch/ASK-ORCH.md" ] || [ -L "$arch/ASK-ORCH.md" ]; } \
  && fail "a dangling symlink left by an earlier run survived in the archive"

# A DIRECTORY sitting in the slot of a record the strand never wrote is not
# debris to delete on the strand's behalf: it fails closed for a human to look
# at, rather than being silently rm -rf'd during a reap.
mkdir -p "$arch/KNOWN-LIMITATIONS.md"
set +e
out7="$(cbr_closeout_base_duties "$tmp/repo" stream/dogfood main "$arch" DONE.marker task_plan.md \
          task_plan.md KNOWN-LIMITATIONS.md 2>/dev/null)"
rc9=$?
set -e
[ "$rc9" -ne 0 ] \
  || fail "a directory blocking a record slot was reported as a clean archive: $out7"
[ -d "$arch/KNOWN-LIMITATIONS.md" ] \
  || fail "a directory in a record slot was deleted — that is a human's call, not the archiver's"
rmdir "$arch/KNOWN-LIMITATIONS.md"

# The extra record: both halves fail loudly, because the caller reaps the source.
digest_src="$tmp/repo/.cbr-watch/dogfood.commits"
mkdir -p "$(dirname "$digest_src")"
printf 'abc1234 2026-08-19 first\n' > "$digest_src"

cbr_archive_extra_record "$digest_src" "$arch" "$tmp/repo" docs/streams/archive/dogfood >/dev/null \
  || fail "archiving the watch digest failed on the happy path"
[ -f "$arch/dogfood.commits" ] || fail "the watch digest was not archived"
$git diff --cached --name-only | grep -q 'dogfood.commits' \
  || fail "the watch digest was archived but never staged — it would surface later as debris"

mkdir -p "$tmp/repo/ro2"; chmod 500 "$tmp/repo/ro2"
set +e
cbr_archive_extra_record "$digest_src" "$tmp/repo/ro2/sub" "$tmp/repo" docs/streams/archive/dogfood >/dev/null 2>&1
rc5=$?
set -e
chmod 700 "$tmp/repo/ro2"
[ "$rc5" -ne 0 ] \
  || fail "a watch digest that could not be COPIED reported success — the reap that follows would delete the source"

set +e
cbr_archive_extra_record "$digest_src" "$tmp/out-of-repo" "$tmp/repo" "$tmp/out-of-repo" >/dev/null 2>&1
rc6=$?
set -e
[ "$rc6" -ne 0 ] \
  || fail "a watch digest that could not be STAGED reported success — the same swallowed failure, one step later"

# The archive slot is not necessarily an empty one: an interrupted run can leave
# a SYMLINK there, and a bare `cp` follows it and writes wherever it points —
# outside the archive, over whatever is at the other end. Every other write into
# an archive goes through a temp file and a rename for exactly this reason; this
# one used to be the exception.
printf 'do not overwrite me\n' > "$tmp/outside-target"
ln -sf "$tmp/outside-target" "$arch/$(basename "$digest_src")"
set +e
cbr_archive_extra_record "$digest_src" "$arch" "$tmp/repo" docs/streams/archive/dogfood >/dev/null 2>&1
rc8=$?
set -e
grep -q 'do not overwrite me' "$tmp/outside-target" \
  || fail "archiving a record through a symlinked slot wrote THROUGH the link and clobbered $tmp/outside-target — the archive can reach outside itself"
# Refusing every stale symlink would satisfy the line above and still be wrong:
# closeout stops with the base untouched when the archive fails, so the retry it
# invites must not be blocked by the debris the failure left behind.
[ "$rc8" -eq 0 ] \
  || fail "archiving into a slot an earlier run left as a symlink FAILED — the retry that a fail-closed archive exists to invite is refused by its own debris"
[ -L "$arch/$(basename "$digest_src")" ] \
  && fail "the slot is still a symlink — the archive holds a pointer, and the reap deletes what it points away from"
[ -f "$arch/$(basename "$digest_src")" ] \
  || fail "the symlinked slot was neither replaced nor failed — there is no record in the archive at all"
cmp -s "$digest_src" "$arch/$(basename "$digest_src")" \
  || fail "the archived record does not match the source bytes after replacing a symlinked slot"
rm -f "$arch/$(basename "$digest_src")"

set +e
cbr_archive_extra_record "$tmp/no-such-digest" "$arch" "$tmp/repo" docs/streams/archive/dogfood >/dev/null 2>&1
rc7=$?
set -e
[ "$rc7" -ne 0 ] || fail "archiving a record that does not exist reported success"

# ---------------------------------------------------------------------------
# WIRING — both leaves call the shared implementation, neither keeps its own
# ---------------------------------------------------------------------------
bash -n "$claude_leaf" || fail "the Claude leaf does not parse"
bash -n "$codex_leaf"  || fail "the Codex leaf does not parse"

for leaf in "$claude_leaf" "$codex_leaf"; do
  name="$(basename "$leaf")"
  grep -q 'strand-lib\.sh' "$leaf" \
    || fail "$name never sources the shared strand library — it is running its own copy of the duties"
  grep -q 'cbr_closeout_base_duties' "$leaf" \
    || fail "$name never calls cbr_closeout_base_duties — the shared duties are not wired in"
done

# The private archivers the shared library replaced. Leaving one in place is how
# a fix lands in one leaf and silently misses the other.
grep -q 'cmp -s "$wt/$f" "$root/$f"' "$claude_leaf" \
  && fail "the Claude leaf still carries its worktree-comparing archiver — the exact loop that archived nothing after a merge"
grep -q 'cp "$wt/$item" "$archive/$item"' "$codex_leaf" \
  && fail "the Codex leaf still carries its worktree-reading archiver"

# The Claude leaf archives one extra record the shared duties know nothing about
# — the watch digest — and then REAPS the strand, deleting the only other copy.
# Its copy-and-stage goes through the shared helper precisely so BOTH of its
# failure modes are reachable from a test; asserting only that the leaf calls it
# is enough here because the failures themselves are proven above.
grep -q 'cbr_archive_extra_record' "$claude_leaf" \
  || fail "the Claude leaf no longer archives the watch digest through the shared helper — an inline cp && stage swallows failures, and the reap that follows deletes the source"
grep -q 'cp "$root/.cbr-watch/$slug.commits"' "$claude_leaf" \
  && fail "the Claude leaf still copies the watch digest inline — that form cannot be failure-tested"

# The Codex leaf must not refuse the retry that a fail-closed archive invites,
# and must not silently adopt an archive belonging to some older strand either.
grep -q '\[ ! -e "\$archive" \] || die' "$codex_leaf" \
  && fail "the Codex leaf still dies whenever the archive directory exists — an interrupted closeout could never be re-run"
# Ownership is decided once, inside the shared duties. A leaf carrying its own
# copy of the rule is how one leaf ends up guarded and the other does not.
for leaf in "$claude_leaf" "$codex_leaf"; do
  grep -q 'cbr_archive_is_retry_of' "$leaf" \
    && fail "$(basename "$leaf") checks archive ownership itself — that rule belongs to cbr_closeout_base_duties, which both leaves already go through"
done

# ---------------------------------------------------------------------------
# CLOSEOUT REFUSES AN OCCUPIED STRAND — run against real disposable strands
# ---------------------------------------------------------------------------
# Closeout is the destructive end of the merge-ownership rule (core build-loop
# step 9): taking a strand over is licensed by its builder being PROVEN dead, and
# a session registry only knows the sessions IT launched, so an interactive
# builder is invisible to it. Both refusals are exercised for real here — a
# process rooted in the worktree, and a host that cannot inspect processes at all
# — because grepping for the guard would pass a leaf that runs it AFTER the reap.
occ_bin="$tmp/occbin"
mkdir -p "$occ_bin"
cat > "$occ_bin/claude" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = "agents" ] && { echo '[]'; exit 0; }
exit 0
SH
chmod +x "$occ_bin/claude"
nolsof="$tmp/occ-nolsof"
mkdir -p "$nolsof"
cp "$occ_bin/claude" "$nolsof/claude"
for c in bash sh env git python3 awk sed grep head tail cat mktemp dirname basename find sort wc tr date stat rm mkdir cp mv ln chmod ls printf uname id cmp diff rsync; do
  w="$(command -v "$c" 2>/dev/null)" && ln -sf "$w" "$nolsof/$c"
done

brokenlsof="$tmp/occ-brokenlsof"
mkdir -p "$brokenlsof"
cp "$occ_bin/claude" "$brokenlsof/claude"
for c in bash sh env git python3 awk sed grep head tail cat mktemp dirname basename find sort wc tr date stat rm mkdir cp mv ln chmod ls printf uname id cmp diff rsync; do
  w="$(command -v "$c" 2>/dev/null)" && ln -sf "$w" "$brokenlsof/$c"
done
# Present, and useless. This is the case a missing-binary fixture cannot reach.
cat > "$brokenlsof/lsof" <<'SH'
#!/usr/bin/env bash
echo "lsof: WARNING: cannot open the process table" >&2
exit 1
SH
chmod +x "$brokenlsof/lsof"

occ_sleeper=""
kill_occ() { [ -n "$occ_sleeper" ] && { kill "$occ_sleeper" 2>/dev/null || true; wait "$occ_sleeper" 2>/dev/null || true; occ_sleeper=""; }; }

# --- the Claude leaf ---
orepo="$tmp/o/repo"; owt="$tmp/o/cockpit-doomed"
mkdir -p "$orepo/skills/claude-controlled-build-run/scripts" \
         "$orepo/skills/claude-controlled-build-run/references/core/scripts" "$owt"
cp "$claude_leaf" "$orepo/skills/claude-controlled-build-run/scripts/cbr.sh"
cp "$lib" "$orepo/skills/claude-controlled-build-run/references/core/scripts/strand-lib.sh"
chmod +x "$orepo/skills/claude-controlled-build-run/scripts/cbr.sh"
git -C "$orepo" init -q -b main
echo x > "$orepo/f"; git -C "$orepo" -c user.email=t@t -c user.name=t add -A
git -C "$orepo" -c user.email=t@t -c user.name=t commit -qm base
git -C "$owt" init -q -b stream/doomed
echo y > "$owt/f"; git -C "$owt" -c user.email=t@t -c user.name=t add -A
git -C "$owt" -c user.email=t@t -c user.name=t commit -qm work

( cd "$owt" && exec sleep 600 ) & occ_sleeper=$!
sleep 1
set +e
( cd "$orepo" && PATH="$occ_bin:$PATH" \
    "$orepo/skills/claude-controlled-build-run/scripts/cbr.sh" closeout doomed ) >"$tmp/o.out" 2>&1
orc=$?
set -e
[ "$orc" -ne 0 ] \
  || fail "the Claude leaf closed out a strand with a live process rooted in its worktree: $(cat "$tmp/o.out")"
[ -d "$owt" ] && [ -f "$owt/f" ] \
  || fail "the Claude leaf reaped the occupied worktree before refusing — the guard must run BEFORE anything is destroyed"
grep -qi 'live process' "$tmp/o.out" \
  || fail "the Claude leaf refused, but not for the occupancy reason — the refusal must name the fact: $(cat "$tmp/o.out")"

kill_occ
set +e
( cd "$orepo" && PATH="$nolsof" \
    "$orepo/skills/claude-controlled-build-run/scripts/cbr.sh" closeout doomed ) >"$tmp/o2.out" 2>&1
orc2=$?
set -e
[ "$orc2" -ne 0 ] \
  || fail "with no way to inspect processes, the Claude leaf reaped anyway: $(cat "$tmp/o2.out")"
[ -d "$owt" ] || fail "the Claude leaf reaped a worktree whose occupancy it could not determine"
grep -qi 'could not be inspected' "$tmp/o2.out" \
  || fail "the Claude leaf refused, but not because occupancy was unknowable — this fixture has other guards that also refuse, so the reason is the assertion: $(cat "$tmp/o2.out")"

# --- the Codex leaf ---
qrepo="$tmp/q/repo"; qwt="$tmp/q/wt-doomed"
mkdir -p "$qrepo/skills/codex-controlled-build-run/scripts" \
         "$qrepo/skills/codex-controlled-build-run/references/cbr-core/scripts" \
         "$qrepo/.cbr-codex/runs/doomed" "$qwt"
cp "$codex_leaf" "$qrepo/skills/codex-controlled-build-run/scripts/cbr-codex.sh"
cp "$lib" "$qrepo/skills/codex-controlled-build-run/references/cbr-core/scripts/strand-lib.sh"
chmod +x "$qrepo/skills/codex-controlled-build-run/scripts/cbr-codex.sh"
git -C "$qrepo" init -q -b main
echo x > "$qrepo/f"; git -C "$qrepo" -c user.email=t@t -c user.name=t add -A
git -C "$qrepo" -c user.email=t@t -c user.name=t commit -qm base
git -C "$qwt" init -q -b stream/doomed
echo y > "$qwt/f"; git -C "$qwt" -c user.email=t@t -c user.name=t add -A
git -C "$qwt" -c user.email=t@t -c user.name=t commit -qm work
printf '{"worktree":"%s"}\n' "$qwt" > "$qrepo/.cbr-codex/runs/doomed/meta.json"
printf '{"worktreeParent":"..","worktreePrefix":"wt-"}\n' > "$qrepo/.cbr-codex.json"
echo 999999 > "$qrepo/.cbr-codex/runs/doomed/pid"

( cd "$qwt" && exec sleep 600 ) & occ_sleeper=$!
sleep 1
set +e
( cd "$qrepo" && PATH="$occ_bin:$PATH" \
    "$qrepo/skills/codex-controlled-build-run/scripts/cbr-codex.sh" closeout doomed --into main ) >"$tmp/q.out" 2>&1
qrc=$?
set -e
[ "$qrc" -ne 0 ] \
  || fail "the Codex leaf closed out a strand with a live process rooted in its worktree: $(cat "$tmp/q.out")"
[ -d "$qwt" ] && [ -d "$qrepo/.cbr-codex/runs/doomed" ] \
  || fail "the Codex leaf destroyed the worktree or the registry before refusing"
grep -qi 'live process' "$tmp/q.out" \
  || fail "the Codex leaf refused, but not for the occupancy reason: $(cat "$tmp/q.out")"
kill_occ

set +e
( cd "$qrepo" && PATH="$nolsof" \
    "$qrepo/skills/codex-controlled-build-run/scripts/cbr-codex.sh" closeout doomed --into main ) >"$tmp/q2.out" 2>&1
qrc2=$?
set -e
[ "$qrc2" -ne 0 ] \
  || fail "with no way to inspect processes, the Codex leaf reaped anyway: $(cat "$tmp/q2.out")"
[ -d "$qwt" ] || fail "the Codex leaf reaped a worktree whose occupancy it could not determine"
grep -qi 'could not be inspected' "$tmp/q2.out" \
  || fail "the Codex leaf refused, but not because occupancy was unknowable: $(cat "$tmp/q2.out")"

# ---------------------------------------------------------------------------
# A CLOSEOUT THAT SUCCEEDS — the three duties, through each leaf, for real
# ---------------------------------------------------------------------------
# The duties above are proven against the shared function, and the leaves were
# proven to CALL it by grep. That is not enough, and a mutation shows why: swap
# either leaf's invocation for a canned success string and the suite above stays
# green while the leaf archives nothing, leaves DONE.marker on the base and never
# regrounds the plan — the pre-branch behaviour, all three gaps reopened.
#
# So each leaf runs one closeout to COMPLETION against a real repo with a real
# merged worktree, and the assertions are the outcomes a human would check the
# morning after: the strand's records are in the archive with the strand's own
# bytes, the marker is gone from the base, the base plan names the base branch,
# and the worktree and branch are gone. That also pins the argument order —
# which paths are records, which is the marker, which is the plan — that nothing
# else checks.
build_merged_strand() {
  # repo, worktree, branch, slug-token → a base checkout with the strand merged
  # into it and the worktree still standing, exactly as it is at closeout time.
  local repo="$1" wt="$2" branch="$3" token="$4"
  local g="git -C $repo -c user.email=t@t -c user.name=t"
  git -C "$repo" init -q -b main
  printf '**Branch:** %s\n\nbase plan\n' "$branch" > "$repo/task_plan.md"
  mkdir -p "$repo/packages"; echo base > "$repo/packages/f"
  $g add -A >/dev/null; $g commit -qm base
  git -C "$repo" worktree add -q -b "$branch" "$wt" >/dev/null
  printf '**Branch:** %s\n\nstrand plan %s\n' "$branch" "$token" > "$wt/task_plan.md"
  printf 'readback %s\n' "$token" > "$wt/progress.md"
  printf 'findings %s\n' "$token" > "$wt/findings.md"
  printf '%s complete %s\n' "$branch" "$token" > "$wt/DONE.marker"
  local gw="git -C $wt -c user.email=t@t -c user.name=t"
  $gw add -A >/dev/null; $gw commit -qm work
  $g merge -q --no-ff "$branch" -m "merge $branch" >/dev/null
}

# --- the Claude leaf ---
srepo="$tmp/s/repo"; swt="$tmp/s/cockpit-live"
mkdir -p "$srepo/skills/claude-controlled-build-run/scripts" \
         "$srepo/skills/claude-controlled-build-run/references/core/scripts"
cp "$claude_leaf" "$srepo/skills/claude-controlled-build-run/scripts/cbr.sh"
cp "$lib" "$srepo/skills/claude-controlled-build-run/references/core/scripts/strand-lib.sh"
chmod +x "$srepo/skills/claude-controlled-build-run/scripts/cbr.sh"
build_merged_strand "$srepo" "$swt" stream/live CLAUDETOKEN
mkdir -p "$srepo/.cbr-watch"; printf 'deadbee work\n' > "$srepo/.cbr-watch/live.commits"

# An lsof that exists and fails must stop the reap exactly as a missing one does
# — this fixture is otherwise perfectly closeable, so the refusal can only be the
# occupancy answer. Note what this does and does not pin: both leaves run with
# `pipefail`, which by itself turns a failing `lsof | sed` into a non-zero
# status, so the leaf refuses here even with the library's own status handling
# broken. That is the point of asserting the OUTCOME — the leaves must refuse
# whatever the reason — while `strand-lib.test.sh` pins the library-level
# guarantee for the callers that do not set pipefail.
set +e
( cd "$srepo" && PATH="$brokenlsof" \
    "$srepo/skills/claude-controlled-build-run/scripts/cbr.sh" closeout live ) >"$tmp/sb.out" 2>&1
sbrc=$?
set -e
[ "$sbrc" -ne 0 ] \
  || fail "with a BROKEN lsof the Claude leaf reaped a strand it could not prove empty — a tool that fails answered 'nobody is there': $(cat "$tmp/sb.out")"
[ -d "$swt" ] || fail "the Claude leaf reaped the worktree on an unprovable occupancy answer"
grep -qi 'could not be inspected' "$tmp/sb.out" \
  || fail "the Claude leaf refused, but not because occupancy was unknowable: $(cat "$tmp/sb.out")"

set +e
( cd "$srepo" && PATH="$occ_bin:$PATH" \
    "$srepo/skills/claude-controlled-build-run/scripts/cbr.sh" closeout live ) >"$tmp/s.out" 2>&1
src=$?
set -e
[ "$src" -eq 0 ] \
  || fail "the Claude leaf could not close out a strand that is merged, unoccupied and clean: $(cat "$tmp/s.out")"

sarch="$srepo/docs/streams/archive/live"
for r in task_plan.md progress.md findings.md DONE.marker; do
  [ -f "$sarch/$r" ] \
    || fail "the Claude leaf's closeout left no $r in $sarch — the strand's records died with the worktree: $(cat "$tmp/s.out")"
  grep -q CLAUDETOKEN "$sarch/$r" \
    || fail "$sarch/$r does not hold the STRAND's bytes — this is the original bug: the base's own copy was archived instead of the strand's"
done
[ -f "$sarch/live.commits" ] \
  || fail "the watch digest was not archived, and the reap has now deleted the only other copy"
[ -e "$srepo/DONE.marker" ] \
  && fail "the merged strand's DONE.marker is still on the base — the next strand folds the base in and its watcher latches on a completion that is not its own"
git -C "$srepo" ls-files --error-unmatch DONE.marker >/dev/null 2>&1 \
  && fail "DONE.marker is gone from the base worktree but still tracked in the index — the deletion was not staged, so the closeout commit leaves it behind"
grep -q '^\*\*Branch:\*\* main$' "$srepo/task_plan.md" \
  || fail "the base plan still names the dead strand's branch — every session opening here re-grounds onto a branch that no longer exists: $(sed -n 1p "$srepo/task_plan.md")"
[ -d "$swt" ] && fail "the Claude leaf reported success but left the worktree standing"
git -C "$srepo" show-ref --verify --quiet refs/heads/stream/live \
  && fail "the Claude leaf reported success but left the branch behind"

# --- the Codex leaf ---
zrepo="$tmp/z/repo"; zwt="$tmp/z/wt-live"
mkdir -p "$zrepo/skills/codex-controlled-build-run/scripts" \
         "$zrepo/skills/codex-controlled-build-run/references/cbr-core/scripts" \
         "$zrepo/.cbr-codex/runs/live"
cp "$codex_leaf" "$zrepo/skills/codex-controlled-build-run/scripts/cbr-codex.sh"
cp "$lib" "$zrepo/skills/codex-controlled-build-run/references/cbr-core/scripts/strand-lib.sh"
chmod +x "$zrepo/skills/codex-controlled-build-run/scripts/cbr-codex.sh"
build_merged_strand "$zrepo" "$zwt" stream/live CODEXTOKEN
printf '{"worktreeParent":"..","worktreePrefix":"wt-"}\n' > "$zrepo/.cbr-codex.json"
printf '{"worktree":"%s"}\n' "$zwt" > "$zrepo/.cbr-codex/runs/live/meta.json"
echo 999999 > "$zrepo/.cbr-codex/runs/live/pid"
# The Codex leaf demands its own merge evidence before it will reap; a real
# closeout has it because merge-facts and live-smoke ran at the merge gate.
zsha="$(git -C "$zwt" rev-parse HEAD)"
printf '{"source_branch":"stream/live","source_sha":"%s","destination":"main","verified":1}\n' \
  "$zsha" > "$zrepo/.cbr-codex/runs/live/merge-facts.json"
printf '{"source_sha":"%s","destination":"main","merged_head":"%s","smoked":1}\n' \
  "$zsha" "$(git -C "$zrepo" rev-parse HEAD)" > "$zrepo/.cbr-codex/runs/live/live-smoke.json"

set +e
( cd "$zrepo" && PATH="$brokenlsof" \
    "$zrepo/skills/codex-controlled-build-run/scripts/cbr-codex.sh" closeout live --into main ) >"$tmp/zb.out" 2>&1
zbrc=$?
set -e
[ "$zbrc" -ne 0 ] \
  || fail "with a BROKEN lsof the Codex leaf reaped a strand it could not prove empty: $(cat "$tmp/zb.out")"
[ -d "$zwt" ] || fail "the Codex leaf reaped the worktree on an unprovable occupancy answer"
grep -qi 'could not be inspected' "$tmp/zb.out" \
  || fail "the Codex leaf refused, but not because occupancy was unknowable: $(cat "$tmp/zb.out")"

set +e
( cd "$zrepo" && PATH="$occ_bin:$PATH" \
    "$zrepo/skills/codex-controlled-build-run/scripts/cbr-codex.sh" closeout live --into main ) >"$tmp/z.out" 2>&1
zrc=$?
set -e
[ "$zrc" -eq 0 ] \
  || fail "the Codex leaf could not close out a strand that is merged, unoccupied and clean: $(cat "$tmp/z.out")"

zarch="$zrepo/docs/streams/archive/live"
for r in task_plan.md progress.md findings.md DONE.marker; do
  [ -f "$zarch/$r" ] \
    || fail "the Codex leaf's closeout left no $r in $zarch: $(cat "$tmp/z.out")"
  grep -q CODEXTOKEN "$zarch/$r" \
    || fail "$zarch/$r does not hold the STRAND's bytes — the base's own copy was archived instead"
done
[ -e "$zrepo/DONE.marker" ] \
  && fail "the Codex leaf left the merged strand's DONE.marker on the base"
grep -q '^\*\*Branch:\*\* main$' "$zrepo/task_plan.md" \
  || fail "the Codex leaf did not reground the base plan: $(sed -n 1p "$zrepo/task_plan.md")"
[ -d "$zwt" ] && fail "the Codex leaf reported success but left the worktree standing"
git -C "$zrepo" show-ref --verify --quiet refs/heads/stream/live \
  && fail "the Codex leaf reported success but left the branch behind — the next closeout-pending sweep still names this strand, and the branch outlives the work"

# ---------------------------------------------------------------------------
# THE UNPROVABLE-OCCUPANCY REFUSAL HAS A WAY THROUGH IT
# ---------------------------------------------------------------------------
# A refusal with no route past it does not make a host without lsof safe; it
# makes the ritual impossible there, and the operator finishes the job with a
# hand-run `git worktree remove` OUTSIDE it — which skips the three duties and
# re-opens the gaps they close. So the refusal names an explicit human
# assertion, and it has to actually work.
orepo2="$tmp/ov/repo"; owt2="$tmp/ov/cockpit-over"
mkdir -p "$orepo2/skills/claude-controlled-build-run/scripts" \
         "$orepo2/skills/claude-controlled-build-run/references/core/scripts"
cp "$claude_leaf" "$orepo2/skills/claude-controlled-build-run/scripts/cbr.sh"
cp "$lib" "$orepo2/skills/claude-controlled-build-run/references/core/scripts/strand-lib.sh"
chmod +x "$orepo2/skills/claude-controlled-build-run/scripts/cbr.sh"
build_merged_strand "$orepo2" "$owt2" stream/over OVERTOKEN

set +e
( cd "$orepo2" && PATH="$brokenlsof" CBR_ALLOW_UNPROVEN_OCCUPANCY=1 \
    "$orepo2/skills/claude-controlled-build-run/scripts/cbr.sh" closeout over ) >"$tmp/ov.out" 2>&1
ovrc=$?
set -e
[ "$ovrc" -eq 0 ] \
  || fail "an operator asserting the worktree is empty could not get past the Claude leaf's unprovable-occupancy refusal — on a host without a working lsof the only route left is a hand-run removal outside the ritual: $(cat "$tmp/ov.out")"
[ -f "$orepo2/docs/streams/archive/over/task_plan.md" ] \
  || fail "the overridden closeout skipped the duties it exists to perform"
[ -d "$owt2" ] && fail "the overridden closeout reported success but left the worktree standing"

zrepo2="$tmp/ov/zrepo"; zwt2="$tmp/ov/wt-over"
mkdir -p "$zrepo2/skills/codex-controlled-build-run/scripts" \
         "$zrepo2/skills/codex-controlled-build-run/references/cbr-core/scripts" \
         "$zrepo2/.cbr-codex/runs/over"
cp "$codex_leaf" "$zrepo2/skills/codex-controlled-build-run/scripts/cbr-codex.sh"
cp "$lib" "$zrepo2/skills/codex-controlled-build-run/references/cbr-core/scripts/strand-lib.sh"
chmod +x "$zrepo2/skills/codex-controlled-build-run/scripts/cbr-codex.sh"
build_merged_strand "$zrepo2" "$zwt2" stream/over OVERTOKEN
printf '{"worktreeParent":"..","worktreePrefix":"wt-"}\n' > "$zrepo2/.cbr-codex.json"
printf '{"worktree":"%s"}\n' "$zwt2" > "$zrepo2/.cbr-codex/runs/over/meta.json"
echo 999999 > "$zrepo2/.cbr-codex/runs/over/pid"
ovsha="$(git -C "$zwt2" rev-parse HEAD)"
printf '{"source_branch":"stream/over","source_sha":"%s","destination":"main","verified":1}\n' \
  "$ovsha" > "$zrepo2/.cbr-codex/runs/over/merge-facts.json"
printf '{"source_sha":"%s","destination":"main","merged_head":"%s","smoked":1}\n' \
  "$ovsha" "$(git -C "$zrepo2" rev-parse HEAD)" > "$zrepo2/.cbr-codex/runs/over/live-smoke.json"

set +e
( cd "$zrepo2" && PATH="$brokenlsof" CBR_ALLOW_UNPROVEN_OCCUPANCY=1 \
    "$zrepo2/skills/codex-controlled-build-run/scripts/cbr-codex.sh" closeout over --into main ) >"$tmp/ovz.out" 2>&1
ovzrc=$?
set -e
[ "$ovzrc" -eq 0 ] \
  || fail "the Codex leaf has no working way past its unprovable-occupancy refusal, so one leaf can be closed out on such a host and the other cannot: $(cat "$tmp/ovz.out")"
[ -f "$zrepo2/docs/streams/archive/over/task_plan.md" ] \
  || fail "the overridden Codex closeout skipped the duties it exists to perform"
[ -d "$zwt2" ] && fail "the overridden Codex closeout reported success but left the worktree standing"

echo "closeout-archive.test PASS (three duties end-to-end, idempotent, both leaves wired to the shared implementation)"
