#!/usr/bin/env bash
# Portable mechanics for the Codex controlled-build-run discipline.
# Law: gather facts and run fixed sequences; never auto-merge/push/relaunch.
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL_DIR="$(cd "$SELF_DIR/.." && pwd -P)"
TPL="$SKILL_DIR/templates"

# The shared, provider-neutral closeout mechanics. The core snapshot ships inside
# this leaf (references/cbr-core/, byte-gated by verify/core-mirrors.test.sh), so the
# path is fixed relative to this script. Sourced, not shelled out to: these are
# functions the closeout composes.
CBR_STRAND_LIB="$SKILL_DIR/references/cbr-core/scripts/strand-lib.sh"
if [ -f "$CBR_STRAND_LIB" ]; then
  # shellcheck source=/dev/null
  . "$CBR_STRAND_LIB"
fi

say() { printf '%s\n' "$*"; }
fact() { printf 'FACT %-24s %s\n' "$1" "$2"; }
fail() { printf 'MISSING %-21s %s\n' "$1" "$2" >&2; }
die() { printf 'cbr-codex: %s\n' "$*" >&2; exit 2; }

repo_root() {
  git -C "${1:-$PWD}" rev-parse --show-toplevel 2>/dev/null ||
    die "${1:-$PWD} is not inside a Git repository"
}

primary_root() {
  local root common
  root="$(repo_root "${1:-$PWD}")"
  common="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  dirname "$common"
}

config_file() { printf '%s/.cbr-codex.json\n' "$(repo_root "${1:-$PWD}")"; }

cfg() {
  local root="$1" key="$2" default="${3-}"
  python3 - "$(config_file "$root")" "$key" "$default" <<'PY'
import json, sys
path, key, default = sys.argv[1:]
try:
    value = json.load(open(path, encoding="utf-8"))
    for part in key.split("."):
        value = value[part]
except Exception:
    value = default
if isinstance(value, bool):
    print("true" if value else "false")
elif isinstance(value, (dict, list)):
    print(json.dumps(value, separators=(",", ":")))
else:
    print(value)
PY
}

cfg_lines() {
  local root="$1" key="$2"
  python3 - "$(config_file "$root")" "$key" <<'PY'
import json, sys
try:
    value = json.load(open(sys.argv[1], encoding="utf-8"))
    for part in sys.argv[2].split("."):
        value = value[part]
    if not isinstance(value, list):
        raise TypeError("not a list")
    for item in value:
        print(item)
except Exception as exc:
    print(f"cbr-codex: invalid config list {sys.argv[2]}: {exc}", file=sys.stderr)
    raise SystemExit(2)
PY
}

worktree_path() {
  local root="$1" slug="$2" parent prefix
  parent="$(cfg "$root" worktreeParent ..)"
  prefix="$(cfg "$root" worktreePrefix '')"
  python3 - "$root" "$parent" "$prefix$slug" <<'PY'
import os, sys
print(os.path.abspath(os.path.join(*sys.argv[1:])))
PY
}

run_dir() { printf '%s/.cbr-codex/runs/%s\n' "$(primary_root "$1")" "$2"; }

