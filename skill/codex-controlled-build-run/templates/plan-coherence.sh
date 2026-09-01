#!/usr/bin/env bash
# Deterministic plan/Git coherence gate. No model judgment.
set -euo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 1
# A merge commit imports the strand's plan into the base branch by design —
# git=main plan=<strand> is the DEFINITION of that moment, not incoherence;
# the plan/branch pact binds strand commits, and every one of those was
# checked when it was made. The merge review gate owns the merge boundary.
if git -C "$root" rev-parse -q --verify MERGE_HEAD >/dev/null || env | grep -qE "^GITHEAD_[0-9a-f]{40}([0-9a-f]{24})?="; then
  exit 0
fi
plan="$root/task_plan.md"
[ -f "$plan" ] || { echo "plan-coherence: task_plan.md missing" >&2; exit 1; }

branch="$(git -C "$root" branch --show-current)"
planned="$(sed -nE 's/.*\*\*Branch:\*\*[[:space:]]*([^ ·]+).*/\1/p' "$plan" | head -1)"
[ -n "$planned" ] && [ "$branch" = "$planned" ] || {
  echo "plan-coherence: branch mismatch: git=$branch plan=${planned:-absent}" >&2
  exit 1
}

staged="$(git -C "$root" diff --cached --name-only --diff-filter=ACMR)"
production=0
if [ -f "$root/.cbr-codex.json" ]; then
  while IFS= read -r prefix; do
    [ -n "$prefix" ] || continue
    if printf '%s\n' "$staged" | grep -qE "^${prefix%/}(/|$)"; then production=1; fi
  done < <(python3 - "$root/.cbr-codex.json" <<'PY'
import json,sys
for path in json.load(open(sys.argv[1], encoding="utf-8")).get("productPaths", []):
    print(path)
PY
)
fi
if [ "$production" -eq 1 ] && ! printf '%s\n' "$staged" | grep -qx task_plan.md; then
  echo "plan-coherence: staged production work must stage task_plan.md in the same commit" >&2
  exit 1
fi

python3 - "$root" "$plan" <<'PY'
import re, subprocess, sys
root, plan = sys.argv[1:]
staged = subprocess.run(
    ["git", "-C", root, "show", ":task_plan.md"],
    capture_output=True, text=True,
)
text = staged.stdout if staged.returncode == 0 else open(plan, encoding="utf-8").read()
stamps = []
for line in text.splitlines():
    table = re.match(
        r"^\|\s*(?:P|Phase|Stage)[0-9]+\s*\|\s*([0-9a-f]{7,64}|pending)\s*\|\s*([0-9a-f]{7,64}|pending)\s*\|",
        line,
        re.I,
    )
    if table:
        stamps.extend(value for value in table.groups() if value.lower() != "pending")
    elif "end_sha:" in line or "reviewed:" in line:
        stamps.extend(re.findall(r"\b[0-9a-f]{7,64}\b", line))
for sha in stamps:
    result = subprocess.run(
        ["git", "-C", root, "merge-base", "--is-ancestor", sha, "HEAD"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    if result.returncode:
        print(f"plan-coherence: off-history checkpoint stamp {sha}", file=sys.stderr)
        raise SystemExit(1)
PY
