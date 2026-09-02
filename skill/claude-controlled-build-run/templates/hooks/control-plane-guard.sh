#!/usr/bin/env bash
# PreToolUse guard (matcher: Write|Edit|MultiEdit|NotebookEdit|Bash). The
# control plane is files in the worktree, and a builder runs with permissions
# skipped, so without this every gate is one Bash call from `exit 0`. This
# hook denies edits to the enforcement layer itself — the session hooks and
# their wiring, the git hooks and config, and the gate scripts — and the git
# idioms that bypass a gate outright (--no-verify, core.hooksPath, merge.ff).
# It is a bar, not a vault: the Bash check reads command text, so a
# determined agent can route around it; what it closes is the cheap, casual
# disarm, and it turns the expensive one into a visible act.
#
# Deliberately NOT guarded: the gate configs (probity.config.ts,
# .pre-commit-config.yaml, .roborev.toml, record-ownership.json) — setup fills
# them in after arm, and they are tracked files whose every change lands in
# the diff the reviewer and the operator read; and post-compact-reground.sh —
# a surfacing hook with a declared PORTING block setup must edit, whose loss
# costs a re-ground, not a guarantee (policy.md: fail-open is for surfacing).
#
# Operators unlock a maintenance session by exporting
# CBR_CONTROL_PLANE_UNLOCK=1 in the environment that launches the harness.
# The token itself is denied inside Bash commands so an agent cannot set it
# for its own subshell.
#
# Enforcement fails CLOSED (policy.md): an unreadable payload or a missing
# python3 denies, never waves through — a silently disarmed guard is the
# blind spot this hook exists to close.
set -uo pipefail

[ "${CBR_CONTROL_PLANE_UNLOCK:-0}" = "1" ] && exit 0

payload="$(cat 2>/dev/null || true)"

command -v python3 >/dev/null 2>&1 || {
  echo "BLOCKED by the CBR control-plane guard: python3 is missing, so the guard cannot read the tool call — enforcement fails closed. Install python3 or have the operator start the session with CBR_CONTROL_PLANE_UNLOCK=1." >&2
  exit 2
}

# The payload rides in a temp file, never an argument or env var: a Write's
# content can exceed the per-argument limit, and a guard that dies there
# would wave the call through.
tmp="$(mktemp 2>/dev/null)" || {
  echo "BLOCKED by the CBR control-plane guard: cannot create a temp file to read the tool call — enforcement fails closed." >&2
  exit 2
}
trap 'rm -f "$tmp"' EXIT
printf '%s' "$payload" > "$tmp"

# NOTE: macOS ships bash 3.2, whose parser tracks quotes inside a heredoc within
# $(...): keep the apostrophe count in the block below EVEN, or the hook dies
# with "unexpected EOF" and every tool call is denied (fail closed, but noisy).
reason="$(python3 - "$tmp" <<'PY'
import json, re, shlex, sys

try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        call = json.load(fh)
except Exception:
    print("the hook payload was not readable JSON (fail closed)")
    sys.exit(0)

tool = str(call.get("tool_name", ""))
inp = call.get("tool_input") or {}

# One path grammar for both checks. Matched against "/"-prefixed, "/"-normalized
# paths so `.git/` cannot match `.github/` and a bare basename still matches.
PROTECTED = re.compile(
    r"/(\.claude/hooks/(?!post-compact-reground\.sh$)|\.claude/settings\.json$|\.git/|"
    r"scripts/merge-review-gate\.sh$|scripts/record-single-source\.sh$)"
)

def protected_path(p):
    p = "/" + str(p).replace("\\", "/").lstrip("/")
    return PROTECTED.search(p) is not None

if tool in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
    path = inp.get("file_path") or inp.get("notebook_path") or ""
    if protected_path(path):
        print(f"{tool} targets a control-plane file: {path}")
    sys.exit(0)

BYPASS_ARG = re.compile(r"^--no-verify(=|$)|hooksPath|merge\.ff")
HEREDOC = re.compile(r"<<-?\s*(['\"]?)(\w+)\1[^\n]*\n.*?^\2[ \t]*$", re.S | re.M)
SHORT_CLUSTER = re.compile(r"^-[a-zA-Z]+$")
GIT_GLOBAL_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace",
                         "--config-env", "--super-prefix", "--exec-path", "--attr-source"}