pid_alive() {
  local pid="${1:-}"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

file_epoch() {
  python3 - "$1" <<'PY'
import os, sys
try: print(int(os.stat(sys.argv[1]).st_mtime))
except OSError: print(0)
PY
}

hash_file() {
  [ -f "$1" ] || { printf 'absent\n'; return; }
  shasum -a 256 "$1" | awk '{print $1}'
}

thread_from_events() {
  python3 - "$1" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        for line in handle:
            try: row = json.loads(line)
            except ValueError: continue
            if row.get("type") == "thread.started" and row.get("thread_id"):
                print(row["thread_id"])
                break
except OSError:
    pass
PY
}

terminal_from_events() {
  python3 - "$1" <<'PY'
import json, sys
terminal = "none"
try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        for line in handle:
            try: kind = json.loads(line).get("type", "")
            except ValueError: continue
            if kind in {"turn.completed", "turn.failed", "error"}:
                terminal = kind
except OSError:
    pass
print(terminal)
PY
}

# cbr push firewall: builders never push; pushing main is the human's, always. Two layers, both
# deny-by-default — the current-branch check alone is bypassable via detached HEAD, a side
# branch, or the primary checkout (proven live 2026-08-27 on the Claude leaf; same body here,
# pinned for both leaves by kit/verify/push-firewall.test.sh).
write_push_firewall() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat >"$path" <<'SH'
#!/bin/sh
branch=$(git symbolic-ref --short HEAD 2>/dev/null)
case "$branch" in
  stream/*)
    if [ "$CBR_ALLOW_PUSH" != "1" ]; then
      echo "pre-push BLOCKED: '$branch' is a builder stream branch — builders never push." >&2
      echo "Intentional human push? re-run with: CBR_ALLOW_PUSH=1 git push" >&2
      exit 1
    fi ;;
esac
# stdin: <local ref> <local sha> <remote ref> <remote sha> per ref being pushed
while read -r _local _lsha remote _rsha; do
  case "$remote" in
    refs/heads/main)
      if [ "$CBR_ALLOW_PUSH" != "1" ]; then
        echo "pre-push BLOCKED: push targets main — main is human-push-only." >&2
        echo "Intentional human push? re-run with: CBR_ALLOW_PUSH=1 git push" >&2
        exit 1
      fi ;;
  esac
done
exit 0
SH
  chmod +x "$path"
}

# Ownership and currency are decided by EXACT BYTES only. A marker substring proves nothing in
# either direction: an old install would read as "already there" forever, and a custom hook that
# merely mentions CBR_ALLOW_PUSH alongside its own enforcement would get clobbered — deleting
# that enforcement silently. So: byte-identical to today's body -> current, untouched; exact
# sha256 of a body a CBR leaf actually shipped -> upgraded in place; no marker -> rc 1 (foreign);
# anything else mentioning the marker -> rc 2 (unrecognized/composed). Both refusals leave the
# hook byte-identical — the caller reports, a human merges.
_fw_sha256() { { shasum -a 256 "$1" 2>/dev/null || sha256sum "$1" 2>/dev/null; } | cut -d' ' -f1; }
ensure_push_firewall() {
  local path="$1" want
  if [ ! -e "$path" ]; then
    write_push_firewall "$path"
    [ -x "$path" ] || return 3   # rc 3: success may never be reported for a hook git will skip
    return 0
  fi
  grep -q "CBR_ALLOW_PUSH" "$path" 2>/dev/null || return 1
  want="$(mktemp)"
  write_push_firewall "$want"
  # a byte-perfect hook with the execute bit stripped is silently skipped by
  # git — the bytes are provably ours, so re-arming the bit is always safe
  if cmp -s "$want" "$path"; then
    rm -f "$want"
    chmod +x "$path" 2>/dev/null || true
    [ -x "$path" ] || return 3
    return 0
  fi
  rm -f "$want"
  case "$(_fw_sha256 "$path")" in
    # claude leaf pre-2026-08-27 (branch-layer only) | codex leaf pre-2026-08-27
    121723d3894c1885cef6fbac5d47b50c26a2feb1b40d8d3a5a8b3192985be584|\
    cd3f4198a9d05fb67960cbb26b797a5c35e74092c56947621800f714dbb52e63)
      write_push_firewall "$path"
      [ -x "$path" ] || return 3
      return 0 ;;
  esac
  return 2
}

put_file() {
  local src="$1" dst="$2" mode="${3:-file}"
  if [ -e "$dst" ]; then
    fact "preserved" "$dst"
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  [ "$mode" = executable ] && chmod +x "$dst"
  fact "installed" "$dst"
}

hooks_hash() {
  local root="$1"
  python3 - "$root" <<'PY'
import hashlib, os, sys
root = sys.argv[1]
paths = [os.path.join(root, ".codex", "hooks.json")]
hooks = os.path.join(root, ".codex", "hooks")
if os.path.isdir(hooks):
    paths += [os.path.join(hooks, p) for p in sorted(os.listdir(hooks))]
h = hashlib.sha256()
for path in paths:
    if not os.path.isfile(path): continue
    h.update(os.path.relpath(path, root).encode() + b"\0")
    h.update(open(path, "rb").read() + b"\0")
print(h.hexdigest())
PY
}

hooks_wiring_check() {
  python3 - "$1" <<'PY'
import json, sys
try: data = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception as exc:
    print(f"invalid JSON: {exc}")
    raise SystemExit(2)
hooks = data.get("hooks", {})
required = {"PreToolUse", "PostToolUse", "SessionStart", "PostCompact", "UserPromptSubmit", "Stop"}
missing = sorted(required - set(hooks))
blob = json.dumps(data)
for needle in ["--agent codex", "@nizos/probity@1.10.0",
               "mark-post-compact.sh", "post-compact-reground.sh", "roborev-gate.sh",
               "roborev-session-sweep.sh", "builder-stop-check.sh",
               "no-interactive-question.sh"]:
    if needle not in blob: missing.append(needle)
if missing:
    print("missing: " + ", ".join(missing))
    raise SystemExit(1)
print("required Codex CBR events and commands present")
PY
}

probity_config_behavior_check() {
  local root="$1"
  (cd "$root" && node --experimental-strip-types --input-type=module -e '
    const { default: config } = await import("./probity.config.ts")
    const { isIntegratedProbityConfig } = await import("./probity-integration.mjs")
    process.exit(isIntegratedProbityConfig(config) ? 0 : 1)
  ' >/dev/null 2>&1)
}

probity_runtime_helpers_check() {
  local root="$1" item
  for item in probity-content-policy.mjs probity-content-policy.d.mts probity-verdict-parser.mjs probity-verdict-parser.d.mts probity-integration.mjs probity-integration.d.mts; do
    cmp -s "$root/$item" "$TPL/$item" || return 1
  done
}

sync_models() {
  local root="$1"
  python3 - "$root/.cbr-codex.json" "$root/.roborev.toml" <<'PY'
import json, re, sys
dial_path, rr_path = sys.argv[1:]
dial = json.load(open(dial_path, encoding="utf-8"))["models"]
text = open(rr_path, encoding="utf-8").read()
replacements = {
    "agent": dial["reviewerAgent"],
    "review_agent": dial["reviewerAgent"],
    "review_model": dial["reviewer"],
    "review_reasoning": dial["reviewerReasoning"],
}
for key, value in replacements.items():
    pattern = rf'(?m)^{re.escape(key)}\s*=\s*"[^"]*"'
    if not re.search(pattern, text):
        raise SystemExit(f"{rr_path}: missing {key}")
    text = re.sub(pattern, f'{key} = "{value}"', text, count=1)
open(rr_path, "w", encoding="utf-8").write(text)
PY
}

model_projection_check() {
  local root="$1"
  python3 - "$root/.cbr-codex.json" "$root/.roborev.toml" "$root/probity.config.ts" <<'PY'
import json, re, sys
dial_path, rr_path, probity_path = sys.argv[1:]
try:
    models = json.load(open(dial_path, encoding="utf-8"))["models"]
    rr = open(rr_path, encoding="utf-8").read()
    probity = open(probity_path, encoding="utf-8").read()
except Exception as exc:
    print(exc); raise SystemExit(2)
for key in ("builder", "builderReasoning", "reviewerAgent", "reviewer", "reviewerReasoning", "probityJudge"):
    if not models.get(key):
        print(f"models.{key} missing"); raise SystemExit(1)
for key, expected in (("agent", models["reviewerAgent"]), ("review_agent", models["reviewerAgent"]), ("review_model", models["reviewer"]), ("review_reasoning", models["reviewerReasoning"])):
    match = re.search(rf'(?m)^{key}\s*=\s*"([^"]+)"', rr)
    if not match or match.group(1) != expected:
        print(f"{key} does not match the dial"); raise SystemExit(1)
if "models.probityJudge" not in probity or "guardedPaths" not in probity:
    print("Probity does not read models.probityJudge and guardedPaths"); raise SystemExit(1)
print("builder, RoboRev, and Probity read/project the single model dial")
PY
}

cmd_arm() {
  local target="${1:-}" fails=0
  [ -n "$target" ] || die "usage: arm <absolute-repo-path>"
  shift || true
  [ "$#" -eq 0 ] || die "usage: arm <absolute-repo-path>"
  target="$(cd "$target" && pwd -P)"
  [ "$(repo_root "$target")" = "$target" ] || die "arm target must be the repository root"
  command -v python3 >/dev/null || die "python3 is required"

  say "arm: target=$target"
  put_file "$TPL/cbr-codex.json" "$target/.cbr-codex.json"
  if [ -e "$target/.codex/config.toml" ]; then
    if grep -q '^model_auto_compact_token_limit[[:space:]]*=' "$target/.codex/config.toml"; then
      fact "Codex config" "compaction threshold already declared; preserved"
    else
      fail "Codex config" "existing .codex/config.toml needs the template compaction setting merged manually"
      fails=$((fails + 1))
    fi
  else
    put_file "$TPL/codex-config.toml" "$target/.codex/config.toml"
  fi

  if [ -e "$target/.agents/skills/codex-controlled-build-run" ]; then
    fact "preserved" ".agents/skills/codex-controlled-build-run"
  else
    mkdir -p "$target/.agents/skills"
    cp -R "$SKILL_DIR" "$target/.agents/skills/codex-controlled-build-run"
    fact "installed" ".agents/skills/codex-controlled-build-run"
  fi

  if [ -e "$target/.codex/hooks.json" ]; then
    if hooks_wiring_check "$target/.codex/hooks.json" >/dev/null; then
      fact "hook wiring" "required behavior already present; preserved"
    else
      fail "hook wiring" "existing .codex/hooks.json needs a manual merge; not overwritten"
      fails=$((fails + 1))
    fi
  else
    put_file "$TPL/codex-hooks.json" "$target/.codex/hooks.json"
  fi
  local hook
  for hook in no-interactive-question.sh mark-post-compact.sh post-compact-reground.sh roborev-gate.sh roborev-session-sweep.sh builder-stop-check.sh; do
    put_file "$TPL/hooks/$hook" "$target/.codex/hooks/$hook" executable
  done

  put_file "$TPL/probity.config.ts" "$target/probity.config.ts"
  put_file "$TPL/probity-content-policy.mjs" "$target/probity-content-policy.mjs"
  put_file "$TPL/probity-content-policy.d.mts" "$target/probity-content-policy.d.mts"
  put_file "$TPL/probity-verdict-parser.mjs" "$target/probity-verdict-parser.mjs"
  put_file "$TPL/probity-verdict-parser.d.mts" "$target/probity-verdict-parser.d.mts"
  put_file "$TPL/probity-integration.mjs" "$target/probity-integration.mjs"
  put_file "$TPL/probity-integration.d.mts" "$target/probity-integration.d.mts"
  if probity_runtime_helpers_check "$target"; then
    fact "Probity runtime" "helper versions exact"
  else
    fail "Probity runtime" "existing helper differs from current skill; manual reconciliation required"
    fails=$((fails + 1))
  fi
  if probity_config_behavior_check "$target"; then
    fact "Probity integration" "required behavior present"
  else
    fail "Probity integration" "existing probity.config.ts needs a manual merge; not overwritten"
    fails=$((fails + 1))
  fi
  local rr_existed=0
  [ -e "$target/.roborev.toml" ] && rr_existed=1
  put_file "$TPL/roborev.toml" "$target/.roborev.toml"
  if [ "$rr_existed" -eq 0 ]; then
    sync_models "$target"
    fact "model projection" "RoboRev generated from .cbr-codex.json"
  elif ! model_projection_check "$target" >/dev/null 2>&1; then
    fail "model projection" "existing .roborev.toml differs from the project dial; reconcile or run sync-models"
    fails=$((fails + 1))
  fi
  put_file "$TPL/pre-commit-config.yaml" "$target/.pre-commit-config.yaml"
  put_file "$TPL/roborev-clean-gate.sh" "$target/.cbr-codex/scripts/roborev-clean-gate.sh" executable
  put_file "$TPL/plan-coherence.sh" "$target/.cbr-codex/scripts/plan-coherence.sh" executable
  put_file "$SELF_DIR/cbr_graph.py" "$target/.cbr-codex/scripts/cbr_graph.py" executable

  if [ ! -e "$target/AGENTS.md" ]; then
    printf '%s\n' '# AGENTS.md' '' 'Use `.agents/skills/codex-controlled-build-run/SKILL.md` for non-trivial builds.' >"$target/AGENTS.md"
    fact "installed" "AGENTS.md CBR pointer"
  else
    fact "preserved" "AGENTS.md"
  fi

  touch "$target/.gitignore"
  local line
  for line in .cbr-codex/runs/ .cbr-codex/watch/ .cbr-codex/hook-trust.sha256 .cbr-codex/provision.json; do
    if ! grep -qxF "$line" "$target/.gitignore"; then
      printf '%s\n' "$line" >>"$target/.gitignore"
      fact "gitignore" "added $line"
    fi
  done

  local pre_push
  pre_push="$(git -C "$target" rev-parse --git-path hooks/pre-push)"
  case "$pre_push" in /*) ;; *) pre_push="$target/$pre_push" ;; esac
  if ensure_push_firewall "$pre_push"; then
    fact "push firewall" "$pre_push (current: branch layer + pushed-ref layer)"
  else
    case "$?" in
      2) fail "push firewall" "hook at $pre_push mentions CBR_ALLOW_PUSH but is not a known CBR body — left untouched; merge manually" ;;
      3) fail "push firewall" "hook at $pre_push could NOT be made executable — git will silently skip it; fix permissions and re-run" ;;
      *) fail "push firewall" "foreign hook at $pre_push; merge manually" ;;
    esac
    fails=$((fails + 1))
  fi

  local pre_commit
  pre_commit="$(git -C "$target" rev-parse --git-path hooks/pre-commit)"
  case "$pre_commit" in /*) ;; *) pre_commit="$target/$pre_commit" ;; esac
  if [ ! -e "$pre_commit" ]; then
    if command -v pre-commit >/dev/null && (cd "$target" && pre-commit install >/dev/null); then
      fact "pre-commit" "installed"
    else
      fail "pre-commit" "install unavailable or failed"
      fails=$((fails + 1))
    fi
  elif grep -q pre-commit "$pre_commit" 2>/dev/null; then
    fact "pre-commit" "existing framework hook preserved"
  else
    fail "pre-commit" "foreign hook at $pre_commit; merge manually"
    fails=$((fails + 1))
  fi

  local rr_hook rr_name
  for rr_name in post-commit post-rewrite; do
    rr_hook="$(git -C "$target" rev-parse --path-format=absolute --git-path "hooks/$rr_name")"
    if [ -e "$rr_hook" ] && ! grep -qi roborev "$rr_hook" 2>/dev/null; then
      fail "RoboRev Git hook" "foreign $rr_name at $rr_hook; merge manually"
      fails=$((fails + 1))
    elif [ ! -e "$rr_hook" ]; then
      put_file "$TPL/git-hooks/$rr_name" "$rr_hook" executable
    else
      fact "RoboRev Git hook" "$rr_name present"
    fi
  done

  say "SUMMARY arm_failures=$fails"
  [ "$fails" -eq 0 ] || return 1
  say "NEXT start Codex terminal TUI in $target; at 'Hooks need review', inspect and trust every hook"
  say "NEXT after Codex trust: $0 record-hook-trust $target"
  say "NEXT after trust is recorded: $0 probe $target"
  return 0
}

cmd_record_hook_trust() {
  local root
  root="$(repo_root "${1:-$PWD}")"
  hooks_wiring_check "$root/.codex/hooks.json" >/dev/null || die "hook wiring is incomplete"
  mkdir -p "$root/.cbr-codex"
  hooks_hash "$root" >"$root/.cbr-codex/hook-trust.sha256"
  fact "hook vet record" "$(cat "$root/.cbr-codex/hook-trust.sha256")"
}

cmd_sync_models() {
  local root
  root="$(repo_root "${1:-$PWD}")"
  sync_models "$root"
  model_projection_check "$root"
}

cmd_doctor() {
  local root="$(repo_root "${1:-$PWD}")" fails=0 item
  say "doctor: repo=$root"
  if python3 -m json.tool "$root/.cbr-codex.json" >/dev/null 2>&1; then
    fact "config" "valid JSON"
  else fail "config" ".cbr-codex.json absent/invalid"; fails=$((fails+1)); fi
  if grep -q 'EDIT-ME' "$root/.cbr-codex.json" 2>/dev/null || grep -qE 'wire (static checks|tests)' "$root/.pre-commit-config.yaml" 2>/dev/null; then
    fail "port knobs" "placeholder remains in live deterministic config"; fails=$((fails+1))
  else fact "port knobs" "live deterministic commands declared"; fi
  if [ -f "$root/.agents/skills/codex-controlled-build-run/SKILL.md" ] || [ -f "$root/skills/codex-controlled-build-run/SKILL.md" ]; then
    fact "skill" "discoverable source present"
  else fail "skill" "Codex CBR SKILL.md missing"; fails=$((fails+1)); fi
  if hooks_wiring_check "$root/.codex/hooks.json" >/dev/null 2>&1; then
    fact "hook wiring" "required events and commands present"
  else fail "hook wiring" "missing/invalid .codex/hooks.json"; fails=$((fails+1)); fi
  for item in no-interactive-question.sh mark-post-compact.sh post-compact-reground.sh roborev-gate.sh roborev-session-sweep.sh builder-stop-check.sh; do
    [ -x "$root/.codex/hooks/$item" ] && fact "hook executable" "$item" || {
      fail "hook executable" "$item"; fails=$((fails+1));
    }
  done
  local compact_expected compact_live
  compact_expected="$(cfg "$root" autoCompactTokenLimit 0)"
  compact_live="$(sed -nE 's/^model_auto_compact_token_limit[[:space:]]*=[[:space:]]*([0-9]+).*/\1/p' "$root/.codex/config.toml" 2>/dev/null | head -1)"
  [ "$compact_expected" = "$compact_live" ] && fact "compaction limit" "$compact_live" || { fail "compaction limit" "config=${compact_live:-absent} project=$compact_expected"; fails=$((fails+1)); }
  local expected actual
  expected="$(cat "$root/.cbr-codex/hook-trust.sha256" 2>/dev/null || true)"
  actual="$(hooks_hash "$root")"
  if [ -n "$expected" ] && [ "$expected" = "$actual" ]; then
    fact "hook vet record" "$actual"
  else fail "hook vet record" "missing or stale; review/trust in Codex terminal TUI, then record-hook-trust"; fails=$((fails+1)); fi
  if [ -f "$root/probity.config.ts" ] && [ -f "$root/probity-content-policy.mjs" ] && [ -f "$root/probity-content-policy.d.mts" ] && [ -f "$root/probity-verdict-parser.mjs" ] && [ -f "$root/probity-verdict-parser.d.mts" ] && [ -f "$root/probity-integration.mjs" ] && [ -f "$root/probity-integration.d.mts" ]; then
    fact "Probity config" "config and runtime helpers present"
  else
    fail "Probity config" "config or runtime helper missing"
    fails=$((fails+1))
  fi
  if probity_runtime_helpers_check "$root"; then
    fact "Probity runtime" "helper versions exact"
  else
    fail "Probity runtime" "helper drift from installed skill"
    fails=$((fails+1))
  fi
  if probity_config_behavior_check "$root"; then
    fact "Probity integration" "required behavior present"
  else
    fail "Probity integration" "stale config; merge current isolation, content-policy, and parser integrations"
    fails=$((fails+1))
  fi
  [ -f "$root/.roborev.toml" ] && fact "RoboRev config" "present" || { fail "RoboRev config" "missing"; fails=$((fails+1)); }
  if model_projection_check "$root" >/dev/null 2>&1; then fact "model dial" "builder/reviewer/judge projections agree"; else fail "model dial" "configuration drift"; fails=$((fails+1)); fi
  [ -x "$root/.cbr-codex/scripts/roborev-clean-gate.sh" ] && fact "review clean gate" "executable" || { fail "review clean gate" "missing"; fails=$((fails+1)); }
  [ -x "$root/.cbr-codex/scripts/plan-coherence.sh" ] && fact "plan coherence" "executable" || { fail "plan coherence" "missing"; fails=$((fails+1)); }
  if grep -q roborev-clean "$root/.pre-commit-config.yaml" 2>/dev/null && grep -q plan-coherence "$root/.pre-commit-config.yaml" 2>/dev/null; then
    fact "pre-commit config" "review and plan gates wired"
  else fail "pre-commit config" "tracked gates missing"; fails=$((fails+1)); fi
  local pre_commit pre_push
  pre_commit="$(git -C "$root" rev-parse --path-format=absolute --git-path hooks/pre-commit)"
  pre_push="$(git -C "$root" rev-parse --path-format=absolute --git-path hooks/pre-push)"
  [ -x "$pre_commit" ] && fact "Git pre-commit" "$pre_commit" || { fail "Git pre-commit" "$pre_commit"; fails=$((fails+1)); }
  if [ -x "$pre_push" ] && grep -q CBR_ALLOW_PUSH "$pre_push"; then
    want_pp="$(mktemp)"; write_push_firewall "$want_pp"
    if cmp -s "$want_pp" "$pre_push"; then
      fact "push firewall" "$pre_push"
    else
      fail "push firewall" "stale or edited body at $pre_push — re-run provision to upgrade"; fails=$((fails+1))
    fi
    rm -f "$want_pp"
  else fail "push firewall" "$pre_push"; fails=$((fails+1)); fi
  for item in codex roborev pre-commit gitleaks python3 git node jq; do
    command -v "$item" >/dev/null && fact "command" "$item" || { fail "command" "$item"; fails=$((fails+1)); }
  done
  if [ -x "$root/node_modules/.bin/probity" ] && node -e 'const p=require("./node_modules/@nizos/probity/package.json"); process.exit(p.version === "1.10.0" ? 0 : 1)' >/dev/null 2>&1; then
    fact "Probity dependency" "@nizos/probity 1.10.0 installed locally"
  else fail "Probity dependency" "install pinned @nizos/probity@1.10.0 locally"; fails=$((fails+1)); fi
  if (cd "$root" && node --input-type=module -e 'await import("@openai/codex-sdk")' >/dev/null 2>&1); then
    fact "Probity judge SDK" "@openai/codex-sdk resolvable"
  else fail "Probity judge SDK" "install @openai/codex-sdk locally"; fails=$((fails+1)); fi
  if probity_config_behavior_check "$root"; then
    fact "Probity config load" "complete config imports with private integration attestation"
  else fail "Probity config load" "config import or active integration check failed"; fails=$((fails+1)); fi
  local rr_status
  rr_status="$(cd "$root" && roborev status --json 2>/dev/null || true)"
  if command -v roborev >/dev/null && printf '%s' "$rr_status" | python3 -c 'import json,sys; raise SystemExit(0 if json.load(sys.stdin).get("running") is True else 1)' 2>/dev/null; then
    fact "RoboRev daemon" "reachable"
  else fail "RoboRev daemon" "reported stopped or status unavailable"; fails=$((fails+1)); fi
  local rr_git
  for item in post-commit post-rewrite; do
    rr_git="$(git -C "$root" rev-parse --path-format=absolute --git-path "hooks/$item")"
    if [ -x "$rr_git" ] && grep -qi roborev "$rr_git"; then fact "RoboRev Git hook" "$item"; else fail "RoboRev Git hook" "$item"; fails=$((fails+1)); fi
  done
  if [ -f "$root/task_plan.md" ]; then
    local branch planned
    branch="$(git -C "$root" branch --show-current)"
    planned="$(sed -nE 's/.*\*\*Branch:\*\*[[:space:]]*([^ ·]+).*/\1/p' "$root/task_plan.md" | head -1)"
    [ "$branch" = "$planned" ] && fact "strand branch" "$branch" || { fail "strand branch" "git=$branch plan=${planned:-absent}"; fails=$((fails+1)); }
    for item in task_plan.md findings.md progress.md; do [ -f "$root/$item" ] || { fail "planning file" "$item"; fails=$((fails+1)); }; done
  fi
  # WARN-ONLY: stale harness tooling (strand-lib probe; fails open on missing
  # tools/network). Outside $fails — updating is a human decision, never a gate.
  if command -v cbr_tool_staleness_report >/dev/null 2>&1; then
    local pin stale
    pin="$(sed -nE 's/.*@nizos\/probity@([0-9][0-9.]*).*/\1/p' "$root/.cbr-codex.json" 2>/dev/null | head -1)"
    [ -n "$pin" ] || pin="1.10.0"
    while IFS= read -r stale; do
      [ -n "$stale" ] && say "WARN $stale"
    done < <(cbr_tool_staleness_report "$pin")
  fi
  say "SUMMARY checks_failed=$fails"
  [ "$fails" -eq 0 ]
}

