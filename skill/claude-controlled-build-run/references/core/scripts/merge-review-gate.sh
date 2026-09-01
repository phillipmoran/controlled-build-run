#!/usr/bin/env bash
# The review wall, at the one boundary that ships work: a MERGE commit.
#
# Per-commit reviews are advisory (2026-08-31 cadence move) — nothing holds an
# ordinary commit. What blocks HERE, and only here, is the merged branch's
# review homework:
#   - no merge in flight               -> not a merge; exit 0, decide nothing
#   - reviewer daemon unreachable      -> blocked (an unverifiable wall is no wall)
#   - open FAIL / queued / running job -> blocked until handled and closed
#   - no COMPLETED branch review whose range ends at the merged tip
#                                      -> blocked (run: roborev review --branch)
#   - fix-round chain longer than 3 with no escalation ruling on file
#                                      -> blocked (record: git config
#                                         branch.<branch>.cbrEscalation "<ruling>")
#   - open jobs that are none of the above (clean per-commit bookkeeping)
#                                      -> fold-closed as superseded by the
#                                         branch review; a failed fold blocks
#                                         (an open review must not survive
#                                         the merge)
set -u

# Merge detection has TWO shapes (probed empirically 2026-08-31):
#   - manual completion (`merge --no-commit` / conflict, then `git commit`):
#     MERGE_HEAD exists in $GIT_DIR.
#   - auto-committing `git merge` firing the pre-merge-commit hook:
#     MERGE_HEAD is NOT yet written there — the only merge evidence in that
#     env is the GITHEAD_<sha>=<name> variable git exports to the hook.
# Keying on MERGE_HEAD alone silently waves through every auto-merge — the
# exact path the wall exists for.
merge_sha="" githead_name=""
if git rev-parse -q --verify MERGE_HEAD >/dev/null; then
  merge_sha="$(git rev-parse MERGE_HEAD)"
else
  # 40 hex = SHA-1 object format, 64 = SHA-256; both are valid production repos
  githeads="$(env | sed -n 's/^GITHEAD_\([0-9a-f]\{40\}\([0-9a-f]\{24\}\)\{0,1\}\)=/\1 /p')"
  if [ "$(printf '%s\n' "$githeads" | grep -c .)" -gt 1 ]; then
    # an octopus merge would let every head but the checked one skip its
    # review homework — the wall audits one branch per merge
    echo "merge-review-gate: octopus merge (multiple merge heads) — merge one branch at a time so each branch's review homework is checked." >&2
    exit 1
  fi
  githead="$(printf '%s\n' "$githeads" | head -1)"
  merge_sha="${githead%% *}"
  githead_name="$(printenv "GITHEAD_$merge_sha" 2>/dev/null || true)"
fi
[ -n "$merge_sha" ] || exit 0

# The branch being merged. GITHEAD's value is the name the merge was invoked
# with; a merge of a detached sha or deleted branch cannot name its homework,
# so it must be named by hand rather than waved through.
ref_branches="$(git for-each-ref --format='%(refname:short)' --points-at "$merge_sha" refs/heads)"
if [ -z "${CBR_MERGE_BRANCH:-}" ] && [ -z "$githead_name" ] \
   && [ "$(printf '%s\n' "$ref_branches" | grep -c .)" -gt 1 ]; then
  # several branches share this tip — guessing could audit the wrong branch's
  # review homework, so the ambiguity fails closed
  echo "merge-review-gate: multiple branches point at $merge_sha ($(printf '%s' "$ref_branches" | tr '\n' ' ')) — name the merged branch: CBR_MERGE_BRANCH=<branch> git commit ..." >&2
  exit 1
fi
branch="${CBR_MERGE_BRANCH:-${githead_name:-$(printf '%s\n' "$ref_branches" | head -1)}}"
[ -n "$branch" ] || {
  echo "merge-review-gate: cannot name the merged branch for $merge_sha — set it: CBR_MERGE_BRANCH=<branch> git merge ..." >&2
  exit 1
}

command -v roborev >/dev/null 2>&1 || {
  echo "merge-review-gate: roborev binary not found — the merge wall cannot be verified; refusing to guess." >&2
  exit 1
}
open_json="$(roborev list --open --json --branch "$branch" 2>&1)" || {
  echo "merge-review-gate: cannot reach the RoboRev daemon (${open_json}). Start it: roborev daemon start" >&2
  exit 1
}
all_json="$(roborev list --json --branch "$branch" 2>&1)" || {
  echo "merge-review-gate: cannot reach the RoboRev daemon (${all_json}). Start it: roborev daemon start" >&2
  exit 1
}

open_file="$(mktemp)"; all_file="$(mktemp)"
trap 'rm -f "$open_file" "$all_file"' EXIT
printf '%s' "$open_json" >"$open_file"
printf '%s' "$all_json"  >"$all_file"

# One JSON pass, three verdict lines on stdout:
#   BLOCKERS <ids...>   open FAIL/queued/running jobs on the branch
#   FOLD <ids...>       open jobs that are mere bookkeeping (fold-close them)
#   BRANCH-REVIEW yes|no  a completed branch review ends at the merged tip
merge_base="$(git merge-base HEAD "$merge_sha")"
verdicts="$(python3 - "$open_file" "$all_file" "$merge_sha" "$merge_base" <<'EOF'
import json, sys