def git_bypass(cmd):
    """The bypass idioms, judged on the ARGUMENTS git would receive: shell
    quoting is honoured (a quoted merge.ff is still the key git sees) and
    only commit-message values are exempt (prose that names a bypass is not
    one). Heredoc bodies are message/file content, not arguments."""
    body = HEREDOC.sub("", cmd)
    try:
        lex = shlex.shlex(body, posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        toks = list(lex)
    except ValueError:
        # unbalanced quoting: nothing can be exempted safely, so fail closed
        return re.search(r"\bgit\b", body) and re.search(r"--no-verify|hooksPath|merge\.ff", body)
    segs, cur = [], []
    for t in toks:
        if t and all(c in "|&;" for c in t):
            segs.append(cur); cur = []
        else:
            cur.append(t)
    segs.append(cur)
    for seg in segs:
        gi = next((i for i, t in enumerate(seg) if t == "git" or t.endswith("/git")), None)
        if gi is None:
            continue
        args, sub, i = seg[gi + 1:], None, 0
        while i < len(args):
            a = args[i]
            if sub is None and a in GIT_GLOBAL_WITH_VALUE:
                # the git globals that take a value sit BEFORE the subcommand:
                # `git -C repo commit -n` must still read as commit -n, and
                # the value itself (-c core.hooksPath=…) is still judged
                if i + 1 < len(args) and BYPASS_ARG.search(args[i + 1]):
                    return True
                i += 2; continue
            if a in ("-m", "--message", "-F", "--file"):
                i += 2; continue
            if a.startswith("--message=") or a.startswith("--file="):
                i += 1; continue
            if SHORT_CLUSTER.match(a):
                if sub == "commit" and "n" in a[1:]:
                    return True                      # -n is --no-verify
                if a.startswith("-m") and len(a) > 2 and not a.endswith("m"):
                    i += 1; continue                  # -m<msg>
                if a.endswith("m") or a.endswith("F"):
                    i += 2; continue                  # -am <msg>, -sF <file>
                i += 1; continue
            if BYPASS_ARG.search(a):
                return True
            if sub is None and not a.startswith("-"):
                sub = a
            i += 1
    return False

if tool == "Bash":
    cmd = str(inp.get("command", ""))
    if git_bypass(cmd):
        print("the git command carries a gate bypass (--no-verify / -n / core.hooksPath / merge.ff)")
        sys.exit(0)
    if re.search(r"\bCBR_CONTROL_PLANE_UNLOCK=", cmd):
        print("the command sets the operator unlock token — that token is for the operator to set, never the agent")
        sys.exit(0)
    TOKEN = (r"(\.claude/hooks/(?!post-compact-reground\.sh)|\.claude/settings\.json|"
             r"(?<![\w.])\.git/|merge-review-gate\.sh|record-single-source\.sh)")
    mutating_verb = re.search(
        r"(^|[;&|(\s])(cp|mv|rm|tee|chmod|chown|truncate|install|ln|rsync|patch|dd|shred)\s", cmd)
    in_place = re.search(r"\bsed\s+(-[a-zA-Z]*i|--in-place)|\bperl\s+-[a-zA-Z]*i", cmd)
    redirect_into = re.search(r">>?\s*['\"]?[^\s'\"|;&]*" + TOKEN, cmd)
    if redirect_into or ((mutating_verb or in_place) and re.search(TOKEN, cmd)):
        print("the shell command writes to, replaces, or re-permissions a control-plane file")
    sys.exit(0)

sys.exit(0)
PY
)"

[ -n "$reason" ] || exit 0

cat >&2 <<MSG
BLOCKED by the CBR control-plane guard: $reason
The session hooks and their wiring (.claude/hooks/, .claude/settings.json),
the git hooks and config (.git/), and the gate scripts
(scripts/merge-review-gate.sh, scripts/record-single-source.sh) are
operator-owned. An agent may not edit, replace, re-permission, or bypass them.
If the change is legitimate, stop and ask the operator: an operator who wants
these files edited starts the session with CBR_CONTROL_PLANE_UNLOCK=1 in its
environment. Never set that token yourself — doing so is the bypass this guard
exists to make visible.
MSG
exit 2