cmd_probe() {
  local root="$(repo_root "${1:-$PWD}")" primary model reason stamp out expected actual
  primary="$(primary_root "$root")"
  expected="$(cat "$primary/.cbr-codex/hook-trust.sha256" 2>/dev/null || true)"; actual="$(hooks_hash "$root")"
  [ -n "$expected" ] && [ "$expected" = "$actual" ] || die "probe refuses unvetted or changed Codex hooks"
  model="$(cfg "$root" models.builder '')"; reason="$(cfg "$root" models.builderReasoning high)"
  [ -n "$model" ] || die "probe builder model missing"
  command -v codex >/dev/null || die "codex missing"
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"; out="$primary/.cbr-codex/probes/$stamp"
  mkdir -p "$out"
  fact "probe model" "$model reasoning=$reason root=$root"
  codex exec --sandbox workspace-write -c 'approval_policy="never"' \
    -c "model_reasoning_effort=\"$reason\"" --dangerously-bypass-hook-trust \
    --json -C "$root" -m "$model" -o "$out/final.txt" - \
    <"$SKILL_DIR/templates/probe-prompt.md" >"$out/events.jsonl" 2>"$out/stderr.log" || true
  [ -f "$out/final.txt" ] && cat "$out/final.txt"
  grep -qE '^PROBE-RESULT: (PROVE-NO BLOCKED / PROVE-ADAPTER BLOCKED / PROVE-PATCH BLOCKED / PROVE-YES OK|PASS-WITH-NOTE)' "$out/final.txt" 2>/dev/null
}

