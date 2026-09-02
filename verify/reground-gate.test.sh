#!/usr/bin/env bash
# Regression test for the post-compaction re-ground hook's DIET payload.
# Proves, against a throwaway fixture repo: the payload carries the house
# rules, the contract, and the ledger tail WHOLE, lists the law files as
# POINTERS (their bodies must NOT ride along), selects role-specific pointers
# from the plan's Run type, stays under the stated byte budget on a
# realistically-sized fixture, and survives a findings.md far past ARG_MAX.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
hook_src="$here/../../skills/claude-controlled-build-run/templates/hooks/post-compact-reground.sh"
[ -f "$hook_src" ] || hook_src="$here/../skill/claude-controlled-build-run/templates/hooks/post-compact-reground.sh"
[ -f "$hook_src" ] || { echo "reground-gate: hook not found at $hook_src" >&2; exit 2; }

# runs inside pre-commit hooks whose GIT_* env would poison the fixture repo
while read -r v; do unset "$v"; done < <(env | sed -nE 's/^(GIT_[A-Z_]*|GITHEAD_[0-9a-f]*)=.*/\1/p')

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
bad() { echo "reground-gate FAIL: $*" >&2; fail=1; }

mkdir -p "$tmp/skills/claude-controlled-build-run/references/core/modes" "$tmp/.claude/hooks"
git -C "$tmp" init -q
for f in policy strand reviews judgment build-loop GLOSSARY; do
  echo "$f law CORE-CANARY-$f" > "$tmp/skills/claude-controlled-build-run/references/core/$f.md"
done
for f in solo fleet; do
  echo "$f mode MODE-CANARY-$f" > "$tmp/skills/claude-controlled-build-run/references/core/modes/$f.md"
done
echo "claude adapter ADAPTER-CANARY" > "$tmp/skills/claude-controlled-build-run/references/claude.md"
echo "router ROUTER-CANARY" > "$tmp/skills/claude-controlled-build-run/SKILL.md"
echo "eng ENGINEERING-CANARY" > "$tmp/ENGINEERING.md"
echo "constitution CONSTITUTION-CANARY" > "$tmp/CONSTITUTION.md"
echo "vision VISION-CANARY" > "$tmp/VISION.md"
echo "agents AGENTS-CANARY" > "$tmp/AGENTS.md"
mkdir -p "$tmp/skills/test-driven-development" "$tmp/skills/cyclomatic-complexity"
echo "TDD-CANARY" > "$tmp/skills/test-driven-development/SKILL.md"
echo "COMPLEXITY-CANARY" > "$tmp/skills/cyclomatic-complexity/SKILL.md"
cp "$hook_src" "$tmp/.claude/hooks/post-compact-reground.sh"

payload() { # run the hook in the fixture; print the WHOLE injected context
  (cd "$tmp" && bash .claude/hooks/post-compact-reground.sh) \
    | jq -r '.hookSpecificOutput.additionalContext'
}

expect_body() { # $1 = case name, $2 = string that must be IN the payload
  payload | grep -qF "$2" || bad "$1: payload does not contain '$2'"
}

expect_no_body() { # $1 = case name, $2 = string that must NOT be in the payload
  payload | grep -qF "$2" && bad "$1: payload unexpectedly contains '$2'"
  return 0
}

# --- orchestrator: house rules + contract + ledger whole; law as pointers ----
printf '# plan PLAN-CANARY\n**Run type:** orchestrator\n' > "$tmp/task_plan.md"
echo "findings FINDINGS-CANARY" > "$tmp/findings.md"
{ echo "LEDGER-HEAD-CANARY"; printf 'old line %s\n' $(seq 1 200); echo "progress PROGRESS-TAIL-CANARY"; } > "$tmp/progress.md"
expect_body orchestrator CONSTITUTION-CANARY
expect_body orchestrator AGENTS-CANARY
expect_body orchestrator PLAN-CANARY
expect_body orchestrator FINDINGS-CANARY
expect_body orchestrator PROGRESS-TAIL-CANARY
expect_no_body orchestrator LEDGER-HEAD-CANARY   # the ledger rides as a TAIL, not whole
# law files are pointers: the paths appear, the bodies must not
expect_body orchestrator "core/policy.md"
expect_body orchestrator "modes/fleet.md"
expect_no_body orchestrator "build-loop.md — "
expect_no_body orchestrator CORE-CANARY-policy
expect_no_body orchestrator CORE-CANARY-build-loop
expect_no_body orchestrator MODE-CANARY-fleet
expect_no_body orchestrator MODE-CANARY-solo
expect_no_body orchestrator ROUTER-CANARY
expect_no_body orchestrator ENGINEERING-CANARY
expect_no_body orchestrator VISION-CANARY
expect_no_body orchestrator TDD-CANARY
expect_no_body orchestrator COMPLEXITY-CANARY
expect_no_body orchestrator ADAPTER-CANARY

