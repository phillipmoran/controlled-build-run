#!/usr/bin/env bash
# Regression test for the post-compaction re-ground hook's composed payload.
# Proves, against a throwaway fixture repo: the four role paths (orchestrator /
# workstream / missing Run type / no plan) select the right core sections, and
# the hook survives a payload far past the OS per-argument limit (a giant
# findings.md must not kill the JSON emission — the re-ground is load-bearing).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
hook_src="$here/../harness/hooks/post-compact-reground.sh"
[ -f "$hook_src" ] || { echo "reground-gate: hook not found at $hook_src" >&2; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
bad() { echo "reground-gate FAIL: $*" >&2; fail=1; }

mkdir -p "$tmp/skills/claude-controlled-build-run/references/core/modes" "$tmp/.claude/hooks"
git -C "$tmp" init -q
for f in policy strand reviews judgment build-loop GLOSSARY; do
  echo "$f law CORE-CANARY-$f" > "$tmp/skills/claude-controlled-build-run/references/core/$f.md"
done
for f in solo fleet captain; do
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

headers() { # just the === section headers, for the role-selection cases
  payload | grep '^=== ' || true
}

# Headers alone prove only that the hook ANNOUNCED a section. A hook that emits
# the header and zero bytes of the file passes every header assertion — proven by
# mutation on 2026-08-27, when replacing the injected body with an empty string
# left the whole suite green. So each injected file also carries a content canary
# that must appear in the full payload.
expect_body() { # $1 = case name, $2 = canary that must be IN the payload
  payload | grep -qF "$2" || bad "$1: payload announced sections but does not contain '$2'"
}

expect_no_body() { # $1 = case name, $2 = canary that must NOT be in the payload
  payload | grep -qF "$2" && bad "$1: payload unexpectedly contains '$2'"
  return 0
}

expect() { # $1 = case name, $2 = headers, $3 = must-contain regex, $4 = must-NOT-contain regex
  printf '%s' "$2" | grep -qE "$3" || bad "$1: missing section matching '$3'"
  if [ -n "$4" ]; then
    printf '%s' "$2" | grep -qE "$4" && bad "$1: unexpected section matching '$4'"
  fi
  return 0
}

printf '# plan PLAN-CANARY\n**Run type:** orchestrator\n' > "$tmp/task_plan.md"
echo "findings FINDINGS-CANARY" > "$tmp/findings.md"
echo "progress PROGRESS-CANARY" > "$tmp/progress.md"
h="$(headers)"
expect orchestrator "$h" 'CBR core policy' ''
expect orchestrator "$h" 'fleet mode' ''
expect orchestrator "$h" 'captain mode' ''
expect orchestrator "$h" 'ACTIVE PLAN' ''
expect orchestrator "$h" 'CBR core (policy|strand)' 'build loop|solo mode'
expect orchestrator "$h" 'cyclomatic-complexity SKILL' ''
expect_body orchestrator COMPLEXITY-CANARY
expect_body orchestrator TDD-CANARY
expect_body orchestrator ROUTER-CANARY
expect_body orchestrator ENGINEERING-CANARY
expect_body orchestrator CORE-CANARY-policy
expect_body orchestrator CORE-CANARY-strand
expect_body orchestrator CORE-CANARY-reviews
expect_body orchestrator CORE-CANARY-judgment
expect_body orchestrator ADAPTER-CANARY
expect_body orchestrator MODE-CANARY-fleet
expect_body orchestrator MODE-CANARY-captain
expect_no_body orchestrator MODE-CANARY-solo
expect_no_body orchestrator CORE-CANARY-build-loop
expect_body orchestrator PLAN-CANARY
expect_body orchestrator FINDINGS-CANARY
expect_body orchestrator PROGRESS-CANARY
expect_body orchestrator CORE-CANARY-GLOSSARY
expect_body orchestrator CONSTITUTION-CANARY
expect_body orchestrator VISION-CANARY
expect_body orchestrator AGENTS-CANARY

printf '# plan PLAN-CANARY\n**Run type:** workstream\n' > "$tmp/task_plan.md"
h="$(headers)"
expect workstream "$h" 'build loop' ''
expect workstream "$h" 'solo mode' ''
expect workstream "$h" 'Claude leaf mechanisms' ''
expect workstream "$h" 'CBR core policy' 'fleet mode|captain mode'
expect workstream "$h" 'cyclomatic-complexity SKILL' ''
expect_body workstream COMPLEXITY-CANARY
expect_body workstream TDD-CANARY
expect_body workstream CORE-CANARY-build-loop
expect_body workstream CORE-CANARY-policy
expect_body workstream ADAPTER-CANARY
expect_body workstream MODE-CANARY-solo
expect_no_body workstream MODE-CANARY-fleet
expect_no_body workstream MODE-CANARY-captain
expect_body workstream PLAN-CANARY
expect_body workstream FINDINGS-CANARY
expect_body workstream PROGRESS-CANARY
expect_body workstream CORE-CANARY-GLOSSARY
expect_body workstream CORE-CANARY-reviews
expect_body workstream CORE-CANARY-strand
expect_body workstream CORE-CANARY-judgment
expect_body workstream CONSTITUTION-CANARY
expect_body workstream VISION-CANARY
expect_body workstream AGENTS-CANARY

printf '# plan PLAN-CANARY\nno run type line\n' > "$tmp/task_plan.md"
h="$(headers)"
expect default-workstream "$h" 'build loop' 'fleet mode|captain mode'

rm -f "$tmp/task_plan.md"
h="$(headers)"
expect no-plan "$h" 'SKILL\.md' 'CBR core|ACTIVE PLAN'
# mid-build only: no plan, no complexity skill (same rule the TDD skill follows)
expect no-plan "$h" 'SKILL\.md' 'cyclomatic-complexity'
expect_no_body no-plan COMPLEXITY-CANARY
expect_no_body no-plan TDD-CANARY
expect_body no-plan ROUTER-CANARY
expect_body no-plan ENGINEERING-CANARY
expect_no_body no-plan CORE-CANARY-policy
expect_no_body no-plan ADAPTER-CANARY
expect_no_body no-plan PLAN-CANARY
expect_no_body no-plan FINDINGS-CANARY
expect_no_body no-plan PROGRESS-CANARY
expect_no_body no-plan CORE-CANARY-GLOSSARY
expect_no_body no-plan CORE-CANARY-build-loop
expect_no_body no-plan MODE-CANARY-solo
expect_no_body no-plan MODE-CANARY-fleet
expect_no_body no-plan CORE-CANARY-strand
expect_no_body no-plan CORE-CANARY-reviews
expect_no_body no-plan CORE-CANARY-judgment
expect_no_body no-plan MODE-CANARY-captain
expect_body no-plan CONSTITUTION-CANARY
expect_body no-plan VISION-CANARY
expect_body no-plan AGENTS-CANARY

# Oversized payload: a findings.md far past ARG_MAX must not break emission.
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

[ "$fail" -eq 0 ] && echo "reground-gate: all payload cases pass"
exit "$fail"