cmd_provision() {
  local slug="${1:-}" branch="${2:-}" base="HEAD" root wt fails=0 command hook_out
  [ -n "$slug" ] && [ -n "$branch" ] || die "usage: provision <slug> <branch> [--base <ref>]"
  shift 2
  if [ "${1:-}" = "--base" ]; then base="${2:-}"; [ -n "$base" ] || die "--base needs a ref"; fi
  root="$(repo_root)"; wt="$(worktree_path "$root" "$slug")"
  [[ "$branch" =~ $(cfg "$root" builderBranchPattern '^stream/') ]] || die "branch $branch does not match builderBranchPattern"
  git -C "$root" show-ref --verify --quiet "refs/heads/$branch" && die "branch already exists: $branch"
  [ ! -e "$wt" ] || die "worktree path exists: $wt"
  fact "provision" "slug=$slug branch=$branch base=$base worktree=$wt"
  git -C "$root" worktree add "$wt" -b "$branch" "$base" >/dev/null
  # Shared-core birth duties: drop the base's inherited STATUS/DONE/ASK records
  # (a dead strand's "COMPLETE" must never greet a watcher of THIS strand), and
  # pin the base so launch can prove the branch still grows from it.
  if command -v cbr_provision_reset_stale_records >/dev/null; then
    cbr_provision_reset_stale_records "$wt" >/dev/null || { fail "stale record reset" "$wt"; fails=$((fails+1)); }
  else fail "shared strand library" "cbr_provision_reset_stale_records missing"; fails=$((fails+1)); fi
  if command -v cbr_record_strand_base >/dev/null && cbr_record_strand_base "$root" "$branch" "$branch" >/dev/null; then
    fact "base pin" "branch.$branch.cbrBase"
  else fail "base pin" "could not record"; fails=$((fails+1)); fi
  mkdir -p "$wt/.cbr-codex"
  printf '{"result":"INCOMPLETE","branch":"%s","base":"%s","started":%s}\n' "$branch" "$base" "$(date +%s)" >"$wt/.cbr-codex/provision.json"
  if [ ! -f "$wt/task_plan.md" ]; then
    sed -e "s|stream/<slug>|$branch|" -e "s|<absolute worktree path>|$wt|" "$TPL/task_plan.skeleton.md" >"$wt/task_plan.md"
  fi
  [ -f "$wt/findings.md" ] || printf '# findings.md — %s\n\nDurable decisions and human forks.\n' "$branch" >"$wt/findings.md"
  printf '# progress.md — %s\n\nNewest entries first. Stream-only log created at provision.\n' "$branch" >"$wt/progress.md"
  while IFS= read -r command; do
    [ -n "$command" ] || continue
    fact "setup command" "$command"
    (cd "$wt" && sh -lc "$command") || fails=$((fails+1))
  done < <(cfg_lines "$root" setupCommands)
  # Project prep-hook socket (shared core): .cbr/provision-hook.sh at the
  # primary root, run in the worktree — the stack-specific prep that must not
  # live in the neutral core or a leaf. Absent = normal skip; failure = FAIL.
  if command -v cbr_run_provision_hook >/dev/null; then
    if hook_out="$(cbr_run_provision_hook "$(primary_root "$root")" "$wt")"; then
      case "$hook_out" in *hook=ran*) fact "provision hook" ".cbr/provision-hook.sh";; esac
    else fail "provision hook" ".cbr/provision-hook.sh"; fails=$((fails+1)); fi
  fi
  command="$(cfg "$root" toolchainProbe EDIT-ME)"
  if [ -n "$command" ] && [ "$command" != EDIT-ME ] && (cd "$wt" && sh -lc "$command"); then
    fact "toolchain probe" "$command"
  else fail "toolchain probe" "$command"; fails=$((fails+1)); fi
  grep -q roborev-clean "$wt/.pre-commit-config.yaml" 2>/dev/null || { fail "gate inheritance" "roborev-clean missing"; fails=$((fails+1)); }
  grep -q plan-coherence "$wt/.pre-commit-config.yaml" 2>/dev/null || { fail "gate inheritance" "plan-coherence missing"; fails=$((fails+1)); }
  if [ "$fails" -eq 0 ]; then
    printf '{"result":"PASS","branch":"%s","base":"%s","completed":%s,"base_sha":"%s"}\n' \
      "$branch" "$base" "$(date +%s)" "$(git -C "$wt" rev-parse "$base")" >"$wt/.cbr-codex/provision.json"
  fi
  say "SUMMARY provision_failures=$fails"
  [ "$fails" -eq 0 ]
}

