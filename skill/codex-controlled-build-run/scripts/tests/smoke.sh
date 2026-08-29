#!/usr/bin/env bash
# Disposable component/lifecycle smoke for the portable Codex CBR harness.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL="$(cd "$HERE/../.." && pwd -P)"
CBR="$SKILL/scripts/cbr-codex.sh"
REAL_NODE="$(command -v node)"
export REAL_NODE
TMP="$(mktemp -d /private/tmp/cbr-codex-smoke.XXXXXX)"
cleanup() {
  rc=$?
  jobs -pr | xargs kill 2>/dev/null || true
  if [ "$rc" -eq 0 ] || [ "${CBR_SMOKE_KEEP_FAILED:-0}" != 1 ]; then rm -rf "$TMP"; else echo "SMOKE-KEPT $TMP" >&2; fi
}
trap cleanup EXIT
REPO="$TMP/repo"; BIN="$TMP/bin"; STATE="$TMP/state"
mkdir -p "$REPO" "$BIN" "$STATE"
export PATH="$BIN:$PATH" FAKE_STATE="$STATE"
export GIT_AUTHOR_NAME="CBR Smoke" GIT_AUTHOR_EMAIL="cbr@example.invalid"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
passes=0

pass() { printf 'PASS %s\n' "$1"; passes=$((passes + 1)); }
must() { "$@" || { printf 'FAIL command: %q ' "$@" >&2; printf '\n' >&2; exit 1; }; }
must_fail() { if "$@"; then printf 'FAIL expected nonzero: %q ' "$@" >&2; printf '\n' >&2; exit 1; fi; }
contains() { grep -qF -- "$2" "$1" || { echo "FAIL $1 missing: $2" >&2; exit 1; }; }
not_contains() { if grep -qF -- "$2" "$1"; then echo "FAIL $1 unexpectedly contains: $2" >&2; exit 1; fi; }

python3 "$HERE/conformance.py"
pass "shared-core and Codex-leaf conformance"

cat >"$BIN/pre-commit" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = install ]; then
  hook="$(git rev-parse --path-format=absolute --git-path hooks/pre-commit)"
  mkdir -p "$(dirname "$hook")"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$hook"; chmod +x "$hook"
fi
exit 0
SH

cat >"$BIN/roborev" <<'SH'
#!/usr/bin/env bash
set -u
state="${FAKE_STATE:?}"
case "${1:-}" in
  init)
    hook="$(git rev-parse --path-format=absolute --git-path hooks/post-commit)"
    mkdir -p "$(dirname "$hook")"
    printf '#!/usr/bin/env bash\nroborev review HEAD >/dev/null 2>&1 || true\n' >"$hook"; chmod +x "$hook" ;;
  status) cat "$state/status.json" 2>/dev/null || printf '{"running":true}\n' ;;
  check-agents) exit 0 ;;
  wait) exit "$(cat "$state/wait-exit" 2>/dev/null || printf 0)" ;;
  list)
    if printf '%s\n' "$*" | grep -q -- '--open'; then cat "$state/open.json" 2>/dev/null || printf '[]\n';
    else cat "$state/all.json" 2>/dev/null || printf '[]\n'; fi ;;
  show) cat "$state/show.txt" 2>/dev/null || printf 'Error: no review found\n' ;;
  review) printf 'review %s\n' "${2:-}" >>"$state/actions.log" ;;
  respond) printf 'respond %s\n' "${2:-}" >>"$state/actions.log" ;;
  close) printf 'close %s\n' "${2:-}" >>"$state/actions.log" ;;
  *) exit 0 ;;
esac
SH

