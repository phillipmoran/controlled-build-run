#!/usr/bin/env bash
# Pre-commit gate: the close-every-review law, made mechanical.
#
# RoboRev's REVIEW stays advisory (an LLM opinion never blocks a commit).
# What blocks here is a deterministic fact about this branch's homework:
#   - a FAIL review is open            -> blocked until responded + closed
#   - a review is still queued/running -> blocked until it lands and is closed
#   - a review CRASHED (status failed) -> NOT a free pass: a crash is not a
#     review (529/auth/infra never produced a verdict), so the commit is
#     unreviewed and the gate blocks until it is re-run to completion. A
#     crash is ignored ONLY when that same commit already has a completed
#     review (the crash was a duplicate/retry) — re-run, never "oh well, skip"
#   - a PASS review is open            -> auto-closed here with a stamped
#     note (clean reviews are bookkeeping, not homework; RoboRev job 13's
#     finding: blocking on them builds bypass pressure)
#   - HEAD has NO completed review     -> re-initiated and blocked. A crashed
#     review (529/auth/infra) does not linger as a `status: failed` row — it
#     vanishes from `roborev list` entirely (observed 2026-06-23: jobs gone,
#     `roborev show <sha>` -> "no review found"). So the `status == failed`
#     branch below almost never fires; the reliable catch is a direct per-commit
#     `roborev show HEAD` — no completed review means the commit would advance
#     unreviewed, so we re-queue it and block. This is the backstop the operator asked
#     for: errored reviews get re-initiated, never silently skipped.
# The law (AGENTS.md, every dispatch) says close every review before the
# next commit — prose alone proved skippable on 2026-06-12, so it has teeth.
set -u

if ! command -v roborev >/dev/null 2>&1; then
  echo "roborev-clean-gate: roborev binary not found — harness is not armed; refusing to guess." >&2
  exit 1
fi

branch=$(git rev-parse --abbrev-ref HEAD)

open_json=$(roborev list --open --json --branch "$branch" 2>&1) || {
  echo "roborev-clean-gate: cannot reach the RoboRev daemon (${open_json}). Start it: roborev daemon start" >&2
  exit 1
}
all_json=$(roborev list --json --branch "$branch" 2>&1) || {
  echo "roborev-clean-gate: cannot reach the RoboRev daemon (${all_json}). Start it: roborev daemon start" >&2
  exit 1
}

# The review backlog on a long-lived branch outgrows ARG_MAX, so the two JSON
# docs travel by temp file, not argv (passing them inline choked with
# "Argument list too long" once main had accumulated enough history). The
# paths are tiny; the blocker/auto-close logic below is unchanged.
open_file=$(mktemp)
all_file=$(mktemp)
trap 'rm -f "$open_file" "$all_file"' EXIT
printf '%s' "$open_json" >"$open_file"
printf '%s' "$all_json" >"$all_file"

pass_ids=$(python3 - "$open_file" "$all_file" <<'EOF'
import json
import sys

def rows(path: str) -> list[dict]:
    # Fail closed: unreadable or non-list roborev output means we cannot trust
    # the review state, so block rather than silently read it as "no reviews".
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (ValueError, OSError) as exc:
        print(f"roborev-clean-gate: could not read roborev output ({exc}) — refusing to guess.", file=sys.stderr)
        sys.exit(1)
    if data is None:
        # A successful roborev call returning JSON `null` means "no rows" (an
        # empty result set), not a malformed answer — daemon-unreachable is
        # already caught by the command's exit code above, so by here the call
        # succeeded. Reading null as [] is the daemon's honest "zero open",
        # not a fail-open on an error (which still blocks via the checks below).
        return []
    if not isinstance(data, list):
        print("roborev-clean-gate: roborev output was not a JSON list — refusing to guess.", file=sys.stderr)
        sys.exit(1)
    return data

def ref(job: dict) -> str:
    return str(job.get("git_ref", ""))[:7]

blockers: list[str] = []
clean: list[str] = []
seen: set = set()

# A commit counts as reviewed once any review of it ran to completion: status
# "done" always carries a P/F verdict, and that holds whether the review is
# still open or already closed. A crashed review (status "failed") produced no
# verdict, so it never counts toward this set.
reviewed = {ref(job) for job in rows(sys.argv[2]) if job.get("status") == "done"}

for job in rows(sys.argv[1]):
    seen.add(job.get("id"))
    if job.get("status") == "failed":
        # A crash is not a review — re-run it, never wave it past. Ignore it only
        # when this commit already has a completed review (the crash was a
        # duplicate/retry); otherwise the commit is unreviewed and we block.
        if ref(job) in reviewed:
            continue
        blockers.append(
            f"  job {job.get('id')}  {ref(job)}  review CRASHED and this commit has no completed review"
            f" — re-run it: roborev review {job.get('git_ref')}"
        )
        continue
    if job.get("verdict") == "P":
        clean.append(str(job.get("id")))
    else:
        blockers.append(f"  job {job.get('id')}  {ref(job)}  OPEN {job.get('verdict') or 'unverdicted'} review — respond + close it")
for job in rows(sys.argv[2]):
    if job.get("status") in ("queued", "running") and job.get("id") not in seen:
        blockers.append(f"  job {job.get('id')}  {ref(job)}  review {job.get('status')} — wait for it, then close it")

if blockers:
    print("roborev-clean-gate: this branch has unfinished RoboRev homework:", file=sys.stderr)
    print("\n".join(blockers), file=sys.stderr)
    print("Close every review before the next commit (roborev respond <job> -m '...' && roborev close <job>).", file=sys.stderr)
    sys.exit(1)
print(" ".join(clean))
EOF
) || exit 1

# HEAD must carry a completed review, or the commit advances unreviewed. A
# crashed review leaves no `status: failed` row to catch (it vanishes from the
# list), so the open-list logic above cannot see it — we verify HEAD directly.
# By here the daemon answered `roborev list` (so it is reachable; a missing
# review is real, not infra), and any queued/running/FAIL review was already a
# blocker above. `roborev show <sha>` returns the review if one completed, or an
# "Error: no review found"/"^error:" first line if none did. No review => re-queue
# and block until it lands. The per-sha lookup (not a branch-filtered list) also
# means an inherited branch-point commit reviewed on its origin branch still counts.
head_sha=$(git rev-parse HEAD 2>/dev/null || true)
if [ -n "$head_sha" ]; then
  show_out=$(roborev show "$head_sha" 2>&1)
  first_line=$(printf '%s\n' "$show_out" | head -1)
  if [ -z "$show_out" ] || printf '%s\n' "$first_line" | grep -qiE '^error:|no review found'; then
    echo "roborev-clean-gate: HEAD ($head_sha) has no completed review — it errored or never ran (a crash leaves no open job, so this is the only catch). Re-initiating:" >&2
    roborev review "$head_sha" >/dev/null 2>&1 || true
    echo "  re-queued — wait for it (roborev wait -q $head_sha), then commit again." >&2
    exit 1
  fi
fi

for job_id in $pass_ids; do
  roborev respond "$job_id" -m 'auto-closed by roborev-clean gate: clean PASS, nothing to address' >/dev/null 2>&1 || true
  roborev close "$job_id" >/dev/null 2>&1 \
    || { echo "roborev-clean-gate: failed to auto-close clean review $job_id — close it by hand." >&2; exit 1; }
  echo "roborev-clean-gate: auto-closed clean PASS review $job_id"
done