launch_process() {
  local mode="$1" run="$2" wt="$3" thread="$4" model="$5" reason="$6" prompt="$7"
  if [ "$mode" = resume ]; then
    nohup codex exec --sandbox workspace-write -c 'approval_policy="never"' \
      -c "model_reasoning_effort=\"$reason\"" --dangerously-bypass-hook-trust \
      --json -C "$wt" -m "$model" -o "$run/final.txt" resume "$thread" - \
      <"$prompt" >"$run/events.jsonl" 2>"$run/stderr.log" &
  else
    nohup codex exec --sandbox workspace-write -c 'approval_policy="never"' \
      -c "model_reasoning_effort=\"$reason\"" --dangerously-bypass-hook-trust \
      --json -C "$wt" -m "$model" -o "$run/final.txt" - \
      <"$prompt" >"$run/events.jsonl" 2>"$run/stderr.log" &
  fi
  printf '%s\n' "$!" >"$run/pid"
}

cmd_launch() {
  local slug="${1:-}" prompt="" model="" reason="" root wt run pid thread i
  [ -n "$slug" ] || die "usage: launch <slug> --prompt-file <file> [--model ID] [--reasoning LEVEL]"
  shift
  while [ "$#" -gt 0 ]; do case "$1" in
    --prompt-file) prompt="${2:-}"; shift 2;;
    --model) model="${2:-}"; shift 2;;
    --reasoning) reason="${2:-}"; shift 2;;
    *) die "unknown launch argument: $1";; esac; done
  [ -f "$prompt" ] || die "--prompt-file must exist"
  root="$(repo_root)"; wt="$(worktree_path "$root" "$slug")"; run="$(run_dir "$root" "$slug")"
  [ -d "$wt" ] || die "missing worktree: $wt"
  grep -q '"result":"PASS"' "$wt/.cbr-codex/provision.json" 2>/dev/null || die "provision PASS not recorded in this worktree"
  # Base pin (shared core): rc=1 = the branch does not contain its recorded
  # base — the wrong-base fork, refused before dispatch; rc=2 = pre-pin strand.
  local pin_branch pin_rc=0
  pin_branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  if command -v cbr_assert_strand_base >/dev/null && [ -n "$pin_branch" ]; then
    cbr_assert_strand_base "$root" "$pin_branch" >/dev/null 2>&1 || pin_rc=$?
    case "$pin_rc" in
      0) ;;
      2) say "WARN no base pin recorded for $pin_branch (pre-pin strand); base check skipped" ;;
      *) die "branch $pin_branch does not contain its recorded base (branch.$pin_branch.cbrBase) — wrong-base fork; re-provision before dispatch" ;;
    esac
  fi
  [ ! -e "$run" ] || die "run registry already exists: $run; use resume or closeout"
  model="${model:-$(cfg "$root" models.builder '')}"; reason="${reason:-$(cfg "$root" models.builderReasoning high)}"
  [ -n "$model" ] || die "builder model missing"
  local expected actual
  expected="$(cat "$(primary_root "$root")/.cbr-codex/hook-trust.sha256" 2>/dev/null || true)"; actual="$(hooks_hash "$wt")"
  [ -f "$root/.cbr-fleet.json" ] && "$SELF_DIR/cbr_graph.py" dispatchable "$root/.cbr-fleet.json" "$slug" --repo "$(primary_root "$root")" --plan "$root/task_plan.md" --worktree "$wt"
  [ -n "$expected" ] && [ "$expected" = "$actual" ] || die "worktree hook sources do not match the vetted hash"
  local occupied locc=2
  occupied="$(python3 - "$(primary_root "$root")/.cbr-codex/runs" "$wt" <<'PY'
import json, os, pathlib, sys
runs, target = pathlib.Path(sys.argv[1]), os.path.realpath(sys.argv[2])
if runs.is_dir():
    for run in runs.iterdir():
        try:
            meta = json.loads((run / "meta.json").read_text())
            pid = int((run / "pid").read_text())
            if os.path.realpath(meta.get("worktree", "")) != target:
                continue
            os.kill(pid, 0)
            print(f"{run.name}:{pid}")
            break
        except (OSError, ValueError, KeyError, json.JSONDecodeError):
            continue
PY
)"
  [ -z "$occupied" ] || die "another live registry owns $wt ($occupied)"
  # The registry only knows the runs IT recorded. A worktree being driven
  # interactively, or by another harness, is invisible to it, and dispatching a
  # second writer there is the same race by a route the registry cannot see. One
  # writer per worktree, wider evidence — and a rule that evaporates when a tool
  # is missing is not a rule, so an unprovable answer refuses unless a human
  # says otherwise in as many words.
  if command -v cbr_path_has_live_process >/dev/null; then
    if cbr_path_has_live_process "$wt"; then locc=0; else locc=$?; fi
  else locc=2; fi
  case "$locc" in
    0) die "a live process is already rooted in $wt (interactive session, or another harness) — refusing to dispatch a second writer into an occupied worktree" ;;
    1) ;;
    *) [ "${CBR_ALLOW_UNPROVEN_OCCUPANCY:-}" = "1" ] \
         || die "the process table could not be inspected, so an occupant of $wt cannot be ruled out — refusing to dispatch a second writer on an unproven answer. Install lsof, or re-run with CBR_ALLOW_UNPROVEN_OCCUPANCY=1 if you have checked by hand." ;;
  esac
  mkdir -p "$run"
  cp "$prompt" "$run/prompt.txt"
  python3 - "$run/meta.json" "$slug" "$wt" "$model" "$reason" <<'PY'
