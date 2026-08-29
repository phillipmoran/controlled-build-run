#!/usr/bin/env bash
# A non-interactive stream builder may not stop merely to ask a question or
# abandon unchecked phases. Continue once; explicit terminal markers permit stop.
set -uo pipefail

payload="$(cat)"
command -v python3 >/dev/null 2>&1 || exit 0
active="$(printf '%s' "$payload" | python3 -c '
import json, sys
try:
    print("1" if json.load(sys.stdin).get("stop_hook_active") else "0")
except Exception:
    print("0")
' 2>/dev/null || echo 0)"
[ "$active" = "1" ] && { printf '{}\n'; exit 0; }

branch="$(git branch --show-current 2>/dev/null || true)"
case "$branch" in stream/*) ;; *) printf '{}\n'; exit 0 ;; esac

for marker in DONE.marker NEEDS-HUMAN.md HARNESS-BROKEN.marker; do
  [ -e "$marker" ] && { printf '{}\n'; exit 0; }
done
[ -f task_plan.md ] || { printf '{}\n'; exit 0; }

if grep -qE '^- \[ \] (P|Phase|Stage)[0-9]+' task_plan.md; then
  python3 - <<'PY'
import json
print(json.dumps({
    "decision": "block",
    "reason": (
        "The active stream plan still has unchecked phases and no DONE.marker, "
        "NEEDS-HUMAN.md, or HARNESS-BROKEN.marker. Continue from task_plan.md. "
        "Do not stop to ask interactively: write ASK-ORCH.md with a proposed "
        "default and keep working on independent work."
    ),
}))
PY
else
  printf '{}\n'
fi