cat >"$BIN/codex" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${FAKE_STATE:?}/codex-args.log"
thread="11111111-2222-4333-8444-555555555555"
printf '{"type":"thread.started","thread_id":"%s"}\n' "$thread"
printf '{"type":"turn.started"}\n'
exec sleep 30
SH
cat >"$BIN/gitleaks" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat >"$BIN/node" <<'SH'
#!/usr/bin/env bash
exec "${REAL_NODE:?}" "$@"
SH
chmod +x "$BIN"/*
printf '[]\n' >"$STATE/open.json"; printf '[]\n' >"$STATE/all.json"; printf 'review PASS\n' >"$STATE/show.txt"
printf '0\n' >"$STATE/wait-exit"

git -C "$REPO" init -q -b main
printf '# fixture\n' >"$REPO/README.md"
git -C "$REPO" add README.md
git -C "$REPO" commit -qm init

mkdir -p "$REPO/node_modules/.bin" "$REPO/node_modules/@nizos/probity" "$REPO/node_modules/@openai/codex-sdk"
printf '#!/usr/bin/env bash\nexit 0\n' >"$REPO/node_modules/.bin/probity"; chmod +x "$REPO/node_modules/.bin/probity"
printf '{"version":"1.10.0","type":"module","exports":"./index.js"}\n' >"$REPO/node_modules/@nizos/probity/package.json"
printf 'export const defineConfig = (value) => value; export const enforceTdd = () => () => null; export const forbidContentPattern = () => () => null;\n' >"$REPO/node_modules/@nizos/probity/index.js"
printf '{"type":"module","exports":"./index.js"}\n' >"$REPO/node_modules/@openai/codex-sdk/package.json"
printf 'export class Codex {}\n' >"$REPO/node_modules/@openai/codex-sdk/index.js"
must "$CBR" arm "$REPO"
python3 - "$REPO/.cbr-codex.json" "$TMP/worktrees" <<'PY'
import json, sys
path, parent = sys.argv[1:]
data = json.load(open(path))
data["worktreeParent"] = parent
data["worktreePrefix"] = "fixture-"
data["toolchainProbe"] = "true"
data["verificationCommands"] = ["true"]
data["liveSmokeCommand"] = "true"
data["integrationBranchPattern"] = "^(main|integration/)"
data["productPaths"] = ["packages", "src"]
json.dump(data, open(path, "w"), indent=2)
PY
python3 - "$REPO/.pre-commit-config.yaml" <<'PY'
import sys
path=sys.argv[1]; text=open(path).read()
text=text.replace("entry: >-\n          sh -c 'echo \"EDIT .pre-commit-config.yaml: wire static checks\" >&2; exit 1'", 'entry: "true"')
text=text.replace("entry: >-\n          sh -c 'echo \"EDIT .pre-commit-config.yaml: wire tests\" >&2; exit 1'", 'entry: "true"')
open(path,'w').write(text)
PY
must "$CBR" record-hook-trust "$REPO"
must git -C "$REPO" add .agents .cbr-codex.json .cbr-codex/scripts .codex .gitignore .pre-commit-config.yaml .roborev.toml AGENTS.md probity.config.ts probity-content-policy.mjs probity-content-policy.d.mts probity-verdict-parser.mjs probity-verdict-parser.d.mts probity-integration.mjs probity-integration.d.mts
must git -C "$REPO" commit -qm harness
printf '{"running":false}\n' >"$STATE/status.json"
must_fail bash -c "cd '$REPO' && '$CBR' doctor '$REPO' >'$TMP/doctor-stopped.out' 2>&1"
contains "$TMP/doctor-stopped.out" 'RoboRev daemon'
printf '{"running":true}\n' >"$STATE/status.json"
must "$CBR" doctor "$REPO"
mv "$REPO/probity-content-policy.mjs" "$TMP/probity-content-policy.mjs"
must_fail bash -c "cd '$REPO' && '$CBR' doctor '$REPO' >'$TMP/doctor-no-runtime-helper.out' 2>&1"
contains "$TMP/doctor-no-runtime-helper.out" 'config or runtime helper missing'
mv "$TMP/probity-content-policy.mjs" "$REPO/probity-content-policy.mjs"
mv "$REPO/probity-content-policy.d.mts" "$TMP/probity-content-policy.d.mts"
must_fail bash -c "cd '$REPO' && '$CBR' doctor '$REPO' >'$TMP/doctor-no-type-helper.out' 2>&1"
contains "$TMP/doctor-no-type-helper.out" 'config or runtime helper missing'
mv "$TMP/probity-content-policy.d.mts" "$REPO/probity-content-policy.d.mts"
must "$CBR" doctor "$REPO"
cp "$REPO/probity-content-policy.mjs" "$TMP/probity-content-policy.valid.mjs"
printf '\nthis is invalid syntax (\n' >>"$REPO/probity-content-policy.mjs"
must_fail bash -c "cd '$REPO' && '$CBR' doctor '$REPO' >'$TMP/doctor-broken-runtime-helper.out' 2>&1"
contains "$TMP/doctor-broken-runtime-helper.out" 'MISSING Probity config load'
mv "$TMP/probity-content-policy.valid.mjs" "$REPO/probity-content-policy.mjs"
must "$CBR" doctor "$REPO"
cp "$REPO/probity.config.ts" "$TMP/probity.config.current.ts"
python3 - "$REPO/probity.config.ts" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("export default markIntegratedProbityConfig(probityConfig)", "// markIntegratedProbityConfig(probityConfig)\nexport default probityConfig")
open(p,'w').write(s)
PY
must_fail bash -c "cd '$REPO' && '$CBR' doctor '$REPO' >'$TMP/doctor-stale-probity.out' 2>&1"
contains "$TMP/doctor-stale-probity.out" 'MISSING Probity integration'
must_fail bash -c "cd '$REPO' && '$CBR' arm '$REPO' >'$TMP/arm-stale-probity.out' 2>&1"
contains "$TMP/arm-stale-probity.out" 'existing probity.config.ts needs a manual merge; not overwritten'
cp "$TMP/probity.config.current.ts" "$REPO/probity.config.ts"
python3 - "$REPO/probity.config.ts" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("export default markIntegratedProbityConfig(probityConfig)", "if (false) markIntegratedProbityConfig(probityConfig)\nexport default probityConfig")
open(p,'w').write(s)
PY
must_fail bash -c "cd '$REPO' && '$CBR' doctor '$REPO' >'$TMP/doctor-unreachable-probity.out' 2>&1"
contains "$TMP/doctor-unreachable-probity.out" 'MISSING Probity integration'
cp "$TMP/probity.config.current.ts" "$REPO/probity.config.ts"
python3 - "$REPO/probity.config.ts" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("export default markIntegratedProbityConfig(probityConfig)", "Object.defineProperty(probityConfig, Symbol.for('cbr.probity.integration.v2'), { value: true })\nexport default probityConfig")
open(p,'w').write(s)
PY
must_fail bash -c "cd '$REPO' && '$CBR' doctor '$REPO' >'$TMP/doctor-forged-config-marker.out' 2>&1"
contains "$TMP/doctor-forged-config-marker.out" 'MISSING Probity integration'
cp "$TMP/probity.config.current.ts" "$REPO/probity.config.ts"
python3 - "$REPO/probity.config.ts" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("ai: codexJudge,", "ai: { reason: async () => ({ kind: 'pass', reason: 'bypass' }), [Symbol.for('cbr.probity.judge.v2')]: true },")
open(p,'w').write(s)
PY
must_fail bash -c "cd '$REPO' && '$CBR' doctor '$REPO' >'$TMP/doctor-unbranded-judge.out' 2>&1"
contains "$TMP/doctor-unbranded-judge.out" 'MISSING Probity integration'
cp "$TMP/probity.config.current.ts" "$REPO/probity.config.ts"
python3 - "$REPO/probity.config.ts" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("rules: [noVendorNamesOutsideAdapters],", "rules: [Object.assign(() => null, { [Symbol.for('cbr.probity.content-policy.v2')]: true })],")
open(p,'w').write(s)
PY
must_fail bash -c "cd '$REPO' && '$CBR' doctor '$REPO' >'$TMP/doctor-missing-content-policy.out' 2>&1"
contains "$TMP/doctor-missing-content-policy.out" 'MISSING Probity integration'
cp "$TMP/probity.config.current.ts" "$REPO/probity.config.ts"
python3 - "$REPO/probity.config.ts" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("rules: [enforceTdd({ fastPath: true })],", "rules: [enforceTdd({ fastPath: true }), noVendorNamesOutsideAdapters],")
s=s.replace("rules: [noVendorNamesOutsideAdapters],", "rules: [],")
open(p,'w').write(s)
PY
must_fail bash -c "cd '$REPO' && '$CBR' doctor '$REPO' >'$TMP/doctor-irrelevant-content-policy.out' 2>&1"
contains "$TMP/doctor-irrelevant-content-policy.out" 'MISSING Probity integration'
scope_case=0
for missing_scope in 'packages/**' '!**/*.test.ts' '!**/*.test.tsx' '!**/*.config.ts' '!**/mocks/**' '!**/fixtures/**'; do
  scope_case=$((scope_case + 1))
  cp "$TMP/probity.config.current.ts" "$REPO/probity.config.ts"
  python3 - "$REPO/probity.config.ts" "$missing_scope" <<'PY'
import sys
p, missing = sys.argv[1:]
s=open(p).read()
replacement = '!**/*.test.ts' if missing == 'packages/**' else 'packages/**'
needle = f"        '{missing}',"
before, found, after = s.rpartition(needle)
assert found
s = before + f"        '{replacement}'," + after
open(p,'w').write(s)
PY
  must_fail bash -c "cd '$REPO' && '$CBR' doctor '$REPO' >'$TMP/doctor-duplicate-scope-$scope_case.out' 2>&1"
  contains "$TMP/doctor-duplicate-scope-$scope_case.out" 'MISSING Probity integration'
done
cp "$TMP/probity.config.current.ts" "$REPO/probity.config.ts"
python3 - "$REPO/probity.config.ts" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("export default markIntegratedProbityConfig(probityConfig)", "markIntegratedProbityConfig(probityConfig)\nprobityConfig.ai = { reason: async () => ({ kind: 'pass', reason: 'bypass' }) }\nexport default probityConfig")
open(p,'w').write(s)
PY
must_fail bash -c "cd '$REPO' && '$CBR' doctor '$REPO' >'$TMP/doctor-mutated-judge-after-attestation.out' 2>&1"
contains "$TMP/doctor-mutated-judge-after-attestation.out" 'MISSING Probity integration'
cp "$TMP/probity.config.current.ts" "$REPO/probity.config.ts"
python3 - "$REPO/probity.config.ts" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("export default markIntegratedProbityConfig(probityConfig)", "markIntegratedProbityConfig(probityConfig)\nprobityConfig.rules[1].rules = []\nexport default probityConfig")
open(p,'w').write(s)
PY
must_fail bash -c "cd '$REPO' && '$CBR' doctor '$REPO' >'$TMP/doctor-mutated-policy-after-attestation.out' 2>&1"
contains "$TMP/doctor-mutated-policy-after-attestation.out" 'MISSING Probity integration'
mv "$TMP/probity.config.current.ts" "$REPO/probity.config.ts"
cp "$REPO/probity-integration.mjs" "$TMP/probity-integration.current.mjs"
python3 - "$REPO/probity-integration.mjs" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("return parseVerdict(turn.finalResponse)", "return { kind: 'pass', reason: turn.finalResponse }")
open(p,'w').write(s)
PY
must_fail bash -c "cd '$REPO' && '$CBR' doctor '$REPO' >'$TMP/doctor-drifted-parser-binding.out' 2>&1"
contains "$TMP/doctor-drifted-parser-binding.out" 'MISSING Probity runtime'
mv "$TMP/probity-integration.current.mjs" "$REPO/probity-integration.mjs"
must "$CBR" doctor "$REPO"
NO_JQ="$TMP/no-jq-bin"; mkdir -p "$NO_JQ"
for command_name in bash sh env python3 grep head cat git node sed dirname pwd mkdir tr sort find diff cmp shasum; do
  command_path="$(command -v "$command_name" 2>/dev/null || true)"
  [ -n "$command_path" ] && ln -s "$command_path" "$NO_JQ/$command_name"
done
must_fail env PATH="$BIN:$NO_JQ" bash -c "cd '$REPO' && '$CBR' doctor '$REPO' >'$TMP/doctor-no-jq.out' 2>&1"
contains "$TMP/doctor-no-jq.out" 'MISSING command               jq'
pass "arm upgrade guard, real config import, runtime dependencies, missing jq, and stopped daemon"

# Compaction reinjection: whole docs + role material + all planning state,
# with no instruction to read after compact.
for doc in CONSTITUTION.md ENGINEERING.md VISION.md; do printf '%s-CANARY\n' "$doc" >"$REPO/$doc"; done
printf '# AGENTS\nAGENTS-CANARY\n' >"$REPO/AGENTS.md"
printf '# task\n\n**Branch:** main  \n**Run type:** workstream\n\n- [ ] P1 — CANARY-NEXT\n' >"$REPO/task_plan.md"
printf 'FINDINGS-CANARY\n' >"$REPO/findings.md"; printf 'PROGRESS-CANARY\n' >"$REPO/progress.md"
mkdir -p "$REPO/skills/cyclomatic-complexity"
printf 'COMPLEXITY-CANARY\n' >"$REPO/skills/cyclomatic-complexity/SKILL.md"
(cd "$REPO" && printf '{"session_id":"thread-a"}\n' | .codex/hooks/mark-post-compact.sh)
(cd "$REPO" && printf '{"session_id":"thread-b"}\n' | CBR_REGROUND_EVENT=UserPromptSubmit .codex/hooks/post-compact-reground.sh) >"$TMP/reground-wrong-thread.out"
[ ! -s "$TMP/reground-wrong-thread.out" ]
(cd "$REPO" && printf '{"session_id":"thread-a"}\n' | CBR_REGROUND_EVENT=UserPromptSubmit .codex/hooks/post-compact-reground.sh) >"$TMP/reground.json"
python3 -m json.tool "$TMP/reground.json" >/dev/null
contains "$TMP/reground.json" '"hookEventName": "UserPromptSubmit"'
for canary in CONSTITUTION.md-CANARY ENGINEERING.md-CANARY VISION.md-CANARY AGENTS-CANARY CANARY-NEXT FINDINGS-CANARY PROGRESS-CANARY 'policy.md — the laws' 'strand.md — one plan' 'build-loop.md — run the build' 'reviews.md — the review layers' 'judgment.md — resolving a judgment call' 'GLOSSARY.md — the harness' 'modes/solo.md — one strand' 'Workstream build loop' COMPLEXITY-CANARY; do contains "$TMP/reground.json" "$canary"; done
not_contains "$TMP/reground.json" 'Codex fleet orchestration'
not_contains "$TMP/reground.json" 'modes/fleet.md — orchestrating a fleet'
not_contains "$TMP/reground.json" 'modes/captain.md — the tier'
not_contains "$TMP/reground.json" 'Also reread'

python3 - "$REPO/task_plan.md" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read(); open(p,'w').write(s.replace('**Run type:** workstream','**Run type:** orchestrator'))
PY
(cd "$REPO" && printf '{"thread_id":"thread-c"}\n' | .codex/hooks/mark-post-compact.sh)
(cd "$REPO" && printf '{"thread_id":"thread-c"}\n' | CBR_REGROUND_EVENT=SessionStart .codex/hooks/post-compact-reground.sh) >"$TMP/reground-orchestrator.json"
contains "$TMP/reground-orchestrator.json" '"hookEventName": "SessionStart"'
for canary in 'policy.md — the laws' 'strand.md — one plan' 'reviews.md — the review layers' 'judgment.md — resolving a judgment call' 'GLOSSARY.md — the harness' 'modes/fleet.md — orchestrating a fleet' 'Codex fleet orchestration' COMPLEXITY-CANARY; do contains "$TMP/reground-orchestrator.json" "$canary"; done
not_contains "$TMP/reground-orchestrator.json" 'build-loop.md — run the build'
not_contains "$TMP/reground-orchestrator.json" 'modes/solo.md — one strand'
not_contains "$TMP/reground-orchestrator.json" 'modes/captain.md — the tier'
not_contains "$TMP/reground-orchestrator.json" 'Workstream build loop'

# The complexity sibling has TWO resolution paths and one fail-open path, all
# three claimed in references/harness.md and SETUP.md. Prove each: the installed
# copy WINS over the repository copy, the repository copy is used when the
# installed one is absent, and a planned reground still emits valid JSON with
# neither present. Distinct canaries, or "it resolved something" reads as "it
# resolved the right thing".
mkdir -p "$REPO/.agents/skills/cyclomatic-complexity"
printf 'COMPLEXITY-INSTALLED-CANARY\n' >"$REPO/.agents/skills/cyclomatic-complexity/SKILL.md"
(cd "$REPO" && printf '{"thread_id":"thread-cc1"}\n' | .codex/hooks/mark-post-compact.sh)
(cd "$REPO" && printf '{"thread_id":"thread-cc1"}\n' | CBR_REGROUND_EVENT=SessionStart .codex/hooks/post-compact-reground.sh) >"$TMP/reground-cc-installed.json"
contains "$TMP/reground-cc-installed.json" COMPLEXITY-INSTALLED-CANARY
not_contains "$TMP/reground-cc-installed.json" COMPLEXITY-CANARY
rm -rf "$REPO/.agents/skills/cyclomatic-complexity"
(cd "$REPO" && printf '{"thread_id":"thread-cc2"}\n' | .codex/hooks/mark-post-compact.sh)
(cd "$REPO" && printf '{"thread_id":"thread-cc2"}\n' | CBR_REGROUND_EVENT=SessionStart .codex/hooks/post-compact-reground.sh) >"$TMP/reground-cc-source.json"
contains "$TMP/reground-cc-source.json" COMPLEXITY-CANARY
mv "$REPO/skills/cyclomatic-complexity" "$TMP/cc-skill-parked"
(cd "$REPO" && printf '{"thread_id":"thread-cc3"}\n' | .codex/hooks/mark-post-compact.sh)
(cd "$REPO" && printf '{"thread_id":"thread-cc3"}\n' | CBR_REGROUND_EVENT=SessionStart .codex/hooks/post-compact-reground.sh) >"$TMP/reground-cc-absent.json"
python3 -m json.tool "$TMP/reground-cc-absent.json" >/dev/null
not_contains "$TMP/reground-cc-absent.json" COMPLEXITY-CANARY
contains "$TMP/reground-cc-absent.json" 'policy.md — the laws'
mv "$TMP/cc-skill-parked" "$REPO/skills/cyclomatic-complexity"

# Mid-build ONLY. Decision 4 makes this half of the contract as binding as the
# inject itself, and it was load-bearing on the Claude leaf and unpinned here:
# hoisting the inject out of the plan guard passed every committed assertion.
# With no plan there is no build, so no build material may leak.
mv "$REPO/task_plan.md" "$TMP/plan-parked"
(cd "$REPO" && printf '{"thread_id":"thread-cc4"}\n' | .codex/hooks/mark-post-compact.sh)
(cd "$REPO" && printf '{"thread_id":"thread-cc4"}\n' | CBR_REGROUND_EVENT=SessionStart .codex/hooks/post-compact-reground.sh) >"$TMP/reground-no-plan.json"
python3 -m json.tool "$TMP/reground-no-plan.json" >/dev/null
contains "$TMP/reground-no-plan.json" CONSTITUTION.md-CANARY
not_contains "$TMP/reground-no-plan.json" COMPLEXITY-CANARY
not_contains "$TMP/reground-no-plan.json" FINDINGS-CANARY
not_contains "$TMP/reground-no-plan.json" PROGRESS-CANARY
not_contains "$TMP/reground-no-plan.json" 'policy.md — the laws'
mv "$TMP/plan-parked" "$REPO/task_plan.md"
python3 - "$REPO/task_plan.md" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read(); open(p,'w').write(s.replace('**Run type:** orchestrator','**Run type:** workstream'))
PY
pass "role-aware core compact reinjection is complete and read-free"

# Stop and question hooks on a stream branch.
must git -C "$REPO" switch -qc stream/hook-test
python3 - "$REPO/task_plan.md" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read(); open(p,'w').write(s.replace('**Branch:** main','**Branch:** stream/hook-test'))
PY
(cd "$REPO" && printf '{"stop_hook_active":false}\n' | .codex/hooks/builder-stop-check.sh) >"$TMP/stop.json"
contains "$TMP/stop.json" '"decision": "block"'
must_fail bash -c "cd '$REPO' && printf '{}\n' | .codex/hooks/no-interactive-question.sh >/dev/null 2>&1"
printf 'done\n' >"$REPO/DONE.marker"
(cd "$REPO" && printf '{"stop_hook_active":false}\n' | .codex/hooks/builder-stop-check.sh) >"$TMP/stop-done.json"
not_contains "$TMP/stop-done.json" 'decision'
rm "$REPO/DONE.marker"
pass "headless question redirect and Stop continuity"

# Plan coherence mutations.
mkdir -p "$REPO/packages"; printf 'x\n' >"$REPO/packages/x.ts"; git -C "$REPO" add packages/x.ts
must_fail bash -c "cd '$REPO' && .cbr-codex/scripts/plan-coherence.sh >/dev/null 2>&1"
git -C "$REPO" add task_plan.md findings.md progress.md CONSTITUTION.md ENGINEERING.md VISION.md AGENTS.md
must bash -c "cd '$REPO' && .cbr-codex/scripts/plan-coherence.sh"
cp "$REPO/task_plan.md" "$TMP/plan.good"
python3 - "$REPO/task_plan.md" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read(); open(p,'w').write(s.replace('stream/hook-test','stream/wrong'))
PY
must_fail bash -c "cd '$REPO' && .cbr-codex/scripts/plan-coherence.sh >/dev/null 2>&1"
cp "$TMP/plan.good" "$REPO/task_plan.md"
git -C "$REPO" reset -q
pass "plan coherence blocks missing plan update and wrong branch"

# RoboRev deterministic state matrix.
GATE="$REPO/.cbr-codex/scripts/roborev-clean-gate.sh"
printf 'null\n' >"$STATE/open.json"; printf '[]\n' >"$STATE/all.json"; printf 'review PASS\n' >"$STATE/show.txt"
must bash -c "cd '$REPO' && '$GATE'"
printf '[{"id":1,"git_ref":"abcdef0123","status":"done","verdict":"F"}]\n' >"$STATE/open.json"
must_fail bash -c "cd '$REPO' && '$GATE' >/dev/null 2>&1"
printf '[{"id":2,"git_ref":"abcdef0123","status":"done","verdict":"P"}]\n' >"$STATE/open.json"
must bash -c "cd '$REPO' && '$GATE'"
contains "$STATE/actions.log" 'close 2'
printf '[]\n' >"$STATE/open.json"; printf '[]\n' >"$STATE/all.json"; printf 'Error: no review found\n' >"$STATE/show.txt"
must_fail bash -c "cd '$REPO' && '$GATE' >/dev/null 2>&1"
contains "$STATE/actions.log" 'review '
printf '[{"id":3,"git_ref":"abcdef0123","status":"failed"}]\n' >"$STATE/open.json"
must_fail bash -c "cd '$REPO' && '$GATE' >/dev/null 2>&1"
printf '[{"id":3,"git_ref":"abcdef0123","status":"failed"}]\n' >"$STATE/open.json"
printf '[{"id":4,"git_ref":"abcdef0123","status":"done","verdict":"P"}]\n' >"$STATE/all.json"; printf 'review PASS\n' >"$STATE/show.txt"
must bash -c "cd '$REPO' && '$GATE'"
printf '[]\n' >"$STATE/open.json"; printf '[{"id":5,"git_ref":"abcdef0123","status":"queued"}]\n' >"$STATE/all.json"
must_fail bash -c "cd '$REPO' && '$GATE' >/dev/null 2>&1"
printf '[]\n' >"$STATE/open.json"; printf '[]\n' >"$STATE/all.json"; printf 'review PASS\n' >"$STATE/show.txt"
pass "RoboRev null, FAIL, PASS-close, no-row, crash, retry, and queued states"

# Post-commit feedback and SessionStart sweep are advisory surfaces.
gate_state="$(git -C "$REPO" rev-parse --git-dir)/roborev-codex-gate-last-sha"
case "$gate_state" in /*) ;; *) gate_state="$REPO/$gate_state";; esac
rm -f "$gate_state"
printf '1\n' >"$STATE/wait-exit"; printf 'review FAIL job 77\n' >"$STATE/show.txt"
set +e
(cd "$REPO" && printf '{"tool_input":{"command":"git commit -m x"}}\n' | .codex/hooks/roborev-gate.sh) >"$TMP/post-review.out" 2>&1
post_rc=$?
set -e
[ "$post_rc" -eq 2 ]
contains "$TMP/post-review.out" 'review FAIL job 77'
printf '[{"id":77,"git_ref":"abcdef0123","status":"done","verdict":"F","commit_subject":"finding"}]\n' >"$STATE/open.json"
(cd "$REPO" && printf '{}\n' | .codex/hooks/roborev-session-sweep.sh) >"$TMP/sweep.json"
contains "$TMP/sweep.json" 'Job #77'
printf '0\n' >"$STATE/wait-exit"; printf '[]\n' >"$STATE/open.json"; printf 'review PASS\n' >"$STATE/show.txt"
pass "RoboRev PostToolUse feedback and branch-scoped session sweep"

# Graph success plus cycle and collision mutations.
cat >"$TMP/fleet.json" <<JSON
{"schemaVersion":1,"integrationBranch":"main","streams":[
 {"slug":"a","branch":"stream/a","worktree":"$TMP/a","dependsOn":[],"filesOwned":["packages/a/**"],"status":"merged","findingsLogged":true,"mergedAt":1},
 {"slug":"b","branch":"stream/b","worktree":"$TMP/b","dependsOn":["a"],"filesOwned":["packages/b/**"],"status":"planned","findingsLogged":false,"mergedAt":null}]}
JSON
printf 'a b\n' >"$TMP/fleet-plan.md"
must "$SKILL/scripts/cbr_graph.py" check "$TMP/fleet.json" --plan "$TMP/fleet-plan.md"
python3 - "$TMP/fleet.json" "$TMP/cycle.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); d['streams'][0]['dependsOn']=['b']; json.dump(d,open(sys.argv[2],'w'))
PY
must_fail "$SKILL/scripts/cbr_graph.py" check "$TMP/cycle.json"
python3 - "$TMP/fleet.json" "$TMP/collision.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); d['streams'][1]['dependsOn']=[]; d['streams'][1]['filesOwned']=['packages/a/sub/**']; json.dump(d,open(sys.argv[2],'w'))
PY
must_fail "$SKILL/scripts/cbr_graph.py" check "$TMP/collision.json"
pass "fleet DAG and ownership negative mutations"

# Return fixture primary to main and commit hook-test material so provisioning
# inherits an armed branch.
must git -C "$REPO" add task_plan.md findings.md progress.md CONSTITUTION.md ENGINEERING.md VISION.md packages/x.ts
must git -C "$REPO" commit -qm hook-fixtures
must git -C "$REPO" switch -q main
must git -C "$REPO" merge -q --no-ff stream/hook-test -m 'merge hook fixture'
python3 - "$REPO/task_plan.md" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read(); open(p,'w').write(s.replace('stream/hook-test','main').replace('- [ ] P1','- [x] P1'))
PY
git -C "$REPO" add task_plan.md; git -C "$REPO" commit -qm 'main plan identity'

# Real Git worktree provision, fake detached Codex launch, duplicate-writer
# refusal, status death, and exact-thread resume.
must mkdir -p "$TMP/worktrees"
must bash -c "cd '$REPO' && '$CBR' provision life stream/life --base main"
WT="$TMP/worktrees/fixture-life"
must grep -q '"result":"PASS"' "$WT/.cbr-codex/provision.json"
python3 - "$WT/task_plan.md" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read(); open(p,'w').write(s.replace('**Branch:** main','**Branch:** stream/life'))
PY
completed="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["completed"])' "$WT/.cbr-codex/provision.json")"
cat >"$TMP/dispatch.json" <<JSON
{"schemaVersion":1,"integrationBranch":"main","streams":[
 {"slug":"life","branch":"stream/life","worktree":"$WT","dependsOn":[],"filesOwned":["packages/life/**"],"status":"planned","findingsLogged":false,"mergedAt":null}]}
JSON
must "$SKILL/scripts/cbr_graph.py" dispatchable "$TMP/dispatch.json" life --repo "$REPO" --worktree "$WT"
must_fail "$SKILL/scripts/cbr_graph.py" dispatchable "$TMP/dispatch.json" life --repo "$REPO" --worktree "$REPO"
cp "$REPO/task_plan.md" "$TMP/dispatch-task-plan.md"
printf '\nlife\n' >>"$REPO/task_plan.md"
must bash -c "cd '$REPO' && '$CBR' dispatchable life '$TMP/dispatch.json'"
python3 - "$TMP/dispatch.json" "$TMP/dispatch-wrong-worktree.json" "$REPO" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); d['streams'][0]['worktree']=sys.argv[3]; json.dump(d,open(sys.argv[2],'w'))
PY
must_fail bash -c "cd '$REPO' && '$CBR' dispatchable life '$TMP/dispatch-wrong-worktree.json' >/dev/null 2>&1"
cp "$TMP/dispatch-task-plan.md" "$REPO/task_plan.md"
pass "graph and public dispatchable bind the fleet row to the exact lifecycle worktree"
python3 - "$TMP/dispatch.json" "$TMP/dispatch-late.json" "$completed" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); d['streams'].insert(0, {'slug':'dep','branch':'stream/dep','worktree':'/tmp/dep','dependsOn':[],'filesOwned':['packages/dep/**'],'status':'merged','findingsLogged':True,'mergedAt':int(sys.argv[3])+1}); d['streams'][1]['dependsOn']=['dep']; json.dump(d,open(sys.argv[2],'w'))
PY
must_fail "$SKILL/scripts/cbr_graph.py" dispatchable "$TMP/dispatch-late.json" life --repo "$REPO" --worktree "$WT"
pass "dispatchable requires worktree provision after dependency merge"
must bash -c "cd '$REPO' && '$CBR' launch life --prompt-file '$SKILL/templates/dispatch-prompt.md'"
RUN="$REPO/.cbr-codex/runs/life"
contains "$RUN/thread-id" '11111111-2222-4333-8444-555555555555'
must_fail bash -c "cd '$REPO' && '$CBR' launch life --prompt-file '$SKILL/templates/dispatch-prompt.md' >/dev/null 2>&1"
pid="$(cat "$RUN/pid")"; kill "$pid"; wait "$pid" 2>/dev/null || true
sleep 2
must_fail bash -c "cd '$REPO' && '$CBR' status life >/dev/null"
must bash -c "cd '$REPO' && '$CBR' resume life"
contains "$STATE/codex-args.log" 'resume 11111111-2222-4333-8444-555555555555 -'
not_contains "$STATE/codex-args.log" '--ephemeral'
not_contains "$STATE/codex-args.log" 'danger-full-access'
pid="$(cat "$RUN/pid")"; kill "$pid"; wait "$pid" 2>/dev/null || true
sleep 2
must bash -c "cd '$REPO' && '$CBR' resume life"
pid="$(cat "$RUN/pid")"; kill "$pid"; wait "$pid" 2>/dev/null || true
sleep 2
must_fail bash -c "cd '$REPO' && '$CBR' resume life >/dev/null 2>&1"
[ -f "$RUN/crash-storm.json" ]
pass "persistent launch, duplicate refusal, exact-thread resume, and crash-storm bound"

# Watch hash latch: an existing marker does not fire, a changed marker does.
printf 'old\n' >"$WT/DONE.marker"
sleep 30 & owner=$!; printf '%s\n' "$owner" >"$RUN/pid"
CBR_WATCH_POLL_SECONDS=1 bash -c "cd '$REPO' && '$CBR' watch life" >"$TMP/watch.out" 2>&1 & watcher=$!
sleep 2
kill -0 "$watcher"
printf 'new\n' >"$WT/DONE.marker"
wait "$watcher"
contains "$TMP/watch.out" 'done-changed'
kill "$owner"; wait "$owner" 2>/dev/null || true
pass "watcher ignores stale DONE and fires on hash change"

# Commit stream bookkeeping, merge it, and exercise guarded closeout.
rm "$WT/DONE.marker"
python3 - "$WT/task_plan.md" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read(); open(p,'w').write(s.replace('- [ ] P0','- [x] P0').replace('- [ ] P1','- [x] P1'))
PY
git -C "$WT" add task_plan.md findings.md progress.md
git -C "$WT" commit -qm 'complete behavior'
phase_sha="$(git -C "$WT" rev-parse HEAD)"
cat >>"$WT/task_plan.md" <<PLAN

## Phase checkpoint ledger

| Phase | end_sha | reviewed | result | evidence |
|---|---|---|---|---|
| P0 | $phase_sha | $phase_sha | pass | fixture review |
PLAN
printf 'final evidence; phase=%s\n' "$phase_sha" >"$WT/DONE.marker"
git -C "$WT" add task_plan.md DONE.marker
git -C "$WT" commit -qm 'checkpoint and done'
must bash -c "cd '$REPO' && '$CBR' merge-facts life --into main"
must git -C "$REPO" merge -q --no-ff stream/life -m 'merge life'
must bash -c "cd '$REPO' && '$CBR' live-smoke life --into main"
printf 'intentionally dirty\n' >"$WT/dirty-closeout-canary.txt"
must_fail bash -c "cd '$REPO' && '$CBR' closeout life --into main >/dev/null 2>&1"
must bash -c "cd '$REPO' && '$CBR' closeout life --into main --force-dirty"
[ ! -d "$WT" ] && [ ! -d "$RUN" ]
[ -f "$REPO/docs/streams/archive/life/task_plan.md" ]
must_fail git -C "$REPO" show-ref --verify --quiet refs/heads/stream/life
pass "archive-first closeout refuses dirty state unless forced, then retires it"

printf 'SMOKE-SUMMARY passes=%s tmp=%s\n' "$passes" "$TMP"