import json, sys, time
path, slug, wt, model, reason = sys.argv[1:]
json.dump({"slug":slug,"worktree":wt,"model":model,"reasoning":reason,"launched":int(time.time()),"resume_count":0}, open(path,"w"), indent=2)
PY
  fact "launch model" "$model reasoning=$reason worktree=$wt sandbox=workspace-write approval=never"
  launch_process launch "$run" "$wt" "" "$model" "$reason" "$run/prompt.txt"
  pid="$(cat "$run/pid")"
  thread=""
  for i in $(seq 1 20); do
    thread="$(thread_from_events "$run/events.jsonl")"
    [ -n "$thread" ] && break
    pid_alive "$pid" || break
    sleep 1
  done
  [ -n "$thread" ] || die "builder did not emit thread.started; inspect $run"
  printf '%s\n' "$thread" >"$run/thread-id"
  mkdir -p "$(primary_root "$root")/.cbr-codex/watch"
  : >"$(primary_root "$root")/.cbr-codex/watch/$slug.needs-arm"
  fact "launched" "pid=$pid thread=$thread registry=$run"
  say "REQUIRED NEXT: $0 watch $slug"
  say "REQUIRED NEXT: $0 watch $slug --watchdog"
}

cmd_resume() {
  local slug="${1:-}" prompt="" root wt run pid thread model reason phase count limit
  [ -n "$slug" ] || die "usage: resume <slug> [--prompt-file <file>]"
  shift
  [ "${1:-}" = "--prompt-file" ] && { prompt="${2:-}"; shift 2; }
  root="$(repo_root)"; wt="$(worktree_path "$root" "$slug")"; run="$(run_dir "$root" "$slug")"
  [ -d "$run" ] || die "run registry missing"
  pid="$(cat "$run/pid" 2>/dev/null || true)"; pid_alive "$pid" && die "recorded builder is still alive: $pid"
  thread="$(cat "$run/thread-id" 2>/dev/null || true)"; [ -n "$thread" ] || die "thread id missing"
  [ -n "$prompt" ] || prompt="$TPL/resume-prompt.md"; [ -f "$prompt" ] || die "resume prompt missing"
  phase="$(grep -m1 -E '^- \[ \] (P|Phase|Stage)[0-9]+' "$wt/task_plan.md" 2>/dev/null | sed -E 's/^- \[ \] ([^ —:]+).*/\1/' || true)"
  [ -n "$phase" ] || phase="no-unchecked-phase"
  limit="$(cfg "$root" samePhaseCrashLimit 2)"
  count="$(python3 - "$run/meta.json" "$phase" <<'PY'
import json, sys
path, phase = sys.argv[1:]
data = json.load(open(path, encoding="utf-8"))
old = data.get("last_resume_phase")
count = int(data.get("same_phase_resume_count", 0)) + 1 if old == phase else 1
data["last_resume_phase"] = phase
data["same_phase_resume_count"] = count
data["resume_count"] = int(data.get("resume_count", 0)) + 1
json.dump(data, open(path, "w", encoding="utf-8"), indent=2)
print(count)
PY
)"
  if [ "$count" -gt "$limit" ]; then
    printf '{"phase":"%s","attempts":%s,"limit":%s,"recorded":%s}\n' "$phase" "$count" "$limit" "$(date +%s)" >"$run/crash-storm.json"
    die "same-phase resume limit exceeded for $phase (attempts=$count limit=$limit); human action required"
  fi
  cp "$run/events.jsonl" "$run/events.previous.$(date +%s).jsonl"
  cp "$prompt" "$run/resume-prompt.txt"
  model="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["model"])' "$run/meta.json")"
  reason="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["reasoning"])' "$run/meta.json")"
  fact "resume model" "$model reasoning=$reason worktree=$wt thread=$thread phase=$phase same_phase_attempt=$count/$limit"
  launch_process resume "$run" "$wt" "$thread" "$model" "$reason" "$run/resume-prompt.txt"
  : >"$(primary_root "$root")/.cbr-codex/watch/$slug.needs-arm"
  fact "resumed" "pid=$(cat "$run/pid") thread=$thread"
}

cmd_status() {
  local slug="${1:-}" root wt run pid alive=0 terminal thread now event_age commit_age branch reviews dirty done ask hard=0
  [ -n "$slug" ] || die "usage: status <slug>"
  root="$(repo_root)"; wt="$(worktree_path "$root" "$slug")"; run="$(run_dir "$root" "$slug")"
  [ -d "$run" ] || die "registry missing: $run"
  pid="$(cat "$run/pid" 2>/dev/null || true)"; pid_alive "$pid" && alive=1
  thread="$(cat "$run/thread-id" 2>/dev/null || thread_from_events "$run/events.jsonl")"
  terminal="$(terminal_from_events "$run/events.jsonl")"; now="$(date +%s)"
  event_age=$((now - $(file_epoch "$run/events.jsonl")))
  if [ -d "$wt" ]; then
    branch="$(git -C "$wt" branch --show-current 2>/dev/null || true)"
    commit_age=$((now - $(git -C "$wt" log -1 --format=%ct 2>/dev/null || printf '%s' "$now")))
    dirty="$(git -C "$wt" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    done="$(hash_file "$wt/DONE.marker")"; ask="$(hash_file "$wt/ASK-ORCH.md")"
    reviews="$(roborev list --open --json --branch "$branch" 2>/dev/null || printf 'unreadable')"
  else branch=missing; commit_age=-1; dirty=-1; done=absent; ask=absent; reviews=unreadable; hard=1; fi
  fact "slug" "$slug"
  fact "worktree" "$wt"
  fact "branch" "$branch"
  fact "process" "pid=${pid:-absent} alive=$alive"
  fact "thread" "${thread:-absent}"
  fact "event stream" "terminal=$terminal age_seconds=$event_age"
  fact "last commit" "age_seconds=$commit_age dirty_paths=$dirty"
  fact "DONE marker" "$done"
  fact "question marker" "$ask"
  [ -f "$run/crash-storm.json" ] && fact "crash storm" "$(cat "$run/crash-storm.json")"
  fact "open reviews" "$reviews"
  local sentinel="$(primary_root "$root")/.cbr-codex/watch/$slug.needs-arm"
  [ -e "$sentinel" ] && fact "watch ownership" "UNWATCHED sentinel present" || fact "watch ownership" "sentinel absent"
  # A registered pid that is gone is not proof the folder is idle: an INTERACTIVE
  # session appears in no registry, and treating that as death invites a second
  # builder onto live work or a reap of an occupied worktree. Occupancy is a live
  # process rooted in the worktree, and it is reported either way so the reader
  # sees which fact decided it.
  local occupied=unknown occ=2
  if [ -d "$wt" ] && command -v cbr_path_has_live_process >/dev/null; then
    # `cmd; occ=$?` would abort under `set -e` on the non-zero returns that
    # are this function's whole point.
    if cbr_path_has_live_process "$wt"; then occ=0; else occ=$?; fi
    case "$occ" in 0) occupied=yes ;; 1) occupied=no ;; *) occupied=unknown ;; esac
  fi
  local occnote=""
  [ "$alive" -eq 0 ] && [ "$occupied" = yes ] && occnote=" INTERACTIVE — no registered session, but somebody is working here; do NOT relaunch or reap"
  [ "$occupied" = unknown ] && occnote=" UNPROVEN — the process table could not be inspected; do not reap or take this strand over on the strength of this"
  fact "folder occupancy" "live_process=$occupied$occnote"
  # Only a PROVEN empty folder joins the hard-dead facts. "Could not look" must
  # not read as "nobody is there" now that a death verdict licenses a takeover.
  if [ "$alive" -eq 0 ] && [ "$done" = absent ] && [ "$occupied" = no ]; then hard=1; fi
  # "Could not look" is only a hard fact when nothing else answers the question.
  # A strand with a LIVE registered session is demonstrably alive whatever the
  # process table says, and failing status for it would page an orchestrator on
  # every poll, forever, on any host without a usable lsof — the Claude leaf
  # returns 0 in exactly that case, and one law cannot give two answers.
  if [ "$alive" -eq 0 ] && [ "$occupied" = unknown ]; then hard=1; fi
  [ "$reviews" = unreadable ] && hard=1
  return "$hard"
}

