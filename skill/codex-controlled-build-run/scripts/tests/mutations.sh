#!/usr/bin/env bash
# Each named scar must independently turn the structural verifier red.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL="$(cd "$HERE/../.." && pwd -P)"
VERIFY="$SKILL/scripts/verify_static.py"
CONFORMANCE="$SKILL/scripts/tests/conformance.py"
CANONICAL_CORE="$(cd "$SKILL/.." && pwd -P)/cbr-core"
REPO="$(cd "$SKILL/../.." && pwd -P)"
TMP="$(mktemp -d /private/tmp/cbr-codex-mutations.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
count=0

python_mutate() {
  local target="$1" old="$2" new="$3"
  python3 - "$target" "$old" "$new" <<'PY'
import sys
path, old, new = sys.argv[1:]
text=open(path, encoding='utf-8').read()
if old not in text: raise SystemExit(f'mutation source absent: {old}')
open(path,'w',encoding='utf-8').write(text.replace(old,new,1))
PY
}

expect_red() {
  local name="$1" case_dir="$TMP/$1"
  shift
  cp -R "$SKILL" "$case_dir"
  "$@" "$case_dir"
  if "$case_dir/scripts/verify_static.py" "$case_dir" >/dev/null 2>&1 && \
     python3 "$case_dir/scripts/tests/conformance.py" "$CANONICAL_CORE" >/dev/null 2>&1; then
    echo "MUTATION-SURVIVED $name" >&2
    exit 1
  fi
  count=$((count + 1)); echo "MUTATION-RED $name"
}

expect_canonical_identity_red() {
  local name="$1" case_repo="$TMP/$1-repo" case_skill
  shift
  git clone --quiet --shared "$REPO" "$case_repo"
  case_skill="$case_repo/skills/codex-controlled-build-run"
  rsync -a --delete "$SKILL/" "$case_skill/"
  "$@" "$case_skill"
  if python3 "$case_skill/scripts/tests/conformance.py" \
      "$case_repo/skills/cbr-core" >/dev/null 2>&1; then
    echo "MUTATION-SURVIVED $name" >&2
    exit 1
  fi
  count=$((count + 1)); echo "MUTATION-RED $name"
}

expect_portable_source_layout_green() {
  local case_repo="$TMP/portable-source-layout"
  mkdir -p "$case_repo/skills"
  git -C "$case_repo" init --quiet
  printf '{"name":"example-host","private":true}\n' >"$case_repo/package.json"
  cp -R "$SKILL" "$case_repo/skills/codex-controlled-build-run"
  cp -R "$CANONICAL_CORE" "$case_repo/skills/cbr-core"
  if ! python3 "$case_repo/skills/codex-controlled-build-run/scripts/tests/conformance.py" \
      "$case_repo/skills/cbr-core" >/dev/null 2>&1; then
    echo "PORTABILITY-FAIL source-layout install rejected unrelated Git history" >&2
    exit 1
  fi
  echo "PORTABILITY-PASS source-layout install ignores unrelated Git history"
}

