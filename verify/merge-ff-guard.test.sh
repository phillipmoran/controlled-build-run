#!/usr/bin/env bash
# Regression for the fast-forward bypass of the merge review wall (external
# review 2026-09-02, reproduced): a merge that fast-forwards creates no commit
# and fires NO commit hook, so a fresh branch merged into an unmoved
# integration branch skipped the wall by default. Proves: (a) the bypass is
# real on git's defaults, (b) merge.ff=false makes pre-merge-commit fire,
# (c) `cbr.sh arm` sets merge.ff=false, installs the TDD sibling skill the
# re-ground hook points at, and installs the control-plane guard, (d) doctor
# FAILs on merge.ff unset and PASSes it when set, (e) the Codex leaf carries
# the same rule. Hermetic: scratch repos only; pre-commit/roborev absence is
# expected and ignored (arm reports them, the facts under test do not need them).
set -uo pipefail
for v in $(env | sed -n 's/^\(GIT_[A-Z_]*\)=.*/\1/p'); do unset "$v"; done

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
kit="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
leaf="$root/skills/claude-controlled-build-run"
[ -f "$leaf/scripts/cbr.sh" ] || leaf="$kit/skill/claude-controlled-build-run"
cbr="$leaf/scripts/cbr.sh"
codex="$root/skills/codex-controlled-build-run/scripts/cbr-codex.sh"
[ -f "$codex" ] || codex="$kit/skill/codex-controlled-build-run/scripts/cbr-codex.sh"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fails=0
bad() { echo "merge-ff-guard.test FAIL: $1" >&2; fails=$((fails+1)); }
g() { git -c user.email=t@t -c user.name=t "$@"; }

# --- (a)+(b): the bypass and the fix, on bare git ---
r="$tmp/bare"; mkdir -p "$r"; g -C "$r" init -q -b main; g -C "$r" commit -q --allow-empty -m init
for h in pre-commit pre-merge-commit; do
  printf '#!/bin/sh\necho HOOK-FIRED %s >&2; exit 1\n' "$h" > "$r/.git/hooks/$h"; chmod +x "$r/.git/hooks/$h"
done
g -C "$r" checkout -q -b stream/x
echo a > "$r/a"; g -C "$r" add a; g -C "$r" -c core.hooksPath=/dev/null commit -q -m "on stream"
g -C "$r" checkout -q main
out="$(g -C "$r" merge stream/x 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && grep -q "Fast-forward" <<<"$out" && ! grep -q "HOOK-FIRED" <<<"$out" \
  || bad "expected git's default merge to fast-forward past both failing hooks (the bypass under test); got rc=$rc: $out"
g -C "$r" reset -q --hard HEAD~1
g -C "$r" config merge.ff false
out="$(g -C "$r" merge stream/x -m merge 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && grep -q "HOOK-FIRED pre-merge-commit" <<<"$out" \
  || bad "with merge.ff=false the pre-merge-commit hook did not fire/block (rc=$rc): $out"
[ "$(g -C "$r" rev-parse HEAD)" = "$(g -C "$r" rev-parse main)" ] || bad "blocked merge moved main"

# --- (c): arm sets the config and installs what the re-ground points at ---
t="$tmp/armed"; mkdir -p "$t"; g -C "$t" init -q -b main; g -C "$t" commit -q --allow-empty -m init
[ "$(git -C "$t" config --get merge.ff 2>/dev/null)" = "" ] || bad "fixture starts with merge.ff set"
arm_out="$(bash "$cbr" arm "$t" --no-probe --model test-model-id 2>&1)" || true
[ "$(git -C "$t" config --get merge.ff)" = "false" ] || bad "arm did not set merge.ff=false: $arm_out"
grep -q "merge.ff=false" <<<"$arm_out" || bad "arm did not report the merge.ff fact: $arm_out"
[ -f "$t/skills/test-driven-development/SKILL.md" ] || bad "arm did not install skills/test-driven-development (the re-ground hook points at it)"
[ -f "$t/skills/cyclomatic-complexity/SKILL.md" ] || bad "arm did not install skills/cyclomatic-complexity"
[ -x "$t/.claude/hooks/control-plane-guard.sh" ] || bad "arm did not install an executable .claude/hooks/control-plane-guard.sh"
python3 - "$t/.claude/settings.json" <<'PY' || bad "arm --model did not pin the model on the fresh settings file"
import json, sys
sys.exit(0 if json.load(open(sys.argv[1])).get("model") == "test-model-id" else 1)
PY
# idempotent: a second arm reports the config as already set, never fails on it
arm2="$(bash "$cbr" arm "$t" --no-probe 2>&1)" || true
grep -q "merge.ff already false" <<<"$arm2" || bad "second arm did not recognise merge.ff already set: $arm2"