cmd_watch() {
  local slug="${1:-}"; [ -n "$slug" ] || die "usage: watch <slug> [--watchdog]"
  shift || true
  exec "$SELF_DIR/captain-watch-codex.sh" "$slug" "$@"
}

cmd_fleet() {
  local root runs d slug rc=0
  root="$(primary_root)"; runs="$root/.cbr-codex/runs"
  [ -d "$runs" ] || { fact "fleet registry" "absent"; return 1; }
  for d in "$runs"/*; do [ -d "$d" ] || continue; slug="$(basename "$d")"; say "--- $slug"; cmd_status "$slug" || rc=1; done
  return "$rc"
}

cmd_graph_check() {
  local file="${1:-.cbr-fleet.json}" root
  root="$(primary_root)"
  [ -f "$file" ] || die "fleet file missing: $file"
  "$SELF_DIR/cbr_graph.py" check "$file" --repo "$root" --plan "$root/task_plan.md"
}

cmd_dispatchable() {
  local slug="${1:-}" file="${2:-.cbr-fleet.json}" root wt
  [ -n "$slug" ] || die "usage: dispatchable <slug> [fleet-json]"
  root="$(primary_root)"
  wt="$(worktree_path "$root" "$slug")"
  "$SELF_DIR/cbr_graph.py" dispatchable "$file" "$slug" --repo "$root" --plan "$root/task_plan.md" --worktree "$wt"
}

checkpoint_check() {
  python3 - "$1" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
rows = re.findall(
    r"^\|\s*((?:P|Phase|Stage)[0-9]+)\s*\|\s*([0-9a-f]{7,40}|pending)\s*\|\s*([0-9a-f]{7,40}|pending)\s*\|",
    text, re.I | re.M,
)
if not rows:
    print("checkpoint ledger has no phase rows", file=sys.stderr); raise SystemExit(1)
for phase, end_sha, reviewed in rows:
    if end_sha.lower() == "pending" or reviewed.lower() == "pending" or end_sha != reviewed:
        print(f"checkpoint {phase} incomplete: end_sha={end_sha} reviewed={reviewed}", file=sys.stderr)
        raise SystemExit(1)
print(f"checkpoint_rows={len(rows)} all_reviewed=true")
PY
}

reviews_empty() {
  python3 -c 'import json,sys; value=json.load(sys.stdin); raise SystemExit(0 if value is None or value == [] else 1)'
}

cmd_merge_facts() {
  local slug="${1:-}" into="" root wt run branch unchecked reviews dirty command source_sha fails=0
  [ -n "$slug" ] || die "usage: merge-facts <slug> --into <integration-branch>"
  shift; [ "${1:-}" = --into ] && into="${2:-}"; [ -n "$into" ] || die "--into required"
  root="$(repo_root)"; wt="$(worktree_path "$root" "$slug")"; run="$(run_dir "$root" "$slug")"; branch="$(git -C "$wt" branch --show-current)"
  fact "merge source" "$branch"; fact "merge destination" "$into"; fact "destination checkout" "$(git -C "$root" branch --show-current)"
  [[ "$into" =~ $(cfg "$root" integrationBranchPattern '^integration/') ]] || { fail "merge destination" "does not match integration pattern"; return 1; }
  [ "$(git -C "$root" branch --show-current)" = "$into" ] || { fail "destination checkout" "wrong branch"; return 1; }
  unchecked="$(grep -cE '^- \[ \] (P|Phase|Stage)[0-9]+' "$wt/task_plan.md" || true)"
  [ "$unchecked" -eq 0 ] || { fail "plan" "$unchecked unchecked phases"; return 1; }
  checkpoint_check "$wt/task_plan.md" || { fail "checkpoints" "end_sha/reviewed mismatch or pending"; return 1; }
  fact "checkpoints" "all phase rows stamped"
  dirty="$(git -C "$wt" status --porcelain | wc -l | tr -d ' ')"; [ "$dirty" -eq 0 ] || { fail "dirty worktree" "$dirty paths"; return 1; }
  reviews="$(roborev list --open --json --branch "$branch" 2>/dev/null || printf unreadable)"
  printf '%s' "$reviews" | reviews_empty || { fail "reviews" "$reviews"; return 1; }
  [ -z "$(git -C "$wt" status --porcelain -- findings.md)" ] || { fail "findings" "uncommitted"; return 1; }
  while IFS= read -r command; do
    [ -n "$command" ] || continue
    fact "verification command" "$command"
    (cd "$wt" && sh -lc "$command") || fails=$((fails + 1))
  done < <(cfg_lines "$root" verificationCommands)
  [ "$fails" -eq 0 ] || { fail "verification" "$fails command(s) failed"; return 1; }
  source_sha="$(git -C "$wt" rev-parse HEAD)"
  mkdir -p "$run"
  printf '{"source_branch":"%s","source_sha":"%s","destination":"%s","verified":%s}\n' "$branch" "$source_sha" "$into" "$(date +%s)" >"$run/merge-facts.json"
  fact "merge facts record" "$run/merge-facts.json"
  fact "live smoke after merge" "required: $0 live-smoke $slug --into $into"
}

cmd_live_smoke() {
  local slug="${1:-}" into="" root run record source_sha command
  [ -n "$slug" ] || die "usage: live-smoke <slug> --into <branch>"
  shift; [ "${1:-}" = --into ] && into="${2:-}"; [ -n "$into" ] || die "--into required"
  root="$(repo_root)"; run="$(run_dir "$root" "$slug")"; record="$run/merge-facts.json"
  [ "$(git -C "$root" branch --show-current)" = "$into" ] || die "live smoke must run on destination branch $into"
  [ -f "$record" ] || die "merge-facts record missing"
  source_sha="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_sha"])' "$record")"
  git -C "$root" merge-base --is-ancestor "$source_sha" HEAD || die "source SHA is not merged into current destination"
  command="$(cfg "$root" liveSmokeCommand EDIT-ME)"
  [ -n "$command" ] && [ "$command" != EDIT-ME ] || die "liveSmokeCommand is not configured"
  fact "live smoke command" "$command"
  (cd "$root" && sh -lc "$command") || return 1
  printf '{"source_sha":"%s","destination":"%s","merged_head":"%s","smoked":%s}\n' "$source_sha" "$into" "$(git -C "$root" rev-parse HEAD)" "$(date +%s)" >"$run/live-smoke.json"
  fact "live smoke record" "$run/live-smoke.json"
}

cmd_closeout() {
  local slug="${1:-}" into="" force=0 root wt run branch pid dirty archive product_diff source_sha smoke_head occrc=0
  [ -n "$slug" ] || die "usage: closeout <slug> --into <branch> [--force-dirty]"
  shift; while [ "$#" -gt 0 ]; do case "$1" in --into) into="${2:-}"; shift 2;; --force-dirty) force=1; shift;; *) die "unknown closeout arg $1";; esac; done
  [ -n "$into" ] || die "--into required"
  root="$(repo_root)"; wt="$(worktree_path "$root" "$slug")"; run="$(run_dir "$root" "$slug")"
  [ -d "$run" ] || die "unreadable/missing run registry"
  pid="$(cat "$run/pid" 2>/dev/null || true)"; pid_alive "$pid" && die "recorded owner is alive: $pid"
  # The registry only knows the owner it recorded. A strand driven interactively,
  # or by another harness, is invisible to it — and the merge-ownership rule
  # (core build-loop step 9) licenses a takeover only on a builder proven dead.
  # For a destructive command, an unanswerable question is a refusal.
  if command -v cbr_path_has_live_process >/dev/null; then
    if cbr_path_has_live_process "$wt"; then occrc=0; else occrc=$?; fi
    case "$occrc" in
      0) die "a live process is rooted in $wt — somebody is working in this strand; the builder owns its own merge and closeout" ;;
      1) fact "occupancy" "no live process rooted in $wt (process-table-proven)" ;;
      *) [ "${CBR_ALLOW_UNPROVEN_OCCUPANCY:-}" = "1" ] \
           || die "the process table could not be inspected, so an occupant cannot be ruled out — refusing to reap $wt. Install lsof, or re-run with CBR_ALLOW_UNPROVEN_OCCUPANCY=1 if you have checked by hand."
         fact "occupancy" "UNPROVEN — an operator asserted the worktree is empty (CBR_ALLOW_UNPROVEN_OCCUPANCY=1)" ;;
    esac
  else
    die "the shared occupancy check is unavailable — refusing to reap $wt without proof that nobody is working in it"
  fi
  [ -d "$wt" ] || die "worktree missing"
  branch="$(git -C "$wt" branch --show-current)"; [ "$branch" != "$into" ] || die "source and destination are identical"
  [ "$(git -C "$root" branch --show-current)" = "$into" ] || die "closeout must run from destination branch $into"
  [ -f "$run/merge-facts.json" ] && [ -f "$run/live-smoke.json" ] || die "merge-facts/live-smoke evidence missing"
  source_sha="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_sha"])' "$run/merge-facts.json")"
  smoke_head="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["merged_head"])' "$run/live-smoke.json")"
  [ "$source_sha" = "$(git -C "$wt" rev-parse HEAD)" ] || die "stream advanced after merge-facts verification"
  git -C "$root" merge-base --is-ancestor "$source_sha" HEAD || die "source SHA is not merged"
  git -C "$root" merge-base --is-ancestor "$smoke_head" HEAD || die "live-smoked merged tree is not on current destination history"
  dirty="$(git -C "$wt" status --porcelain)"
  [ -z "$dirty" ] || [ "$force" -eq 1 ] || die "dirty files require inspection and --force-dirty"
  product_diff=""
  while IFS= read -r path; do [ -n "$path" ] || continue; product_diff="$product_diff$(git -C "$root" diff --name-only "$into...$branch" -- "$path")"; done < <(cfg_lines "$root" productPaths)
  [ -z "$product_diff" ] || die "product content still differs from $into; merge proof failed"
  # The three duties closeout owes the base branch (references/cbr-core/build-loop.md
  # step 9), performed by the shared provider-neutral mechanism: archive the strand's
  # records out of its FINAL COMMIT, drop its completion marker from the base, and
  # reground the base's root plan. This leaf supplies only the filenames.
  #
  # Reading the worktree, as this did, loses whatever the merge or a later commit
  # changed — and after a merge the base already holds the same bytes, which is how
  # the archive silently became a manual step.
  command -v cbr_closeout_base_duties >/dev/null ||
    die "shared closeout library missing ($CBR_STRAND_LIB); refusing to retire a strand whose records cannot be archived"
  # An archive directory that already exists is a PRIOR ATTEMPT at this same
  # slug, not a collision: closeout stops with the base untouched when the
  # archive fails, so the retry it invites must not be refused by the debris the
  # failure left behind. The records are re-extracted from the strand's commit
  # either way, so a stale partial archive is overwritten, not trusted.
  # Ownership of an existing archive is decided by the shared duties, not here:
  # one rule, one place, both leaves.
  archive="$root/docs/streams/archive/$slug"
  local duties
  duties="$(cbr_closeout_base_duties "$root" "$branch" "$into" "$archive" \
              DONE.marker task_plan.md \
              task_plan.md findings.md progress.md STATUS.md ASK-ORCH.md ORCH-ANSWER.md \
              DONE.marker NEEDS-HUMAN.md HARNESS-BROKEN.marker)" ||
    die "a base-branch closeout duty failed ($duties); worktree and branch are untouched"
  # The provenance stamp is not a record: an archive holding only the stamp is
  # still an archive of nothing, and this assertion exists to catch exactly that.
  [ -n "$(find "$archive" -type f ! -name "${CBR_ARCHIVE_STAMP:-.cbr-archive-of}" -print -quit)" ] \
    || die "archive is empty"
  fact "archive" "$archive"
  fact "base duties" "$duties"
  if [ "$force" -eq 1 ]; then
    git -C "$root" worktree remove --force "$wt"
  else
    git -C "$root" worktree remove "$wt"
  fi
  git -C "$root" branch -d "$branch"
  rm -rf "$run" "$root/.cbr-codex/watch/$slug.state" "$root/.cbr-codex/watch/$slug.needs-arm" "$root/.cbr-codex/watch/$slug.heartbeat"
  fact "retired" "worktree=$wt branch=$branch registry=$run"
}

cmd_janitor() {
  local root runs d slug wt branch pid state
  root="$(primary_root)"; runs="$root/.cbr-codex/runs"
  git -C "$root" worktree list --porcelain
  [ -d "$runs" ] || { fact "registry" "none"; return; }
  for d in "$runs"/*; do [ -d "$d" ] || continue; slug="$(basename "$d")"; wt="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("worktree",""))' "$d/meta.json" 2>/dev/null || true)"; pid="$(cat "$d/pid" 2>/dev/null || true)"; branch="$(git -C "$wt" branch --show-current 2>/dev/null || true)"; state=stale; pid_alive "$pid" && state=active; [ -d "$wt" ] || state=orphan-registry; fact "janitor $slug" "state=$state pid=${pid:-absent} worktree=${wt:-absent} branch=${branch:-absent}"; done
  fact "janitor law" "report-only; nothing removed"
}

usage() {
  cat <<'TXT'
Usage: cbr-codex.sh <command>
  arm <repo>                      create missing portable harness files
  record-hook-trust [repo]        record hashes after human Codex TUI hook review
  sync-models [repo]              project the single model dial into RoboRev
  doctor [repo]                   read-only preflight facts
  probe [repo]                    live Probity prove-NO/prove-YES
  provision <slug> <branch> [--base REF]
  launch <slug> --prompt-file FILE [--model ID] [--reasoning LEVEL]
  resume <slug> [--prompt-file FILE]
  status <slug>                   per-strand process/thread/git/review facts
  watch <slug> [--watchdog]       fire-once watcher or its dead-man
  fleet                           status all registered strands
  graph-check [fleet-json]        deterministic DAG/ownership validation
  dispatchable <slug> [fleet-json]
  merge-facts <slug> --into BRANCH
  live-smoke <slug> --into BRANCH  run configured real entry-path smoke
  closeout <slug> --into BRANCH [--force-dirty]
  janitor                         read-only worktree/registry reconciliation
TXT
}

case "${1:-help}" in
  arm) shift; cmd_arm "$@";;
  record-hook-trust) shift; cmd_record_hook_trust "$@";;
  sync-models) shift; cmd_sync_models "$@";;
  doctor) shift; cmd_doctor "$@";;
  probe) shift; cmd_probe "$@";;
  provision) shift; cmd_provision "$@";;
  launch) shift; cmd_launch "$@";;
  resume) shift; cmd_resume "$@";;
  status) shift; cmd_status "$@";;
  watch) shift; cmd_watch "$@";;
  fleet) shift; cmd_fleet "$@";;
  graph-check) shift; cmd_graph_check "$@";;
  dispatchable) shift; cmd_dispatchable "$@";;
  merge-facts) shift; cmd_merge_facts "$@";;
  live-smoke) shift; cmd_live_smoke "$@";;
  closeout) shift; cmd_closeout "$@";;
  janitor) shift; cmd_janitor "$@";;
  help|-h|--help) usage;;
  *) usage >&2; exit 2;;
esac
