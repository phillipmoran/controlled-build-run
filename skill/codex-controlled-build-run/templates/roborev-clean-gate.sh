#!/usr/bin/env bash
# Deterministic pre-commit fact gate for the close-every-review law.
set -u

if ! command -v roborev >/dev/null 2>&1; then
  echo "roborev-clean-gate: roborev missing; cannot prove review state" >&2
  exit 1
fi

branch="$(git branch --show-current 2>/dev/null)" || exit 1
[ -n "$branch" ] || { echo "roborev-clean-gate: detached HEAD" >&2; exit 1; }
open_file="$(mktemp)" || exit 1
all_file="$(mktemp)" || { rm -f "$open_file"; exit 1; }
trap 'rm -f "$open_file" "$all_file"' EXIT

roborev list --open --json --branch "$branch" >"$open_file" 2>/dev/null || {
  echo "roborev-clean-gate: daemon unavailable while reading open reviews" >&2
  exit 1
}
roborev list --json --branch "$branch" >"$all_file" 2>/dev/null || {
  echo "roborev-clean-gate: daemon unavailable while reading branch reviews" >&2
  exit 1
}

pass_ids="$(python3 - "$open_file" "$all_file" <<'PY'
import json
import sys

def rows(path):
    try:
        with open(path, encoding="utf-8") as handle:
            value = json.load(handle)
    except (OSError, ValueError) as exc:
        print(f"roborev-clean-gate: unreadable JSON: {exc}", file=sys.stderr)
        raise SystemExit(1)
    if value is None:
        return []
    if not isinstance(value, list):
        print("roborev-clean-gate: expected JSON list or null", file=sys.stderr)
        raise SystemExit(1)
    return value

def short(job):
    return str(job.get("git_ref", ""))[:7]

opened = rows(sys.argv[1])
all_rows = rows(sys.argv[2])
reviewed = {short(j) for j in all_rows if j.get("status") == "done"}
seen = set()
blockers = []
passes = []

for job in opened:
    seen.add(job.get("id"))
    status = job.get("status")
    if status == "failed":
        if short(job) not in reviewed:
            blockers.append(
                f"job {job.get('id')} {short(job)} crashed without a completed retry"
            )
    elif job.get("verdict") == "P":
        passes.append(str(job.get("id")))
    else:
        blockers.append(
            f"job {job.get('id')} {short(job)} open {job.get('verdict') or status or 'unverdicted'}"
        )

for job in all_rows:
    if job.get("status") in {"queued", "running"} and job.get("id") not in seen:
        blockers.append(f"job {job.get('id')} {short(job)} {job.get('status')}")

if blockers:
    print("roborev-clean-gate: unfinished reviews:", file=sys.stderr)
    for blocker in blockers:
        print(f"  {blocker}", file=sys.stderr)
    raise SystemExit(1)
print(" ".join(passes))
PY
)" || exit 1

head_sha="$(git rev-parse HEAD 2>/dev/null || true)"
if [ -n "$head_sha" ]; then
  show_out="$(roborev show "$head_sha" 2>&1 || true)"
  first_line="$(printf '%s\n' "$show_out" | head -1)"
  if [ -z "$show_out" ] || printf '%s\n' "$first_line" | grep -qiE '^error:|no review found'; then
    roborev review "$head_sha" >/dev/null 2>&1 || true
    echo "roborev-clean-gate: HEAD has no completed review; re-queued and blocked" >&2
    exit 1
  fi
fi

for job_id in $pass_ids; do
  roborev respond "$job_id" -m 'auto-closed by roborev-clean: clean PASS' >/dev/null 2>&1 || true
  roborev close "$job_id" >/dev/null 2>&1 || {
    echo "roborev-clean-gate: failed to auto-close PASS $job_id" >&2
    exit 1
  }
done