# --- (d): doctor grades the fact ---
doc="$(bash "$cbr" doctor "$t" 2>&1)" || true
grep -q "PASS.*merge.ff=false" <<<"$doc" || bad "doctor did not PASS merge.ff on an armed repo: $doc"
grep -q "PASS.*TDD skill present" <<<"$doc" || bad "doctor did not PASS the TDD sibling on an armed repo"
grep -q "FAIL.*probity.config.ts still carries its EDIT-ME" <<<"$doc" || bad "doctor did not FAIL the unedited probity skeleton (presence is not liveness)"
grep -q "FAIL.*roborev.toml still carries its EDIT-ME" <<<"$doc" || bad "doctor did not FAIL the unedited roborev skeleton"
grep -q "PASS.*hook present + executable: .claude/hooks/control-plane-guard.sh" <<<"$doc" || bad "doctor's hook loop does not grade the guard"
git -C "$t" config --unset merge.ff
doc="$(bash "$cbr" doctor "$t" 2>&1)" || true
grep -q "FAIL.*merge.ff is not false" <<<"$doc" || bad "doctor did not FAIL merge.ff after it was unset: $doc"
# a drifted verbatim hook is named, not silently accepted
git -C "$t" config merge.ff false
printf '#!/bin/sh\nexit 0\n' > "$t/.claude/hooks/builder-stop-check.sh"
doc="$(bash "$cbr" doctor "$t" 2>&1)" || true
grep -q "WARN.*hook body differs from its template: .claude/hooks/builder-stop-check.sh" <<<"$doc" \
  || bad "doctor did not WARN on a disarmed (drifted) hook body: $doc"
# compaction triple: different numbers WARN, disabled FAILs
python3 - "$t/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]; c = json.load(open(p)); c["autoCompactWindow"] = 200000
json.dump(c, open(p, "w"), indent=2)
PY
doc="$(bash "$cbr" doctor "$t" 2>&1)" || true
grep -q "WARN.*compaction triple differs from the reference" <<<"$doc" || bad "doctor did not WARN (rather than FAIL) on a deliberately different compaction window: $doc"
grep -q "FAIL.*compaction triple" <<<"$doc" && bad "doctor still FAILs a deliberately different compaction window"
python3 - "$t/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]; c = json.load(open(p)); c["autoCompactEnabled"] = False
json.dump(c, open(p, "w"), indent=2)
PY
doc="$(bash "$cbr" doctor "$t" 2>&1)" || true
grep -q "FAIL.*compaction triple missing/disabled" <<<"$doc" || bad "doctor did not FAIL a disabled compaction: $doc"

# --- (e): the Codex leaf carries the same rule ---
grep -q 'config merge.ff false' "$codex" || bad "cbr-codex.sh arm does not set merge.ff=false"
grep -q 'merge.ff.*not false' "$codex" || bad "cbr-codex.sh doctor does not grade merge.ff"

[ "$fails" -eq 0 ] || exit 1
echo "merge-ff-guard.test OK: default merge fast-forwards past failing hooks; merge.ff=false fires pre-merge-commit; arm sets it, installs the TDD sibling + guard, pins --model; doctor grades merge.ff, EDIT-ME liveness, hook-body drift, compaction WARN/FAIL; Codex leaf carries the rule"