mut_host() { python3 - "$1/templates/codex-hooks.json" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read(); open(p,'w').write(s.replace('--agent codex','--agent claude-code'))
PY
}
mut_sessionstart_compact() { python3 - "$1/templates/codex-hooks.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d['hooks'].pop('PostCompact'); moved=d['hooks'].pop('UserPromptSubmit')[0]; moved['matcher']='^compact$'; d['hooks']['SessionStart'].append(moved); json.dump(d,open(p,'w'))
PY
}
mut_context() { python3 - "$1/templates/codex-hooks.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); del d['hooks']['UserPromptSubmit'][0]['hooks'][0]['additionalContextLimit']; json.dump(d,open(p,'w'))
PY
}
mut_ephemeral() { python_mutate "$1/scripts/cbr-codex.sh" 'nohup codex exec --sandbox workspace-write' 'nohup codex exec --ephemeral --sandbox workspace-write'; }
mut_sandbox() { python_mutate "$1/scripts/cbr-codex.sh" '--sandbox workspace-write' '--sandbox danger-full-access'; }
mut_doctor_jq() { python_mutate "$1/scripts/cbr-codex.sh" 'python3 git node jq' 'python3 git node'; }
mut_done() { python_mutate "$1/scripts/captain-watch-codex.sh" 'if [ "$done1" != "$done0" ]' 'if false'; }
mut_provision() { python_mutate "$1/scripts/cbr-codex.sh" 'provision PASS not recorded in this worktree' 'provision state ignored'; }
mut_adapter_tdd() { python_mutate "$1/templates/cbr-codex.json" '    "adapters/**/*.ts",' ''; }
mut_vendor_guard() { python_mutate "$1/templates/probity.config.ts" 'forbidContentPattern({' 'allowContentPattern({'; }
mut_judge_hook_isolation() { python_mutate "$1/templates/probity-integration.mjs" '          workingDirectory: tmpdir(),' ''; }
mut_verdict_offset_zero() { python_mutate "$1/templates/probity-verdict-parser.mjs" '    if (start === 0) break' ''; }
mut_patch_header_content() { python_mutate "$1/templates/probity-integration.mjs" 'content: contentForVendorPolicy(action.content)' 'content: action.content'; }
mut_patch_deleted_context() { python_mutate "$1/templates/probity-content-policy.mjs" ".filter((line) => line.startsWith('+'))" ".filter((line) => !line.startsWith('-'))"; }
mut_doctor_probity_runtime() { python_mutate "$1/scripts/cbr-codex.sh" '"$root/probity-content-policy.mjs"' '"$root/probity-content-policy.missing"'; }
mut_stale_probity_upgrade() { python_mutate "$1/scripts/cbr-codex.sh" 'probity_config_behavior_check "$target"' 'true'; }
mut_adapter_probe_scope() { python_mutate "$1/templates/probe-prompt.md" 'adapters/**/*.ts' 'adapters/**'; }
mut_adapter_config_scope() { python_mutate "$1/templates/cbr-codex.json" '    "adapters/**/*.ts",' '    "adapters/**/*.tsx",'; }
mut_core_snapshot() {
  # The canonical leaf carries no embedded snapshot; plant one from the
  # canonical core, then drift it — conformance must byte-gate any snapshot
  # that IS present (the installed-leaf layout).
  cp -R "$CANONICAL_CORE" "$1/references/cbr-core"
  python_mutate "$1/references/cbr-core/policy.md" 'deterministic' 'determinstic'
}
mut_router_route() { python_mutate "$1/SKILL.md" '$CBR_CORE/modes/fleet.md' 'references/modes/fleet.md'; }
mut_other_provider() { python3 - "$1/SKILL.md" <<'PY'
import sys
p=sys.argv[1]; open(p,'a').write('\n' + '.' + 'claude/' + '\n')
PY
}
mut_role_payload() { python_mutate "$1/templates/hooks/post-compact-reground.sh" '$core/modes/fleet.md' '$core/build-loop.md'; }

"$VERIFY" "$SKILL" >/dev/null
python3 "$CONFORMANCE" "$CANONICAL_CORE" >/dev/null
expect_red wrong-probity-host mut_host
expect_red reground-on-sessionstart-compact mut_sessionstart_compact
expect_red truncated-additional-context mut_context
expect_red ephemeral-builder mut_ephemeral
expect_red danger-full-access mut_sandbox
expect_red doctor-without-jq mut_doctor_jq
expect_red missing-done-hash-latch mut_done
expect_red launch-without-provision mut_provision
expect_red adapter-without-tdd mut_adapter_tdd
expect_red missing-vendor-neutral-guard mut_vendor_guard
expect_red nested-judge-inherits-project-hooks mut_judge_hook_isolation
expect_red verdict-json-at-offset-zero-loops mut_verdict_offset_zero
expect_red patch-header-treated-as-file-content mut_patch_header_content
expect_red patch-deletions-treated-as-file-content mut_patch_deleted_context
expect_red doctor-ignores-probity-runtime-helper mut_doctor_probity_runtime
expect_red arm-preserves-stale-probity-config mut_stale_probity_upgrade
expect_red broad-adapter-probe-scope mut_adapter_probe_scope
expect_red adapter-config-probe-drift mut_adapter_config_scope
expect_red drifted-core-snapshot mut_core_snapshot
expect_red missing-router-route mut_router_route
expect_red other-provider-leaf-leak mut_other_provider
expect_red crossed-role-payload mut_role_payload
expect_portable_source_layout_green
echo "MUTATION-SUMMARY red=$count survived=0 portable=1"