# --- workstream: role flips the pointer set ---------------------------------
printf '# plan PLAN-CANARY\n**Run type:** workstream\n' > "$tmp/task_plan.md"
expect_body workstream "core/build-loop.md"
expect_body workstream "modes/solo.md"
expect_no_body workstream "modes/fleet.md"
expect_body workstream "test-driven-development/SKILL.md"
expect_body workstream "cyclomatic-complexity/SKILL.md"
expect_no_body workstream CORE-CANARY-build-loop
expect_no_body workstream MODE-CANARY-solo

# --- a fleet builder's branch never receives solo merge law -----------------
git -C "$tmp" checkout -q -b stream/fixture-probe
expect_body stream-builder "core/build-loop.md"
expect_no_body stream-builder "modes/solo.md"
git -C "$tmp" checkout -q -b ordinary-workstream
expect_body ordinary-branch "modes/solo.md"

# --- missing Run type defaults to workstream --------------------------------
printf '# plan PLAN-CANARY\nno run type line\n' > "$tmp/task_plan.md"
expect_body default-workstream "core/build-loop.md"
expect_no_body default-workstream "modes/fleet.md"

# --- no plan: no contract, no ledger, no law pointers beyond the router -----
rm -f "$tmp/task_plan.md"
expect_body no-plan CONSTITUTION-CANARY
expect_body no-plan AGENTS-CANARY
expect_body no-plan "claude-controlled-build-run/SKILL.md"
expect_no_body no-plan PLAN-CANARY
expect_no_body no-plan FINDINGS-CANARY
expect_no_body no-plan PROGRESS-TAIL-CANARY
expect_no_body no-plan "core/policy.md"

# --- byte budget: a realistically-sized fixture stays under the stated diet --
budget="$(sed -nE 's/^REGROUND_BUDGET_BYTES=([0-9]+).*/\1/p' "$hook_src")"
[ -n "$budget" ] || bad "budget: hook no longer states REGROUND_BUDGET_BYTES"
python3 - "$tmp" <<'PY'
import sys
t = sys.argv[1]
def doc(path, size, tag):
    body = (tag + "\n") + ("x" * 72 + "\n") * (size // 73)
    open(f"{t}/{path}", "w").write(body)
doc("task_plan.md", 26000, "# plan PLAN-CANARY\n**Run type:** workstream")
doc("CONSTITUTION.md", 2100, "constitution CONSTITUTION-CANARY")
doc("AGENTS.md", 3700, "agents AGENTS-CANARY")
doc("findings.md", 1400, "findings FINDINGS-CANARY")
doc("progress.md", 40000, "progress")  # long log; only the tail may ride
PY
bytes="$(payload | wc -c | tr -d ' ')"
[ "$bytes" -le "$budget" ] || \
  bad "budget: realistic payload is ${bytes}B, over the stated ${budget}B diet"

# --- oversized findings.md far past ARG_MAX must not break emission ---------
printf '# plan PLAN-CANARY\n**Run type:** workstream\n' > "$tmp/task_plan.md"
python3 -c "print('OVERSIZED-FINDINGS-CANARY' + 'x' * 1500000)" > "$tmp/findings.md" 2>/dev/null \
  || perl -e "print 'OVERSIZED-FINDINGS-CANARY', 'x' x 1500000" > "$tmp/findings.md"
# NOTE: no `| grep -q` on the giant payload — under pipefail, grep -q's early
# exit SIGPIPEs jq and the pipeline reads as failure. Pure-bash match instead.
out="$( (cd "$tmp" && bash .claude/hooks/post-compact-reground.sh) )"
ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // empty')" \
  || ctx=""
[ -n "$ctx" ] || bad "oversized: hook did not emit valid JSON with a giant findings.md"
case "$ctx" in
  *OVERSIZED-FINDINGS-CANARY*) : ;;
  *) bad "oversized: giant findings.md body was not injected (the section header alone is not proof)" ;;
esac
case "$ctx" in
  *PLAN-CANARY*) : ;;
  *) bad "oversized: a giant findings.md displaced the plan from the payload" ;;
esac

[ "$fail" -eq 0 ] && echo "reground-gate: all diet payload cases pass"
exit "$fail"
