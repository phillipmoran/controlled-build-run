#!/usr/bin/env bash
# Regression for the control-plane guard (PreToolUse: Write|Edit|MultiEdit|
# NotebookEdit|Bash). Every gate is a file in the worktree and a builder runs
# with permissions skipped, so without this hook the battery is one shell
# call from `exit 0`. Proves: protected paths deny (Write/Edit and the shell
# idioms that write them), the git bypass idioms deny, ordinary work and
# reads pass, the two deliberate exemptions pass (the re-ground hook's
# PORTING block, the gate configs), quoted prose that names a bypass passes,
# an unreadable payload fails CLOSED, the operator unlock passes, and the
# leaf wires it (settings template, arm's put list, doctor's hook loop and
# wiring contract). Hermetic: runs the hook on JSON payloads only.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
kit="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
leaf="$root/skills/claude-controlled-build-run"
[ -f "$leaf/templates/hooks/control-plane-guard.sh" ] || leaf="$kit/skill/claude-controlled-build-run"
hook="$leaf/templates/hooks/control-plane-guard.sh"
[ -f "$hook" ] || { echo "control-plane-guard.test FAIL: hook not found at $hook" >&2; exit 1; }

fails=0
bad() { echo "control-plane-guard.test FAIL: $1" >&2; fails=$((fails+1)); }

expect() { # expect <rc> <label> <json>
  local want="$1" label="$2" json="$3" rc
  printf '%s' "$json" | env -u CBR_CONTROL_PLANE_UNLOCK bash "$hook" >/dev/null 2>&1; rc=$?
  [ "$rc" = "$want" ] || bad "$label: rc=$rc, want $want"
}
w() { printf '{"tool_name":"%s","tool_input":{"file_path":"%s"}}' "$1" "$2"; }
b() { python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1"; }

# --- prove-NO: the enforcement layer is not the agent's to edit ---
expect 2 "Write to a session hook"            "$(w Write .claude/hooks/builder-stop-check.sh)"
expect 2 "Edit to settings.json (absolute)"   "$(w Edit /some/repo/.claude/settings.json)"
expect 2 "MultiEdit to a git hook"            "$(w MultiEdit .git/hooks/pre-push)"
expect 2 "Write to git config"                "$(w Write .git/config)"
expect 2 "Edit to the merge wall"             "$(w Edit scripts/merge-review-gate.sh)"
expect 2 "Edit to the record gate"            "$(w Edit scripts/record-single-source.sh)"
expect 2 "shell: redirect into a hook"        "$(b "echo 'exit 0' > .claude/hooks/builder-stop-check.sh")"
expect 2 "shell: tee into a hook"             "$(b "printf 'exit 0' | tee .claude/hooks/no-interactive-ask.sh")"
expect 2 "shell: in-place sed on the wall"    "$(b "sed -i '' 's/exit 1/exit 0/' scripts/merge-review-gate.sh")"
expect 2 "shell: chmod on a git hook"         "$(b "chmod -x .git/hooks/pre-push")"
expect 2 "shell: cp over settings"            "$(b "cp /tmp/loose.json .claude/settings.json")"
expect 2 "shell: rm a hook"                   "$(b "rm .claude/hooks/control-plane-guard.sh")"
expect 2 "git: --no-verify"                   "$(b "git commit --no-verify -m x")"
expect 2 "git: commit -n"                     "$(b "git commit -n -m x")"
expect 2 "git: commit -an"                    "$(b "git commit -an -m x")"
expect 2 "git: -c core.hooksPath"             "$(b "git -c core.hooksPath=/dev/null merge stream/x")"
expect 2 "git: config hooksPath"              "$(b "git config core.hooksPath /tmp/none")"
expect 2 "git: config merge.ff"               "$(b "git config merge.ff true")"
expect 2 "git: merge --no-verify"             "$(b "git merge --no-verify stream/x")"
expect 2 "git: push --no-verify"              "$(b "git push --no-verify origin main")"
expect 2 "git: quoted --no-verify"            "$(b "git commit '--no-verify' -m x")"
expect 2 "git: quoted merge.ff key"           "$(b "git config 'merge.ff' true")"
expect 2 "git: quoted -c hooksPath"           "$(b "git -c 'core.hooksPath=/dev/null' commit -m x")"
expect 2 "git: --no-verify after the message" "$(b "git commit -m x \"--no-verify\"")"
expect 2 "git: -n after -am message"          "$(b "git commit -am x -n")"
expect 2 "git: unbalanced quote fails closed" "$(b "git commit -m \"oops --no-verify")"
expect 2 "git: absolute path binary"          "$(b "/usr/bin/git commit --no-verify -m x")"
expect 2 "git: -C path commit -n"             "$(b "git -C repo commit -n -m x")"
expect 2 "git: --git-dir value commit -n"     "$(b "git --git-dir .git commit -n -m x")"
expect 2 "git: -c harmless then commit -n"    "$(b "git -c user.name=x commit -n -m x")"
expect 2 "git: -c hooksPath via global value" "$(b "git -c core.hooksPath=/dev/null status")"
expect 2 "unlock token set in-command"        "$(b "CBR_CONTROL_PLANE_UNLOCK=1 cp x .claude/hooks/y.sh")"
expect 2 "unlock token exported in-command"   "$(b "export CBR_CONTROL_PLANE_UNLOCK=1; git commit -m x")"
expect 2 "unreadable payload fails closed"    "not json at all"

