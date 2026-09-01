#!/usr/bin/env bash
# smoke.sh — arming smoke test for the controlled-build-run control plane.
#
# Run this from the ROOT of the TARGET repo AFTER following SETUP.md. It checks
# the static facts a shell can verify: prerequisites on PATH, the gates wired,
# the hooks installed, the scripts present. It prints PASS/FAIL per check and
# exits non-zero if any hard check fails.
#
# It CANNOT prove the two things only a live Claude session can:
#   - Probity actually BLOCKS an untested production write (the prove-NO), and
#   - the path actually ALLOWS a real toolchain command + a throwaway edit (prove-YES).
# Those are the builder's first in-session act — see SKILL.md "One plan, one worktree".
#
# Usage:  bash controlled-build-run-kit/verify/smoke.sh
set -u
pass=0; fail=0; warn=0
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail=$((fail+1)); }
warn() { printf '  \033[33mWARN\033[0m  %s\n' "$1"; warn=$((warn+1)); }
have() { command -v "$1" >/dev/null 2>&1; }

root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not inside a git repo"; exit 1; }
cd "$root" || exit 1
echo "controlled-build-run smoke test — repo: $root"

echo "[1] prerequisites on PATH"
for c in claude roborev git jq node npx python3; do
  if have "$c"; then ok "$c present"; else bad "$c MISSING"; fi
done
for c in uv gitleaks; do
  if have "$c"; then ok "$c present (optional)"; else warn "$c missing (optional — needed only if your gates use it)"; fi
done
if have claude; then
  ver="$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  echo "       claude version: ${ver:-unknown} (need a build with --bg + 'claude agents' for fleet dispatch)"
fi

echo "[2] Probity armed (PreToolUse hook)"
settings=".claude/settings.json"
if [ -f "$settings" ] && jq -e '.. | objects | select(.command? // "" | test("probity"))' "$settings" >/dev/null 2>&1; then
  ok "probity PreToolUse command found in $settings"
else
  bad "no probity command in $settings — merge control-plane/settings.hooks.json"
fi
if [ -f probity.config.ts ]; then ok "probity.config.ts present at repo root"; else bad "probity.config.ts missing at repo root"; fi

echo "[3] RoboRev armed"
if [ -f .roborev.toml ]; then ok ".roborev.toml present"; else bad ".roborev.toml missing (run: roborev init --agent claude-code)"; fi
pc="$(git rev-parse --git-path hooks/post-commit 2>/dev/null)"
pr="$(git rev-parse --git-path hooks/post-rewrite 2>/dev/null)"
[ -e "$pc" ] && ok "git post-commit hook installed" || bad "git post-commit hook missing (roborev init)"
[ -e "$pr" ] && ok "git post-rewrite hook installed" || warn "git post-rewrite hook missing (roborev init usually installs it)"
[ -f .claude/hooks/roborev-gate.sh ] && ok ".claude/hooks/roborev-gate.sh present" || bad "roborev-gate.sh missing"
[ -f .claude/hooks/roborev-session-sweep.sh ] && ok "roborev-session-sweep.sh present" || bad "roborev-session-sweep.sh missing"
if have roborev; then
  if roborev list --json >/dev/null 2>&1; then ok "roborev daemon reachable"; else warn "roborev daemon not reachable (run: roborev daemon start)"; fi
fi

echo "[4] pre-commit gate armed"
pcg="$(git rev-parse --git-path hooks/pre-commit 2>/dev/null)"
[ -f "$pcg" ] && ok "git pre-commit hook installed" || bad "git pre-commit hook NOT installed (run: pre-commit install  — or  uv run pre-commit install)"
if [ -f .pre-commit-config.yaml ] && grep -q 'merge-review-gate' .pre-commit-config.yaml; then
  ok "merge-review-gate entry present in .pre-commit-config.yaml (per-commit reviews advisory)"
else
  bad "merge-review-gate entry missing from .pre-commit-config.yaml (the merge-boundary review wall)"
fi
if [ -x scripts/merge-review-gate.sh ]; then ok "scripts/merge-review-gate.sh present + executable"; else bad "scripts/merge-review-gate.sh missing or not executable (chmod +x)"; fi

echo "[5] post-compaction reground hook"
rg=".claude/hooks/post-compact-reground.sh"
if [ -f "$rg" ]; then
  ok "$rg present"
  if jq -e '.. | objects | select(.matcher? == "compact")' "$settings" >/dev/null 2>&1; then
    ok "SessionStart/compact entry wired in settings.json"
  else
    bad "reground hook not wired as SessionStart matcher=compact in settings.json"
  fi
  sections="$(bash "$rg" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | grep -cE '^=== ' || true)"
  if [ "${sections:-0}" -ge 1 ]; then ok "reground hook emits $sections doc section(s)"; else warn "reground hook emitted 0 sections (no binding docs found yet? expected before any docs/plan exist)"; fi
else
  bad "$rg missing"
fi

echo "[6] session sweep liveness"
sw=".claude/hooks/roborev-session-sweep.sh"
if [ -f "$sw" ]; then
  msg="$(bash "$sw" 2>/dev/null | jq -r '.systemMessage' 2>/dev/null || true)"
  case "$msg" in
    *"RoboRev gate armed"*) ok "session sweep emits: $msg" ;;
    *) warn "session sweep did not emit the armed line (daemon down? roborev/jq missing?)" ;;
  esac
else
  bad "$sw missing"
fi

echo "[7] the skill is in place"
if find . -path '*/claude-controlled-build-run/SKILL.md' 2>/dev/null | grep -q .; then
  ok "claude-controlled-build-run/SKILL.md found in repo"
else
  bad "claude-controlled-build-run SKILL.md not found — copy skill/claude-controlled-build-run/ into your skills dir"
fi
if [ -x "$(find . -path '*/claude-controlled-build-run/scripts/cbr.sh' 2>/dev/null | head -1)" ]; then
  ok "cbr.sh present + executable (fleet dispatch available)"
else
  warn "cbr.sh missing/not executable (only needed for parallel --bg builder dispatch)"
fi

echo
echo "summary: $pass passed, $fail failed, $warn warnings"
echo "NEXT (only a live Claude session can prove these):"
echo "  - prove-NO: attempt an untested production write in your gated tree -> must be BLOCKED by Probity"
echo "  - prove-YES: run one real toolchain command + one throwaway Write you delete -> both must SUCCEED"
[ "$fail" -eq 0 ] || exit 1