def rows(path):
    # Fail closed: unreadable review state must block, never read as "none".
    try:
        with open(path, encoding="utf-8") as fh:
            value = json.load(fh)
    except Exception:
        sys.exit(3)
    if value is None:
        return []          # roborev prints literal `null` for an empty list
    if not isinstance(value, list):
        sys.exit(3)
    return value

open_rows, all_rows = rows(sys.argv[1]), rows(sys.argv[2])
merge_sha, merge_base = sys.argv[3], sys.argv[4]

blockers, fold = [], []
for row in open_rows:
    rid = str(row.get("id", "?"))
    status = str(row.get("status", "")).lower()
    verdict = str(row.get("verdict", "")).upper()
    if verdict.startswith("F") or status in ("queued", "running", "failed"):
        blockers.append(rid)
    else:
        fold.append(rid)

# The review must span the WHOLE branch: its range must end at the merged tip
# AND start at the integration merge-base — a HEAD~1..tip review of the last
# commit alone is not the branch review the wall promises.
def full_branch_review(row):
    if str(row.get("status", "")).lower() != "done":
        return False
    ref = str(row.get("git_ref", ""))
    if ".." not in ref:
        return False
    start, end = ref.rsplit("..", 1)[0], ref.rsplit("..", 1)[-1]
    # reviewer git_refs carry >=7-hex prefixes; anything shorter is not a
    # review identifier and must not prefix-match its way through the wall
    if len(start) < 7 or len(end) < 7:
        return False
    return merge_sha.startswith(end) and merge_base.startswith(start)

done_branch = any(full_branch_review(row) for row in all_rows)

print("BLOCKERS", *blockers)
print("FOLD", *fold)
print("BRANCH-REVIEW", "yes" if done_branch else "no")
EOF
)" || {
  echo "merge-review-gate: could not parse the RoboRev job lists — refusing on unverifiable state." >&2
  exit 1
}

blockers="$(printf '%s\n' "$verdicts" | sed -n 's/^BLOCKERS //p')"
fold_ids="$(printf '%s\n' "$verdicts" | sed -n 's/^FOLD //p')"
branch_review="$(printf '%s\n' "$verdicts" | sed -n 's/^BRANCH-REVIEW //p')"

if [ -n "$blockers" ] && [ "$blockers" != "BLOCKERS" ]; then
  echo "merge-review-gate: open blocking review(s) on $branch: $blockers — handle each (fix, or respond+close with recorded judgment) before merging." >&2
  exit 1
fi

if [ "$branch_review" != "yes" ]; then
  echo "merge-review-gate: no completed branch review spans $merge_base..$merge_sha (must start at the merge-base and end at the merged tip — a partial-range review does not count) — run: roborev review --branch --base <integration>  (from $branch), wait for it, handle findings, then merge." >&2
  exit 1
fi

# Round cap (3 TOTAL per PR, ratified 2026-08-31): every review-fix commit in
# the merge range counts — interleaving ordinary commits or splitting chains
# does not reset it (a consecutive-run proxy was narrower than the ratified
# TOTAL). First-parent history is deliberate, not an oversight: commits
# arriving through refresh/nested merges carry rounds already ruled on at
# their own merge boundaries, and re-counting them would double-charge this
# PR for another branch's homework. The commit-subject citation is the
# sanctioned grammar
# for a fix round; the escalation ruling is the deliberate exit.
max_run="$(git log --first-parent --format='%s' "$merge_base".."$merge_sha" | grep -c -i -E '(review|roborev)s? [0-9]' || true)"
if [ "${max_run:-0}" -gt 3 ]; then
  ruling="$(git config "branch.$branch.cbrEscalation" 2>/dev/null || true)"
  [ -n "$ruling" ] || {
    echo "merge-review-gate: a fix-round chain of $max_run commits exceeds the 3-round cap and no escalation ruling is on file — record one: git config branch.$branch.cbrEscalation '<who ruled what, when>'" >&2
    exit 1
  }
  echo "merge-review-gate: round cap exceeded ($max_run) — proceeding on recorded ruling: $ruling"
fi

# Bookkeeping open jobs fold into the branch review. A fold that fails leaves
# an open review behind the merge — the zero-open-reviews promise is the
# gate's to keep, so a failed close blocks like every other unverifiable fact.
for id in $fold_ids; do
  [ "$id" = "FOLD" ] && continue
  if roborev respond --job "$id" -m "superseded by the completed branch review at merge of $branch" >/dev/null 2>&1 \
     && roborev close "$id" >/dev/null 2>&1; then
    echo "merge-review-gate: folded job $id into the branch review"
  else
    echo "merge-review-gate: could not fold-close job $id — the merge would leave an open review behind; close it (roborev respond --job $id ... && roborev close $id) and retry" >&2
    exit 1
  fi
done

echo "merge-review-gate: $branch clean — branch review complete, no blockers, round cap honored"
exit 0