# --- prove-YES: ordinary work, reads, and the deliberate exemptions pass ---
expect 0 "Write to production code"           "$(w Write src/app.ts)"
expect 0 "Write under .github (not .git/)"    "$(w Write .github/workflows/ci.yml)"
expect 0 "Write a .gitignore"                 "$(w Write docs/.gitignore)"
expect 0 "Edit the re-ground PORTING block"   "$(w Edit .claude/hooks/post-compact-reground.sh)"
expect 0 "Edit probity.config.ts (config)"    "$(w Edit probity.config.ts)"
expect 0 "Edit .pre-commit-config.yaml"       "$(w Edit .pre-commit-config.yaml)"
expect 0 "Edit .roborev.toml"                 "$(w Edit .roborev.toml)"
expect 0 "Edit a hook template in the skill"  "$(w Edit skills/claude-controlled-build-run/templates/hooks/roborev-gate.sh)"
expect 0 "shell: read settings"               "$(b "cat .claude/settings.json")"
expect 0 "shell: copy settings OUT"           "$(b "cat .claude/settings.json > /tmp/settings.bak")"
expect 0 "shell: run a hook by hand"          "$(b "bash .claude/hooks/roborev-session-sweep.sh 2>/dev/null")"
expect 0 "shell: sed the re-ground hook"      "$(b "sed -i '' 's/HOUSE_DOCS=.*/HOUSE_DOCS=(README.md)/' .claude/hooks/post-compact-reground.sh")"
expect 0 "shell: arm itself"                  "$(b "bash skills/claude-controlled-build-run/scripts/cbr.sh arm . --no-probe")"
expect 0 "git: ordinary commit"               "$(b "git add -A && git commit -m 'feat: thing'")"
expect 0 "git: prose naming a bypass (quoted)" "$(b "git commit -m 'docs: explain why --no-verify is denied'")"
expect 0 "git: log -n"                        "$(b "git log -n 5 --oneline")"
expect 0 "git: add -n (dry run)"              "$(b "git add -n .")"
expect 0 "git: -C path log -n"                "$(b "git -C repo log -n 3")"
expect 0 "git: -C path add -n"                "$(b "git -C repo add -n .")"
expect 0 "git: prose via -am cluster"         "$(b "git commit -am 'note on merge.ff and --no-verify'")"
expect 0 "git: prose via --message="          "$(b "git commit --message='why core.hooksPath is denied'")"
expect 0 "git: prose in a heredoc message"    "$(b "$(printf 'git commit -F - <<'"'"'EOF'"'"'\nfix: guard\n\nExplain --no-verify and merge.ff.\nEOF')")"
expect 0 "git: read merge config"             "$(b "git config --get merge.conflictStyle")"
expect 0 "grep for the unlock token"          "$(b "grep -rn CBR_CONTROL_PLANE_UNLOCK docs/")"
expect 0 "unrelated tool"                     '{"tool_name":"Read","tool_input":{"file_path":".claude/settings.json"}}'

# --- the operator unlock ---
rc=0; printf '%s' "$(w Write .claude/hooks/x.sh)" | CBR_CONTROL_PLANE_UNLOCK=1 bash "$hook" >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || bad "operator unlock did not pass a protected Write (rc=$rc)"

# --- the denial names the reason and the unlock ---
msg="$(printf '%s' "$(w Write .claude/hooks/x.sh)" | env -u CBR_CONTROL_PLANE_UNLOCK bash "$hook" 2>&1 >/dev/null || true)"
grep -q "BLOCKED by the CBR control-plane guard" <<<"$msg" || bad "denial does not identify itself: $msg"
grep -q "CBR_CONTROL_PLANE_UNLOCK=1" <<<"$msg" || bad "denial does not tell the operator how to unlock: $msg"

# --- a payload past the per-argument limit still denies (fail closed, not fail open) ---
big="$(python3 -c 'print("x"*1500000)')"
rc=0; printf '{"tool_name":"Write","tool_input":{"file_path":".claude/hooks/x.sh","content":"%s"}}' "$big" \
  | env -u CBR_CONTROL_PLANE_UNLOCK bash "$hook" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || bad "a 1.5MB payload targeting a hook was not denied (rc=$rc) — the guard fails open on large writes"

# --- the leaf wires it: settings template, arm, doctor, wiring contract ---
settings="$leaf/templates/claude-settings.json"
python3 - "$settings" <<'PY' || bad "the settings template does not wire control-plane-guard.sh under PreToolUse with a matcher covering Write, Edit and Bash"
import json, re, sys
cfg = json.load(open(sys.argv[1]))
ok = False
for block in cfg.get("hooks", {}).get("PreToolUse", []):
    m = block.get("matcher", "")
    if not all(re.search(m, t) for t in ("Write", "Edit", "Bash")):
        continue
    if any("control-plane-guard.sh" in h.get("command", "") for h in block.get("hooks", [])):
        ok = True
sys.exit(0 if ok else 1)
PY
cbr="$leaf/scripts/cbr.sh"
grep -qE '^ *put hooks/control-plane-guard\.sh ' "$cbr" || bad "cbr.sh arm does not install control-plane-guard.sh"
grep -q 'control-plane-guard.sh' <<<"$(sed -n '/^  for h in roborev-gate.sh/,/^  done/p' "$cbr")" \
  || bad "cbr.sh doctor's executable-hook loop does not list control-plane-guard.sh"
grep -q '"\.claude/hooks/control-plane-guard\.sh"' "$cbr" \
  || bad "missing_hook_wiring's need list does not require the guard block"

[ "$fails" -eq 0 ] || exit 1
echo "control-plane-guard.test OK: protected paths and git bypasses deny (shell and tool), ordinary work and the two exemptions pass, unreadable and oversized payloads fail closed, operator unlock passes, leaf wiring present"
