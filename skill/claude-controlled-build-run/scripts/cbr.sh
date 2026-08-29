#!/usr/bin/env bash
# cbr.sh — controlled-build-run companion: the deterministic launch rail for parallel builders.
#
# ONE entry point, a few subcommands. This is the HANDS for the SKILL.md sections it executes;
# the prose stays the policy and the why. If this script vanished, the skill must still be
# hand-executable from the prose — so keep it boring, and never let it become the only copy of
# the procedure.
#
# Each subcommand obeys one law (the closeout-facts.py rule): GATHER FACTS, RUN THE FIXED
# SEQUENCE, DECIDE NOTHING. Concretely that means:
#   - fail closed: exit non-zero the moment a hard fact is wrong, and say which one
#   - never auto-act beyond the subcommand's job (no merge, no relaunch, no kill)
#   - never print a health verdict ("HEALTHY"/"OK"/"READY") — print the facts and let the
#     orchestrator (a human, or the agent) make the call. Silence is an ALARM, not a pass.
#
# There is deliberately NO "do everything" subcommand. You run the one for the moment you're at:
#   provision (before dispatch) -> launch (dispatch the builder as `claude --bg`) -> status (watch from outside).
#
# Usage:
#   cbr.sh provision <slug> <branch> [--base <ref>]
#   cbr.sh launch    <slug> --prompt-file <file> [--model <id>] [--effort <low|medium|high|xhigh|max>]
#   cbr.sh status    <slug>
#   cbr.sh help
#
# The model/effort defaults below MUST match SKILL.md "The model dial". They live here only so an
# unattended launch has a value; always pass --model/--effort explicitly when you can, and the
# launch echoes what it used so the human sees it before the builder spends a token.

set -uo pipefail

# ---- constants (keep in sync with SKILL.md "model dial" + references/harness-spec.md §7) ----
DEFAULT_MODEL="claude-sonnet-5"
DEFAULT_EFFORT="medium"
WEB_PKG="."   # the npm package whose node_modules the gate needs (repo root for now)

# The gates are the real boundary (Probity guards Edit/Write; pre-commit guards the commit;
# RoboRev reviews it). The allowlist just keeps an UNATTENDED builder from stalling on a safe
# op no human is there to approve: mutations stay gated, read-only inspection + test-running
# run free. Too narrow and the detached session hangs on `git status`/`git ls-files`/a seeded
# probe (observed live, S4+S5, 2026-06-20); broader-but-read-only is the correct trade.
#
# "worktree.bgIsolation": "none" — a `claude --bg` session normally auto-forks a fresh worktree under
# .claude/worktrees/ before editing (the bgIsolation guard). We DON'T want that: provision already made
# this worktree with the right branch + deps + push firewall, so the builder must edit HERE. Setting it
# to "none" (worktree-scoped, gitignored) keeps the session in the provisioned worktree. Probity still
# bites — it is a PreToolUse hook, independent of bgIsolation (proven on a --bg session 2026-06-23).
ALLOWLIST_JSON='{
  "worktree": { "bgIsolation": "none" },
  "permissions": {
    "allow": [
      "Edit", "Write", "MultiEdit",
      "Bash(pnpm install:*)", "Bash(pnpm add:*)", "Bash(pnpm remove:*)",
      "Bash(pnpm exec:*)", "Bash(pnpm run:*)", "Bash(pnpm test:*)", "Bash(pnpm vitest:*)",
      "Bash(pnpm -r:*)", "Bash(pnpm --filter:*)", "Bash(pnpm ls:*)", "Bash(pnpm why:*)",
      "Bash(roborev:*)",
      "Bash(git add:*)", "Bash(git commit:*)",
      "Bash(git status:*)", "Bash(git diff:*)", "Bash(git log:*)", "Bash(git show:*)",
      "Bash(git rev-parse:*)", "Bash(git ls-files:*)", "Bash(git check-ignore:*)",
      "Bash(git branch:*)", "Bash(git rev-list:*)", "Bash(git worktree list:*)",
      "Bash(ls:*)", "Bash(cat:*)", "Bash(grep:*)", "Bash(rg:*)",
      "Bash(find:*)", "Bash(head:*)", "Bash(tail:*)", "Bash(wc:*)",
      "Bash(sleep:*)", "Bash(echo:*)"
    ]
  }
}'

# ---- small helpers ----
die()  { echo "cbr: $*" >&2; exit 1; }
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$*"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; }
note() { printf '  ----  %s\n' "$*"; }
# WARN is not FAIL: it names something a human should act on without claiming a
# check failed. Printing a warn-only fact in red FAIL made a clean doctor look broken.
warn() { printf '  \033[33mWARN\033[0m  %s\n' "$*"; }

# The shared, provider-neutral closeout mechanics. The core snapshot ships inside
# this leaf (references/core/, byte-gated by verify/core-mirrors.test.sh), so the path is
# fixed relative to this script and needs no repo lookup. Sourced, not shelled out
# to: these are functions the closeout composes.
CBR_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CBR_STRAND_LIB="$CBR_SELF_DIR/../references/core/scripts/strand-lib.sh"
if [ -f "$CBR_STRAND_LIB" ]; then
  # shellcheck source=/dev/null
  . "$CBR_STRAND_LIB"
fi

repo_root() { git rev-parse --show-toplevel 2>/dev/null || die "not inside a git repo"; }

# Occupancy as a tri-state, in one place, because every caller that asks it gets
# the same three answers and the same right to be wrong in only one direction.
# Echoes yes|no|unknown; never fails.
worktree_occupancy() {
  local path="$1" rc=2
  if command -v cbr_path_has_live_process >/dev/null; then
    if cbr_path_has_live_process "$path"; then rc=0; else rc=$?; fi
  fi
  case "$rc" in 0) echo yes ;; 1) echo no ;; *) echo unknown ;; esac
}


worktree_path() { echo "$(dirname "$(repo_root)")/cockpit-$1"; }   # sibling of the repo: ../cockpit-<slug>

# ---- lineage emitter (P3) — best-effort, zero-touch (SETUP.md "recorder side stays
# ZERO-TOUCH"): the ABSENCE of a resolvable recorder must never fail a launch, only skip
# the observability side-channel. ----

# Mirrors packages/recorder/src/discovery.ts:slugifyPath exactly (replace '/' and '.' with '-')
# so a lineage event's project_id matches the same project the daemon already derives.
slugify_project_id() { printf '%s' "$1" | tr '/.' '--'; }

# project_id keys off the repo's PRIMARY worktree (matches discoverProjects: project_id =
# slugifyPath(worktrees[0].path)), so it is the same regardless of which worktree launched.
primary_worktree_project_id() {
  local primary
  primary="$(git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | head -1)"
  [ -n "$primary" ] || return 1
  slugify_project_id "$primary"
}

# Sets the global array CBR_BIN_CMD to an invocation prefix for the recorder CLI and returns
# 0, or returns 1 if none is resolvable. Checked in order: an explicit CBR_BIN override, a
# globally-linked `cbr` on PATH, then the in-repo adapter build — the self-hosting case where
# the reference host's own cbr.sh dispatches the reference host builders. A target repo armed with this skill
# but without the recorder installed simply gets no lineage events, per zero-touch.
resolve_cbr_bin() {
  if [ -n "${CBR_BIN:-}" ]; then CBR_BIN_CMD=("$CBR_BIN"); return 0; fi
  if command -v cbr >/dev/null 2>&1; then CBR_BIN_CMD=(cbr); return 0; fi
  local candidate; candidate="$(repo_root)/adapters/claude-code/dist/bin.js"
  if [ -f "$candidate" ]; then CBR_BIN_CMD=(node "$candidate"); return 0; fi
  return 1
}

# Sidecar registry (P3): append-only JSONL under ${CBR_HOME}/lineage-registry.jsonl recording
# run_id, spawned_by, child_id, agent_role, project_id, launch_ts for every REAL (parent_id
# present) spawn, so P4's death-observer + recovery sweep can recover the SAME run_id after a
# crash/restart. Independent of whether the observability emit succeeds — best-effort, never
# fails the launch.
persist_lineage_registry() {
  local slug="$1" sid="$2" parent_id="$3" agent_role="$4" project_id="$5" now_ms="$6"
  local home="${CBR_HOME:-$HOME/.cbr}"
  mkdir -p "$home" 2>/dev/null || { note "lineage: could not create \$CBR_HOME — skipping registry persist"; return 0; }
  local line
  line="$(python3 - "$slug" "$sid" "$parent_id" "$agent_role" "$project_id" "$now_ms" <<'PY'
import json, sys
slug, child_id, spawned_by, agent_role, project_id, launch_ts = sys.argv[1:7]
row = {
    "run_id": f"spawn:{spawned_by}:{slug}",
    "spawned_by": spawned_by,
    "child_id": child_id,
    "agent_role": agent_role or None,
    "project_id": project_id,
    "launch_ts": int(launch_ts),
}
print(json.dumps(row))
PY
)" || { note "lineage: could not build registry row — skipping"; return 0; }
  printf '%s\n' "$line" >> "$home/lineage-registry.jsonl" 2>/dev/null \
    || note "lineage: could not append to registry — skipping"
}

# Emits ONE agent.spawned lineage event for a just-launched --bg session. Best-effort: any
# failure here (no recorder resolvable, `cbr emit` rejects the event) is a printed note, never
# a launch failure — the dispatch already succeeded and is registered with the supervisor.
# parent_id precedence (resolved by the caller): explicit --parent-id arg > CBR_PARENT_ID env >
# absent. When absent, this emits a legacy FLAT spawn with NO lineage fields (never a malformed
# partial one) — spawned_by/child_id/run_id are all-or-nothing together.
emit_lineage_spawn() {
  local slug="$1" sid="$2" parent_id="$3" agent_role="$4"
  local project_id
  project_id="$(primary_worktree_project_id)" \
    || { note "lineage: could not resolve project_id — skipping spawn emit"; return 0; }
  # Sole wall-clock read for this event: the observation boundary now that the spawn is
  # confirmed registered — stamped once into event_time/observed_time/seq, marked 'observed'.
  local now_ms; now_ms="$(python3 -c 'import time; print(int(time.time() * 1000))')"
  if [ -n "$parent_id" ]; then
    persist_lineage_registry "$slug" "$sid" "$parent_id" "$agent_role" "$project_id" "$now_ms"
  fi
  if ! resolve_cbr_bin; then
    note "lineage: no recorder CLI resolvable (set CBR_BIN or put 'cbr' on PATH) — skipping spawn emit"
    return 0
  fi
  local payload
  payload="$(python3 - "$slug" "$sid" "$parent_id" "$agent_role" "$project_id" "$now_ms" <<'PY'
import json, sys
slug, sid, parent_id, agent_role, project_id, now_ms = sys.argv[1:7]
now_ms = int(now_ms)
payload = {"role": "builder", "phase_index": 0}
if agent_role:
    payload["agent_role"] = agent_role
if parent_id:
    run_id = f"spawn:{parent_id}:{slug}"
    payload["spawned_by"] = parent_id
    payload["child_id"] = sid
    payload["run_id"] = run_id
    event_id = run_id
else:
    event_id = "spawn:legacy:" + sid
event = {
    "schema_version": "0.2.3",
    "seq": now_ms,
    "event_id": event_id,
    "event_type": "agent.spawned",
    "event_time": now_ms,
    "observed_time": now_ms,
    "time_quality": "observed",
    "source": "supervisor-observer",
    "project_id": project_id,
    # The spawned child session id — the envelope identity the projection keys a
    # no-parent (legacy) spawn on (identityKey = session_id). Without it a
    # parent-less launch has no identityKey and the projection drops the event,
    # so a real launch goes invisible (projection principle). Harmless on the
    # lineage path, which folds by payload.child_id.
    "session_id": sid,
    "machine_id": "local",
    "visibility": "sensitive",
    "payload": payload,
}
print(json.dumps(event))
PY
)"
  if printf '%s' "$payload" | "${CBR_BIN_CMD[@]}" emit >/dev/null 2>&1; then
    ok "lineage: agent.spawned emitted (project_id=$project_id)"
  else
    note "lineage: cbr emit rejected the spawn event — skipping (dispatch itself succeeded)"
  fi
}

# Emits ONE agent.exited lineage event when cmd_status observes a terminal supervisor state
# (done/failed) in real time. Best-effort and idempotent, mirroring emit_lineage_spawn:
#   - run_id is recovered from the sidecar registry (persist_lineage_registry) by matching
#     child_id against the (possibly 8-hex-truncated) sid cmd_status read from the supervisor.
#     A legacy/no-lineage session has no registry row — silent no-op (zero-touch mandate).
#   - dedup against the PROJECT'S OWN events file: cmd_status can be polled repeatedly, and
#     P4's recovery sweep may already have synthesized this same run_id's exit, so any existing
#     agent.exited row with a matching payload.run_id short-circuits a re-emit.
#   - event_id uses a DIFFERENT deterministic prefix ("status-exit:") than the recovery sweep's
#     ("sweep-exit:") so the two emission sources stay distinguishable while both dedup safely
#     off the shared payload.run_id.
emit_lineage_exit() {
  local slug="$1" sid="$2" reason="$3"
  local home="${CBR_HOME:-$HOME/.cbr}"
  local registry="$home/lineage-registry.jsonl"
  [ -f "$registry" ] || return 0
  local run_id
  run_id="$(python3 - "$registry" "$sid" <<'PY'
import json, sys
path, sid = sys.argv[1], sys.argv[2]
run_id = ""
try:
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except Exception:
                continue
            child_id = row.get("child_id", "")
            if child_id and child_id.startswith(sid):
                run_id = row.get("run_id", "")
except Exception:
    pass
print(run_id)
PY
)"
  [ -n "$run_id" ] || return 0

  local project_id
  project_id="$(primary_worktree_project_id)" 2>/dev/null || return 0
  [ -n "$project_id" ] || return 0

  local events_file="$home/events/$project_id.jsonl"
  if [ -f "$events_file" ]; then
    local already
    already="$(python3 - "$events_file" "$run_id" <<'PY'
import json, sys
path, run_id = sys.argv[1], sys.argv[2]
found = ""
try:
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except Exception:
                continue
            if row.get("event_type") == "agent.exited" and row.get("payload", {}).get("run_id") == run_id:
                found = "1"
                break
except Exception:
    pass
print(found)
PY
)"
    [ -z "$already" ] || return 0
  fi

  resolve_cbr_bin || return 0
  local now_ms; now_ms="$(python3 -c 'import time; print(int(time.time() * 1000))')"
  local payload
  payload="$(python3 - "$run_id" "$reason" "$project_id" "$now_ms" <<'PY'
import json, sys
run_id, reason, project_id, now_ms = sys.argv[1:5]
now_ms = int(now_ms)
event = {
    "schema_version": "0.2.3",
    "seq": now_ms,
    "event_id": f"status-exit:{run_id}",
    "event_type": "agent.exited",
    "event_time": now_ms,
    "observed_time": now_ms,
    "time_quality": "observed",
    "source": "supervisor-observer",
    "project_id": project_id,
    "machine_id": "local",
    "visibility": "sensitive",
    "payload": {"reason": reason, "run_id": run_id},
}
print(json.dumps(event))
PY
)"
  if printf '%s' "$payload" | "${CBR_BIN_CMD[@]}" emit >/dev/null 2>&1; then
    ok "lineage: agent.exited emitted (reason=$reason, project_id=$project_id)"
  else
    note "lineage: cbr emit rejected the exit event — skipping"
  fi
}

# this skill's own folder + templates — arm copies FROM here, so arm is self-contained
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
TPL="$SKILL_DIR/templates"

# the push firewall hook body — shared by provision (worktrees) and arm (fresh repos)
write_push_firewall() {  # $1 = pre-push hook file path
  cat > "$1" <<'HOOK'
#!/bin/sh
# cbr push firewall: builders never push; pushing main is the human's, always (on some repos a
# push to main auto-deploys prod). Holds under --dangerously-skip-permissions — a hook is not a
# permission. Two layers, both deny-by-default:
#   1) current-branch check — a stream/* worktree pushes nothing (the accident guard)
#   2) pushed-ref check — nothing pushes to main without CBR_ALLOW_PUSH=1, from any branch, any
#      worktree, detached HEAD included (layer 1 alone is bypassable via detached HEAD, a side
#      branch, or the primary checkout; proven live 2026-08-27, pinned by
#      kit/verify/push-firewall.test.sh)
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
HOOK
  chmod +x "$1"
}

# Ownership and currency are decided by EXACT BYTES only. A marker substring proves nothing in
# either direction: an old install would read as "already there" forever, and a custom hook that
# merely mentions CBR_ALLOW_PUSH alongside its own enforcement would get clobbered — deleting
# that enforcement silently. So: byte-identical to today's body -> current, untouched; exact
# sha256 of a body a CBR leaf actually shipped -> upgraded in place; no marker -> rc 1 (foreign);
# anything else mentioning the marker -> rc 2 (unrecognized/composed). Both refusals leave the
# hook byte-identical — the caller reports, a human merges.
_fw_sha256() { { shasum -a 256 "$1" 2>/dev/null || sha256sum "$1" 2>/dev/null; } | cut -d' ' -f1; }
ensure_push_firewall() {  # $1 = pre-push hook file path
  if [ ! -e "$1" ]; then
    write_push_firewall "$1"
    [ -x "$1" ] || return 3   # rc 3: success may never be reported for a hook git will skip
    return 0
  fi
  grep -q "CBR_ALLOW_PUSH" "$1" 2>/dev/null || return 1
  local want; want="$(mktemp)"
  write_push_firewall "$want"
  # a byte-perfect hook with the execute bit stripped is silently skipped by
  # git — the bytes are provably ours, so re-arming the bit is always safe
  if cmp -s "$want" "$1"; then
    rm -f "$want"
    chmod +x "$1" 2>/dev/null || true
    [ -x "$1" ] || return 3
    return 0
  fi
  rm -f "$want"
  case "$(_fw_sha256 "$1")" in
    # claude leaf pre-2026-08-27 (branch-layer only) | codex leaf pre-2026-08-27
    121723d3894c1885cef6fbac5d47b50c26a2feb1b40d8d3a5a8b3192985be584|\
    cd3f4198a9d05fb67960cbb26b797a5c35e74092c56947621800f714dbb52e63)
      write_push_firewall "$1"
      [ -x "$1" ] || return 3
      return 0 ;;
  esac
  return 2
}

# is the FULL hook wiring live in this settings.json? The armed harness needs all four blocks —
# Probity (PreToolUse), the RoboRev gate (PostToolUse), and the session sweep + compaction
# re-ground (SessionStart). Hook SCRIPTS on disk prove nothing if settings never invokes them,
# and a needle in an inert entry proves nothing either — so this parses the hook OBJECTS: the
# command must sit in a type:"command" entry under the right event, with the matcher the harness
# needs (Probity must match Write+Edit, the RoboRev gate must match Bash, the re-ground must
# match "compact"; the sweep block carries no matcher). Also verifies the model pin the dial says
# lives here. Prints missing piece names (one per line); exit 0 all wired / 1 missing / 2 unreadable.
missing_hook_wiring() {  # $1 = settings.json path
  python3 - "$1" <<'PY'
import sys, json, re, shlex, os
try:
    cfg = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(2)
hooks = cfg.get("hooks", {})

def cmd_is_live(cmd, kind, needle):
    # argv-level, not substring: the needle must be the thing EXECUTED, never text
    # inside an option payload (`bash -c 'echo …gate.sh'`) or a later argument
    try:
        toks = shlex.split(str(cmd))
    except ValueError:
        return False
    if not toks:
        return False
    prog = os.path.basename(toks[0])
    if kind == "script":
        if toks[0].endswith(needle):
            return True
        if prog not in ("bash", "sh", "zsh"):
            return False
        # the script operand is the FIRST non-option argument; -c makes the payload
        # a string (not a script path), so its presence disqualifies the block
        args = toks[1:]
        if "-c" in args:
            return False
        operand = next((t for t in args if not t.startswith("-")), None)
        return operand is not None and operand.endswith(needle)
    if kind == "npx-pkg":
        # the official semver.org grammar — no leading zeroes, no empty identifiers
        semver = (r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
                  r"(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)"
                  r"(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?"
                  r"(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?")
        def pinned_npx(tokens):
            # the package spec is the first non-option npx operand, pinned to a
            # concrete version (@latest / unversioned floats the guard)
            if not tokens or os.path.basename(tokens[0]) != "npx":
                return False
            operand = next((t for t in tokens[1:] if not t.startswith("-")), None)
            return operand is not None and re.fullmatch(re.escape(needle) + "@" + semver, operand) is not None
        # Form A (pre-2026-07-03): a bare version-pinned npx run
        if pinned_npx(toks):
            return True
        # Form B (ratified 2026-07-03, cost fix): sh -c 'local bin first, pinned-npx
        # fallback' — accept ONLY when the payload both executes the local
        # node_modules/.bin/probity AND falls back to a version-pinned npx run.
        if prog in ("sh", "bash", "zsh") and "-c" in toks:
            payload = toks[toks.index("-c") + 1] if len(toks) > toks.index("-c") + 1 else ""
            if "node_modules/.bin/probity" not in payload:
                return False
            m = re.search(r"npx\s+(?:--yes\s+)?(\S+)", payload)
            return m is not None and re.fullmatch(re.escape(needle) + "@" + semver, m.group(1)) is not None
        return False
    return False

def live(event, kind, needle, want_matcher):
    for block in hooks.get(event, []) or []:
        if not isinstance(block, dict):
            continue
        m = block.get("matcher")
        if want_matcher == "NONE":
            # must fire on EVERY source — a matcher (other than match-all) scopes it down
            if isinstance(m, str) and m.strip() not in ("", "*", ".*"):
                continue
        elif want_matcher is not None:
            # matcher is a regex over tool/source names; every needed token must match
            if not isinstance(m, str):
                continue
            try:
                if not all(re.search(m, tok) for tok in want_matcher):
                    continue
            except re.error:
                continue
        for h in block.get("hooks", []) or []:
            if isinstance(h, dict) and h.get("type") == "command" and cmd_is_live(h.get("command", ""), kind, needle):
                return True
    return False

need = [
    ("PreToolUse",  "npx-pkg", "@nizos/probity",                        ["Write", "Edit"], "Probity TDD gate (PreToolUse, matcher must cover Write+Edit)"),
    ("PostToolUse", "script",  ".claude/hooks/roborev-gate.sh",         ["Bash"],          "RoboRev commit gate (PostToolUse, matcher must cover Bash)"),
    ("SessionStart","script",  ".claude/hooks/roborev-session-sweep.sh","NONE",            "RoboRev session sweep (SessionStart, must run on EVERY start — no scoping matcher)"),
    ("SessionStart","script",  ".claude/hooks/post-compact-reground.sh",["compact"],       "compaction re-ground (SessionStart, matcher 'compact')"),
    ("PreToolUse",  "script",  ".claude/hooks/no-interactive-ask.sh",   ["AskUserQuestion"], "AskUserQuestion guard (PreToolUse, matcher 'AskUserQuestion' — a --bg builder must not freeze on an interactive prompt)"),
]
missing = [label for event, kind, needle, matcher, label in need if not live(event, kind, needle, matcher)]
if not isinstance(cfg.get("model"), str) or not cfg["model"].strip():
    missing.append('model pin ("model" key — the dial says the orchestrator model is pinned here)')
print("\n".join(missing))
sys.exit(1 if missing else 0)
PY
}

# ---------------------------------------------------------------------------
# provision <slug> <branch> [--base <ref>]
#   Set up a fresh builder worktree so the FIRST commit doesn't die: worktree+branch, the gitignored
#   deps the gate needs (node_modules symlink + uv sync), the §7 allowlist, and the deterministic
#   armed-checks. It does NOT launch claude, write the plan, or claim Probity is proven (it can't —
#   the live prove-NO/prove-YES is the builder's first in-session act).
# ---------------------------------------------------------------------------
cmd_provision() {
  local slug="${1:-}" branch="${2:-}" base=""
  shift 2 2>/dev/null || die "usage: cbr.sh provision <slug> <branch> [--base <ref>]"
  while [ $# -gt 0 ]; do
    case "$1" in
      --base) base="${2:-}"; shift 2 ;;
      *) die "provision: unknown arg '$1'" ;;
    esac
  done
  [ -n "$slug" ] && [ -n "$branch" ] || die "usage: cbr.sh provision <slug> <branch> [--base <ref>]"

  local root wt fails=0 reset_out hook_out
  root="$(repo_root)"
  wt="$(worktree_path "$slug")"

  echo "provision: slug=$slug branch=$branch base=${base:-<current HEAD>}"
  echo "           worktree=$wt"

  git -C "$root" show-ref --verify --quiet "refs/heads/$branch" \
    && die "branch '$branch' already exists — provision is for FRESH strands (relaunch reuses the existing one)"
  [ -e "$wt" ] && die "worktree path '$wt' already exists — remove it first or pick another slug"

  # 1. worktree + branch
  if git -C "$root" worktree add "$wt" -b "$branch" ${base:+"$base"} >/dev/null 2>&1; then
    ok "worktree + branch created"
  else
    bad "git worktree add failed"; return 1
  fi

  # 1b. progress.md — the fresh worktree inherits the FLEET's log from the branch; left
  # alone, the builder prepends its entries to it and closeout then archives fleet history
  # as if it were the stream's narrative (every such archive needed a hand-trim review
  # cycle). Reset at birth so the file is stream-only from line one.
  if printf '%s\n' \
      "# progress.md — $branch builder log (reset at provision, $(date +%F))" \
      "" \
      "Newest at top. STREAM-ONLY: this file was reset when the worktree was created —" \
      "fleet/orchestrator history lives in the orchestrator's worktree, never here." \
      "Closeout archives this file verbatim as the stream's permanent record." \
      > "$wt/progress.md"; then
    ok "progress.md reset to a stream-only log (archives are born clean)"
  else
    bad "progress.md reset failed"; fails=$((fails+1))
  fi

  # 1c. stale records — the worktree inherits the base's STATUS.md / DONE.marker /
  # ASK-ORCH etc.; a watcher that glances at a dead strand's "COMPLETE" believes a
  # build that never ran. Shared-core duty (strand-lib), same on both leaves.
  if command -v cbr_provision_reset_stale_records >/dev/null; then
    if reset_out="$(cbr_provision_reset_stale_records "$wt")"; then
      ok "stale records reset (${reset_out##*removed=} inherited record(s) removed)"
    else
      bad "stale record reset failed"; fails=$((fails+1))
    fi
  else
    bad "shared strand library missing (cbr_provision_reset_stale_records)"; fails=$((fails+1))
  fi

  # 1d. base pin — write the strand's base down at birth so launch can prove the
  # branch still grows from it (the wrong-base fork check). At creation the branch
  # tip IS the base, so pin the tip.
  if command -v cbr_record_strand_base >/dev/null \
     && cbr_record_strand_base "$root" "$branch" "$branch" >/dev/null; then
    ok "base pin recorded (branch.$branch.cbrBase)"
  else
    bad "base pin could not be recorded"; fails=$((fails+1))
  fi

  # 2. node_modules — gitignored, so a fresh worktree lacks it; the web hooks (always_run) 127 without it
  if [ -d "$root/$WEB_PKG/node_modules" ]; then
    ln -s "$root/$WEB_PKG/node_modules" "$wt/$WEB_PKG/node_modules" \
      && ok "node_modules symlinked from primary checkout" \
      || { bad "node_modules symlink failed"; fails=$((fails+1)); }
  else
    bad "primary checkout has no $WEB_PKG/node_modules to link (run npm ci there first)"; fails=$((fails+1))
  fi

  # 2b. pnpm-workspace per-package node_modules — the root link alone is not enough:
  # each workspace package resolves its own deps (e.g. zod) through its OWN
  # node_modules, so a fresh worktree 127s inside packages/* until these exist.
  # Entry-level links, NOT whole-dir links: external deps (.pnpm store) may point
  # at the primary checkout (immutable), but workspace packages (@cbr/*) must
  # repoint INTO the worktree or tsc/runtime silently build against the primary's
  # source. Same rule per-shim inside .bin — a wholesale .bin link leaks
  # workspace-package binaries back to the primary checkout.
  if pkg_links=$(python3 - "$root" "$wt" <<'PYEOF'
import os, shutil, sys
root, wt = os.path.realpath(sys.argv[1]), os.path.realpath(sys.argv[2])
count = 0
def link_entry(src_nm, dst_nm, name):
    global count
    s, d = os.path.join(src_nm, name), os.path.join(dst_nm, name)
    if os.path.lexists(d):
        return
    os.makedirs(os.path.dirname(d), exist_ok=True)
    # pnpm bin shims are plain scripts that resolve their target relative to
    # their own directory ($basedir/../<pkg>/...) — a copy resolves through
    # the worktree's repointed links, a symlink-to-primary would not.
    if os.path.dirname(name) == '.bin' and os.path.isfile(s) and not os.path.islink(s):
        shutil.copy2(s, d)
        count += 1
        return
    rp = os.path.realpath(s)
    inside = rp.startswith(root + os.sep)
    is_workspace = inside and 'node_modules' not in rp[len(root) + 1:].split(os.sep)
    target = os.path.join(wt, os.path.relpath(rp, root)) if is_workspace else rp
    os.symlink(target, d)
    count += 1
for group in ('packages', 'adapters'):
    gdir = os.path.join(root, group)
    if not os.path.isdir(gdir):
        continue
    for pkg in sorted(os.listdir(gdir)):
        src_nm = os.path.join(gdir, pkg, 'node_modules')
        if not os.path.isdir(src_nm):
            continue
        dst_nm = os.path.join(wt, group, pkg, 'node_modules')
        os.makedirs(dst_nm, exist_ok=True)
        for name in sorted(os.listdir(src_nm)):
            if name.startswith('@') or name == '.bin':
                for sub in sorted(os.listdir(os.path.join(src_nm, name))):
                    link_entry(src_nm, dst_nm, os.path.join(name, sub))
            else:
                link_entry(src_nm, dst_nm, name)
print(count)
PYEOF
  ); then
    ok "per-package node_modules provisioned ($pkg_links entry links; workspace pkgs repointed in-worktree)"
  else
    bad "per-package node_modules provisioning failed"; fails=$((fails+1))
  fi

  # 2c. project prep hook — stack-specific workspace prep beyond the steps above
  # lives in the PROJECT's own .cbr/provision-hook.sh (shared-core socket); absent
  # is the normal case, a failing or non-executable hook fails the provision.
  if command -v cbr_run_provision_hook >/dev/null; then
    if hook_out="$(cbr_run_provision_hook "$root" "$wt")"; then
      case "$hook_out" in
        *hook=ran*) ok "project provision hook ran (.cbr/provision-hook.sh)" ;;
      esac
    else
      bad "project provision hook failed (.cbr/provision-hook.sh)"; fails=$((fails+1))
    fi
  fi

  # 3. toolchain — the worktree must resolve tsc through the linked node_modules
  if ( cd "$wt" && pnpm exec tsc --version >/dev/null 2>&1 ); then
    ok "toolchain reachable in worktree (pnpm exec tsc via linked node_modules)"
  else
    bad "toolchain unreachable in worktree (node_modules link failed?)"; fails=$((fails+1))
  fi

  # 4. operability allowlist (§7) + bgIsolation:none — gitignored, worktree-scoped; does NOT weaken Probity
  mkdir -p "$wt/.claude"
  printf '%s\n' "$ALLOWLIST_JSON" > "$wt/.claude/settings.local.json"
  if git -C "$wt" check-ignore -q .claude/settings.local.json; then
    ok "allowlist + bgIsolation:none written and confirmed gitignored"
  else
    bad "allowlist is NOT gitignored — it would get committed"; fails=$((fails+1))
  fi

  # 5. armed-checks — gates only bite on a branch that CONTAINS them, and the hook must be installed
  grep -q "roborev-clean" "$wt/.pre-commit-config.yaml" 2>/dev/null \
    && ok "roborev-clean gate present in this branch's .pre-commit-config.yaml" \
    || { bad "roborev-clean gate missing from .pre-commit-config.yaml (branch forked before the gate?)"; fails=$((fails+1)); }
  local hook
  hook="$(git -C "$wt" rev-parse --git-path hooks/pre-commit 2>/dev/null)"   # ABSOLUTE path for a linked worktree
  if [ -n "$hook" ] && [ -x "$hook" ]; then
    ok "pre-commit hook is installed and executable"
  else
    bad "pre-commit hook not installed (run 'uv run pre-commit install')"; fails=$((fails+1))
  fi

  # 6. push firewall — pairs with --dangerously-skip-permissions. A builder must NEVER push (cardinal
  #    rule: only the human pushes; a push to main auto-deploys prod). A git PRE-PUSH HOOK enforces it
  #    even with prompts off (a hook is not a permission). Scoped to stream/* so the human's own pushes
  #    are untouched; lives in the shared common hooks dir, so one install covers every worktree.
  local pp; pp="$(git -C "$wt" rev-parse --git-path hooks/pre-push 2>/dev/null)"
  if [ -n "$pp" ]; then
    if ensure_push_firewall "$pp"; then
      ok "push firewall current (pre-push denies stream/* and any push to main unless CBR_ALLOW_PUSH=1)"
    else
      case "$?" in
        2) bad "pre-push hook at $pp mentions CBR_ALLOW_PUSH but is not a known CBR body (custom or hand-merged?) — left untouched; merge the two-layer firewall by hand before dispatch" ;;
        3) bad "push firewall at $pp could NOT be made executable — git will silently skip it; fix filesystem permissions and re-run" ;;
        *) bad "a foreign pre-push hook already exists ($pp) — the stream/* push firewall was NOT installed; add the deny by hand before dispatch (skip-permissions re-opens this push boundary)" ;;
      esac
      fails=$((fails+1))
    fi
  fi

  echo
  if [ "$fails" -eq 0 ]; then
    note "harness provisioned. NEXT: drop task_plan.md (with a '**Branch:** $branch' line) into $wt,"
    note "then: cbr.sh launch $slug --prompt-file <dispatch-prompt-file>"
    note "the LIVE Probity prove-NO/prove-YES probe is the builder's FIRST in-session act — this script"
    note "verifies the path is ready, it does NOT prove Probity bites (a shell can't)."
    return 0
  fi
  bad "$fails check(s) failed — fix them before dispatch; do NOT launch onto a half-provisioned worktree"
  return 1
}

# ---------------------------------------------------------------------------
# launch <slug> --prompt-file <file> [--model <id>] [--effort <e>]
#   Dispatch the on-plan builder as a `claude --bg` BACKGROUND SESSION (managed by the supervisor
#   daemon, so it survives the orchestrator), and confirm it registered. Takes the dispatch prompt as
#   a file — it never composes the prompt (that's judgment).
# ---------------------------------------------------------------------------
cmd_launch() {
  local slug="${1:-}" prompt_file="" model="$DEFAULT_MODEL" effort="$DEFAULT_EFFORT"
  # Lineage (P3): parent_id precedence is explicit --parent-id > CBR_PARENT_ID env > absent.
  local parent_id="${CBR_PARENT_ID:-}" agent_role=""
  shift 1 2>/dev/null || die "usage: cbr.sh launch <slug> --prompt-file <file> [--model <id>] [--effort <e>]"
  while [ $# -gt 0 ]; do
    case "$1" in
      --prompt-file) prompt_file="${2:-}"; shift 2 ;;
      --model)       model="${2:-}"; shift 2 ;;
      --effort)      effort="${2:-}"; shift 2 ;;
      --parent-id)   parent_id="${2:-}"; shift 2 ;;
      --agent-role)  agent_role="${2:-}"; shift 2 ;;
      *) die "launch: unknown arg '$1'" ;;
    esac
  done
  [ -n "$slug" ] || die "usage: cbr.sh launch <slug> --prompt-file <file> [--model <id>] [--effort <e>]"
  [ -n "$prompt_file" ] && [ -f "$prompt_file" ] || die "launch: --prompt-file must point at an existing file"

  local wt wt_real; wt="$(worktree_path "$slug")"
  [ -d "$wt" ] || die "launch: worktree '$wt' does not exist — run 'cbr.sh provision $slug <branch>' first"

  # BASE PIN — prove the branch still grows from the base provision recorded
  # (shared-core duty). rc=1 is the wrong-base fork, caught before dispatch
  # instead of mid-build; rc=2 (no pin — strand born before this law) warns.
  local pin_branch pin_rc=0
  pin_branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  if command -v cbr_assert_strand_base >/dev/null && [ -n "$pin_branch" ]; then
    cbr_assert_strand_base "$(repo_root)" "$pin_branch" >/dev/null 2>&1 || pin_rc=$?
    case "$pin_rc" in
      0) ;;
      2) note "no base pin recorded for $pin_branch (pre-pin strand) — proceeding without the base check" ;;
      *) die "launch: branch '$pin_branch' does not contain its recorded base — it grew from the wrong place; re-provision or fix the pin (branch.$pin_branch.cbrBase) before dispatch" ;;
    esac
  fi
  command -v claude >/dev/null || die "launch: claude not found on PATH"
  command -v python3 >/dev/null || die "launch: python3 not found on PATH"
  wt_real="$(cd "$wt" && pwd -P)"

  # PREFLIGHT — one-writer-per-worktree. Refuse to dispatch a SECOND background session into a worktree
  # that already has a live one rooted in it: two --bg builders on one worktree/branch race on the git
  # index, clobber each other's uncommitted edits, and double-run RoboRev. The supervisor registry
  # (claude agents --json) is the GROUND TRUTH for liveness — never infer it from a STATUS file or a
  # stale transcript (that exact mis-read caused a real double-launch on stream/anim-frontend
  # 2026-07-08). Fail-closed on an unknown-but-not-dead state; if the registry is unreadable, WARN and
  # proceed (the post-dispatch registration probe below still runs). "blocked" counts as LIVE — a frozen
  # session still owns the worktree.
  local occ rc jtmp2; jtmp2="$(mktemp)"
  if claude agents --json --all >"$jtmp2" 2>/dev/null && [ -s "$jtmp2" ]; then
    occ="$(python3 - "$jtmp2" "$wt_real" <<'PY'
import sys, json
path, wt = sys.argv[1], sys.argv[2]
DEAD = {"done", "stopped", "failed", "error", "killed", "exited", "cancelled", "canceled"}
try:
    rows = json.load(open(path))
except Exception:
    sys.exit(3)  # unreadable JSON -> distinct code so the caller WARNs, never silently proceeds
for r in rows:
    if r.get("kind") != "background":
        continue
    cwd = r.get("cwd") or ""
    # rooted-worktree ownership — MUST match cmd_status: a subdir cwd still owns the worktree.
    if not (cwd == wt or cwd.startswith(wt + "/")):
        continue
    st = (r.get("state") or "").strip().lower()
    if st in DEAD:
        continue
    print("%s|%s" % (r.get("sessionId", "?"), st or "unknown"))  # live (or unknown != dead) -> report
    break
PY
)"
    rc=$?
    if [ "$rc" -ne 0 ]; then
      occ=""
      note "launch: supervisor registry output was unreadable (JSON parse failed) — could not check $wt for an existing writer; proceeding (post-dispatch registration probe still applies)"
    fi
  else
    occ=""
    note "launch: could not read the supervisor registry to check $wt for an existing writer — proceeding (post-dispatch registration probe still applies)"
  fi
  rm -f "$jtmp2"
  if [ -n "$occ" ]; then
    local osid="${occ%%|*}" ost="${occ##*|}"
    die "launch: a live background session ($osid, state=$ost) is already rooted in $wt — refusing to dispatch a second writer (they would race on the git index + RoboRev). Stop it first:  claude stop $osid   (or use a different slug/worktree)."
  fi

  # The registry only knows the sessions IT launched. A worktree being driven
  # INTERACTIVELY, or by another harness, is invisible to it — and dispatching a
  # second writer there is one of the two harms the occupancy fact exists to
  # prevent. Same one-writer rule, wider evidence.
  local locc; locc="$(worktree_occupancy "$wt_real")"
  case "$locc" in
    yes) die "launch: a live process is already rooted in $wt (interactive session, or another harness) — refusing to dispatch a second writer into an occupied worktree" ;;
    no)  ;;
    *)   # A one-writer rule that evaporates when a tool is missing is not a
         # rule. Refuse, and make the override an explicit human act rather
         # than a silent consequence of the host's toolchain.
         [ "${CBR_ALLOW_UNPROVEN_OCCUPANCY:-}" = "1" ] \
           || die "launch: the process table could not be inspected, so an occupant of $wt cannot be ruled out — refusing to dispatch a second writer on an unproven answer. Install lsof, or re-run with CBR_ALLOW_UNPROVEN_OCCUPANCY=1 if you have checked by hand."
         note "launch: occupancy UNPROVEN and CBR_ALLOW_UNPROVEN_OCCUPANCY=1 was set — proceeding on the registry check alone, at the operator's word" ;;
  esac

  # SURFACE the dial BEFORE spending a token (the 'state the model to the human' rule)
  echo "launch: slug=$slug  model=$model  effort=$effort  worktree=$wt  perms=skip-permissions (unattended)"

  # On-plan BACKGROUND session (NO -p, NO tmux). `claude --bg` hands the session to the supervisor
  # daemon and returns immediately — no pty needed. A Claude Bash tool can't allocate a pty, so
  # `tmux new-session` is impossible from inside a Claude session; --bg is how an orchestrator (itself
  # a Claude session) dispatches a builder. The session is a TRUE independent root: it boots cd'd into
  # the provisioned worktree, and provision wrote "worktree.bgIsolation":"none" there so it edits THIS
  # worktree (its deps + branch + firewall) instead of auto-forking a fresh .claude/worktrees/ one.
  #
  # --dangerously-skip-permissions, NOT --permission-mode auto: an unattended builder writes compound
  # bash (RoboRev poll loops, inspection one-liners with `$(…)`) that the permission layer prompts on by
  # STRUCTURE — no allowlist can match a loop, so `auto` stalls on a prompt no human can answer.
  # Skipping permissions removes ONLY the prompt layer; the real guards are HOOKS and still bite:
  # Probity (PreToolUse TDD — proven to bite a --bg session 2026-06-23), the pre-commit gate, the
  # pre-push stream/* firewall, and per-commit RoboRev. (The prompt content IS read into this shell as
  # "$CBR_PROMPT" via $(cat …); it is safe not because it bypasses the shell but because it is always
  # double-quoted when handed to `claude`, so a ", $, or backtick in the prompt stays literal.)
  local out sid
  out="$(cd "$wt" && CBR_PROMPT="$(cat "$prompt_file")" && claude --bg "$CBR_PROMPT" --name "$slug" --model "$model" --effort "$effort" --dangerously-skip-permissions 2>&1)" \
    || { printf '%s\n' "$out" | head -5; die "launch: 'claude --bg' exited non-zero"; }
  # Observed format (verified 2026-06-23, CLI v2.1.186): "backgrounded · 46b83135" — a short 8-hex id; the
  # CLI may also emit a full dashed UUID. Match either off the "backgrounded" line (the registry probe below
  # uses startswith, so a short id still resolves the full sessionId). On a format change this fails closed
  # with the explicit error below — never a silent mis-dispatch.
  sid="$(printf '%s' "$out" | grep -i backgrounded | grep -oiE '[0-9a-f]{8}(-[0-9a-f]{4}){0,4}' | head -1)"
  [ -n "$sid" ] || { printf '%s\n' "$out" | head -5; die "launch: could not parse a session id from 'claude --bg' output"; }
  echo "  dispatched: sessionId=$sid"

  # PROOF it is really supervisor-managed (the survival property tmux used to give): it must appear in
  # the supervisor registry as a BACKGROUND session rooted in this worktree. Match by sessionId, with a
  # cwd fallback. Poll briefly — registration lags the dispatch by a beat. Silence here is an alarm.
  # NOTE: read the registry from a FILE, not `claude … | python3 - <<PY`. With a pipe AND a heredoc,
  # the heredoc wins python's stdin, so the piped JSON is lost and json.load(sys.stdin) reads empty.
  local i reg=1 jtmp; jtmp="$(mktemp)"
  for i in $(seq 1 12); do
    claude agents --json --all >"$jtmp" 2>/dev/null
    if python3 - "$jtmp" "$sid" "$wt_real" <<'PY'
import sys, json
path, sid, wt = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    rows = json.load(open(path))
except Exception:
    sys.exit(1)
for r in rows:
    if r.get("sessionId","").startswith(sid) or (r.get("cwd")==wt and r.get("kind")=="background"):
        sys.exit(0)
sys.exit(1)
PY
    then reg=0; break; fi
    sleep 1
  done
  rm -f "$jtmp"
  if [ "$reg" -eq 0 ]; then
    ok "registered with the supervisor (sessionId=$sid) — survives this orchestrator"
  else
    bad "session $sid not found in 'claude agents --json' after ${i}s — dispatch may have failed"; return 1
  fi
  # Lineage boundary: the dispatch is now CONFIRMED (registered), so this is the observation
  # moment — best-effort, never fails the launch (see emit_lineage_spawn).
  emit_lineage_spawn "$slug" "$sid" "$parent_id" "$agent_role"

  # ARM-OWNERSHIP (the cure for launch-and-forget). Dispatch and watch must not separate. cbr.sh
  # cannot arm the watcher ITSELF: a watcher backgrounded inside this child process detaches from the
  # orchestrator's session, so its fire-once exit would never wake the orchestrator (only a task the
  # orchestrator's OWN harness backgrounds delivers that wake). So launch does the next-best,
  # unmissable thing — drop a needs-arm sentinel that `cbr.sh status` turns into a loud UNWATCHED
  # alarm until it is cleared, and print the exact arm command as the REQUIRED final action.
  local root; root="$(cd "$(dirname "$0")/../../.." && pwd -P)"
  mkdir -p "$root/.cbr-watch" 2>/dev/null && : > "$root/.cbr-watch/$slug.needs-arm"
  rm -f "$root/.cbr-watch/$slug.heartbeat"   # a prior watcher's heartbeat must not read as "watched" for this fresh launch
  echo
  echo "  REQUIRED NEXT — background BOTH as tracked tasks (their exit is your wake; do NOT foreground):"
  echo "      cbr.sh watch $slug                                # its armed line prints cycle=<id>"
  echo "      cbr.sh watch $slug --watchdog --cycle <id>        # bind the dead-man to that exact cycle"
  echo "  Until then, 'cbr.sh status $slug' reports UNWATCHED.  (logs: claude logs $sid | stop: claude stop $sid)"
  echo "  CONTRACT CHECK: the dispatch prompt must tell the builder to COMMIT DONE.marker as its final"
  echo "  commit (a file-drop alone leaves 'stopped' ambiguous between COMPLETE and DIED)."
}

# ---------------------------------------------------------------------------
# watch <slug> [--watchdog [--cycle <id>]] [--stall-secs N] [--fail-grace-secs N]
#   Arm the captain's fire-once event trap over a dispatched builder — the step `launch` prints as
#   REQUIRED. A thin, discoverable front for scripts/captain-watch.sh: it resolves the script path (so
#   a context-less orchestrator need not know where it lives) and clears the launch needs-arm sentinel,
#   then execs the watcher. ALWAYS background this as a tracked task so its exit is the wake; run it
#   twice — the bare watcher FIRST, then --watchdog --cycle <id> with the cycle id the watcher's
#   armed line prints (binding the dead-man is what lets it retire cleanly after DONE). DECIDES NOTHING.
# ---------------------------------------------------------------------------
cmd_watch() {
  local slug="${1:-}"; shift || true
  [ -n "$slug" ] || die "usage: cbr.sh watch <slug> [--watchdog [--cycle <id>]] [...]  (ALWAYS background as a tracked task — its exit is your wake)"
  local dir root; dir="$(cd "$(dirname "$0")" && pwd -P)"; root="$(cd "$dir/../../.." && pwd -P)"
  [ -x "$dir/captain-watch.sh" ] || die "watch: $dir/captain-watch.sh missing or not executable"
  mkdir -p "$root/.cbr-watch" 2>/dev/null
  rm -f "$root/.cbr-watch/$slug.needs-arm"   # arming clears the launch sentinel — no longer UNWATCHED
  exec "$dir/captain-watch.sh" "$slug" "$@"
}

# ---------------------------------------------------------------------------
# status <slug>
#   One-shot ground-truth liveness — NOT a daemon, NOT a verdict. Reads the supervisor registry
#   (claude agents --json) for the background session rooted in this worktree and prints its state,
#   plus git progress facts read straight from the worktree. Exits non-zero only on HARD-dead facts
#   (no session). Staleness/state are facts (printed), not verdicts — the watcher weighs them against
#   its own interval, because silence is an ALARM, not a pass.
# ---------------------------------------------------------------------------
cmd_status() {
  local slug="${1:-}"; [ -n "$slug" ] || die "usage: cbr.sh status <slug>"
  local wt wt_real; wt="$(worktree_path "$slug")"; wt_real="$(cd "$wt" 2>/dev/null && pwd -P || echo "$wt")"
  command -v claude >/dev/null || die "status: claude not found on PATH"
  command -v python3 >/dev/null || die "status: python3 not found on PATH"

  echo "status: slug=$slug worktree=$wt"

  # a reaped worktree means closeout already ran — a stopped session lingering in the registry
  # must not read as a DIED builder (there is nothing left to build in).
  if [ ! -d "$wt" ]; then
    note "worktree does not exist — stream was closed out (or never provisioned); nothing to watch"
    echo "SUMMARY slug=$slug worktree=absent"
    return 1
  fi

  # liveness from the SUPERVISOR registry (no tmux, no pty). Match the background session rooted in this
  # worktree; print its state (working/blocked/done/failed) as a FACT, not a verdict.
  # read the registry from a FILE, not a pipe — a heredoc would otherwise steal python's stdin (see launch).
  local found jtmp; jtmp="$(mktemp)"
  claude agents --json --all >"$jtmp" 2>/dev/null
  found="$(python3 - "$jtmp" "$wt_real" <<'PY'
import sys, json
path, wt = sys.argv[1], sys.argv[2]
try:
    rows = json.load(open(path))
except Exception:
    sys.exit(0)
for r in rows:
    cwd = r.get("cwd","")
    if r.get("kind")=="background" and (cwd==wt or cwd.startswith(wt+"/")):
        print(f"{r.get('sessionId','')[:8]} {r.get('state','?')}")
        break
PY
)"
  rm -f "$jtmp"
  # A non-working session is only half a fact — DONE.marker presence disambiguates it.
  # stopped/done/absent WITH a marker = COMPLETE (verify + merge); WITHOUT = DIED mid-task
  # (read the logs). 2026-07-10: a finished builder read as a 4h stall because state=stopped
  # was dismissed as registry staleness with nothing here to say "its terminal signal exists".
  local dmark="no"; [ -f "$wt/DONE.marker" ] && dmark="yes"
  # readback fact (core law: build-loop.md). Computed BEFORE the session-presence
  # branches: a finished or dead builder is exactly when a dispatcher reads this —
  # at final verification, and in the post-mortem — so no SUMMARY may drop it.
  # Reported, never gated: it does not touch $verdict, like the UNWATCHED alarm.
  local rbstate; rbstate="$(readback_state "$wt")"
  case "$rbstate" in
    present) ok   "readback present in progress.md — read it against the plan before trusting the build" ;;
    MISSING) warn "readback MISSING from progress.md — the builder never restated mission/scope/OUT" ;;
    *)       note "no progress.md yet — too early to expect a readback" ;;
  esac
  if [ -z "$found" ]; then
    if [ "$dmark" = yes ]; then
      ok "no live session, but DONE.marker present — builder finished; verify + merge (do not treat as dead)"
      echo "SUMMARY slug=$slug session=absent done_marker=yes readback=$rbstate verdict=complete"
      return 0
    fi
    # "No registered session" is not "nobody is working here". A strand driven
    # by an INTERACTIVE session appears in no background registry at all, and
    # calling that died is the expensive direction: it invites a dispatcher to
    # launch a second builder onto live work, or to reap a worktree that still
    # has somebody in it. Ground truth for occupancy is a live process rooted in
    # the folder, so ask that before pronouncing death.
    local occ; occ="$(worktree_occupancy "$wt_real")"
    case "$occ" in
      yes) note "no background session, but a live process is rooted in this worktree — INTERACTIVE (or another harness): somebody is working here, do NOT relaunch or reap"
         echo "SUMMARY slug=$slug session=absent live_process=yes done_marker=no readback=$rbstate verdict=interactive"
         return 0 ;;
      no) bad "no background session rooted in this worktree AND no live process in it — builder is not running here (no DONE.marker: died or never launched)"
         echo "SUMMARY slug=$slug session=absent live_process=no done_marker=no readback=$rbstate verdict=died"
         return 1 ;;
      *) # "Could not look" is not "nobody is there". Since the merge-ownership
         # rule turns a death verdict into permission to take a strand over, an
         # unanswerable liveness question must not be answered as death.
         bad "no background session, and the process table could NOT be inspected — liveness is UNPROVEN; do not relaunch, reap, or take this strand over on the strength of this"
         echo "SUMMARY slug=$slug session=absent live_process=unknown done_marker=no readback=$rbstate verdict=unproven"
         return 1 ;;
    esac
  fi
  local sid state verdict="running" live_process="not-checked"; sid="${found%% *}"; state="${found##* }"
  ok "background session present: sessionId=$sid state=$state"
  case "$state" in
    failed)  # A failed session is a dead SESSION, not proof of an idle folder. The
             # takeover rule wants both facts (core build-loop step 9), and a
             # human picking up a crashed builder's worktree is the shape that
             # was actually observed.
             bad "session state=failed — needs attention; read: claude logs $sid"
             emit_lineage_exit "$slug" "$sid" error
             live_process="$(worktree_occupancy "$wt_real")"
             case "$live_process" in
               yes) note "...but a live process is rooted in this worktree — somebody is working here now; do NOT relaunch or reap"
                    verdict="interactive" ;;
               no)  verdict="died" ;;
               *)   bad "and the process table could NOT be inspected — occupancy is UNPROVEN; do not reap or take over on the strength of this"
                    verdict="unproven" ;;
             esac ;;
    blocked) note "session state=blocked — waiting on input/permission; read: claude logs $sid" ;;
    done|stopped|exited)
             # every terminal state needs the marker to count as COMPLETE — a session that
             # ended without its terminal signal did not fulfil the builder contract.
             if [ "$dmark" = yes ]; then
               ok "session state=$state WITH DONE.marker — builder COMPLETE; verify + merge"
               verdict="complete"
               [ "$state" = done ] && emit_lineage_exit "$slug" "$sid" complete
             else
               # The law that licenses a takeover wants BOTH facts (core
               # build-loop step 9), and this is the shape observed live: a bg
               # builder crashed, a human picked the worktree up interactively.
               # Reporting the dead session without the occupancy fact leaves an
               # orchestrator unable to obey the rule on the very path it matters.
               local docc; docc="$(worktree_occupancy "$wt_real")"
               case "$docc" in
                 yes) note "session state=$state WITHOUT DONE.marker, BUT a live process is rooted in this worktree — the registered session died and somebody is working here now; do NOT relaunch or reap"
                    verdict="interactive" ;;
                 no) bad "session state=$state WITHOUT DONE.marker and no live process in the worktree — builder DIED mid-task; read: claude logs $sid"
                    verdict="died"
                    [ "$state" = done ] && emit_lineage_exit "$slug" "$sid" error ;;
                 *) bad "session state=$state WITHOUT DONE.marker, and the process table could NOT be inspected — the session is gone but occupancy is UNPROVEN; do not reap or take over on the strength of this"
                    verdict="unproven" ;;
               esac
               live_process="$docc"
             fi ;;
  esac

  # ground-truth progress facts (read straight from the worktree — no session needed)
  local branch last_sha last_when age_s dirty
  branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  last_sha="$(git -C "$wt" log -1 --format=%h 2>/dev/null)"
  last_when="$(git -C "$wt" log -1 --format=%ci 2>/dev/null)"
  age_s="$(git -C "$wt" log -1 --format=%ct 2>/dev/null)"
  [ -n "$age_s" ] && age_s=$(( $(date +%s) - age_s ))
  dirty="$(git -C "$wt" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  note "branch=$branch  last_commit=$last_sha  at=$last_when  age=${age_s}s  uncommitted_files=$dirty"

  # open reviews on the branch (re-derived from the daemon, never inferred)
  if command -v roborev >/dev/null; then
    local rc; rc="$(roborev list --branch "$branch" 2>/dev/null | grep -ic 'open\|fail' || true)"
    note "open reviews (rough): ${rc:-0} — confirm before any merge with: roborev list --branch $branch"
  fi

  # UNWATCHED alarm (arm-ownership guard): a live builder with no armed watcher is silent drift. The
  # launch needs-arm sentinel persists until `cbr.sh watch` clears it; a fresh heartbeat (<15 min) is
  # positive proof a watcher is actually running. This only prints — status still exits 0 (not hard-dead).
  local root hb watched="no"
  root="$(cd "$(dirname "$0")/../../.." && pwd -P)"; hb="$root/.cbr-watch/$slug.heartbeat"
  if [ -f "$root/.cbr-watch/$slug.needs-arm" ]; then
    watched="no"   # launch's sentinel is AUTHORITATIVE: a prior watcher's still-fresh heartbeat on this
                   # slug must not mask a just-launched, not-yet-armed builder. Only `cbr.sh watch` clears it.
  elif [ -f "$hb" ] && [ $(( $(date +%s) - $(stat -f %m "$hb" 2>/dev/null || stat -c %Y "$hb" 2>/dev/null || echo 0) )) -lt 900 ]; then
    watched="yes"
  fi
  if [ "$watched" = yes ]; then
    ok "watcher armed (fresh heartbeat) for '$slug'"
  else
    bad "UNWATCHED — no fresh watcher heartbeat. ARM NOW (background both):  cbr.sh watch $slug   |   then cbr.sh watch $slug --watchdog --cycle <id from the watcher's armed line>"
  fi

  echo "SUMMARY slug=$slug session=present state=$state last_commit_age_s=${age_s:-unknown} uncommitted=$dirty watched=$watched done_marker=$dmark live_process=$live_process readback=$rbstate verdict=$verdict"
  note "weigh last_commit_age + state against YOUR watch interval — silence/stall is the page, not 'busy'."
  [ "$verdict" = died ] && return 1
  return 0
}

# ---------------------------------------------------------------------------
# fleet
#   The board: every live (or just-finished) fleet session, derived FRESH each run from the supervisor
#   registry + git worktrees + roborev. Persists NOTHING — re-run it after a compaction to recover the
#   picture (this is why the captain needs no context-only state). Role-aware by where it's invoked:
#   from the primary checkout it's the CAPTAIN's full board; from an integration/* worktree it tags
#   ● your streams vs ○ another orchestrator's (read from your task_plan.md) so an orchestrator can't
#   drift into someone else's session. Facts only — decides nothing.
# ---------------------------------------------------------------------------
cmd_fleet() {
  command -v python3 >/dev/null || die "fleet: python3 not found on PATH"
  local root inv_branch primary role
  root="$(repo_root)"
  inv_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  primary="$(git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | head -1)"
  if [ "$root" = "$primary" ]; then role="captain"
  elif printf '%s' "$inv_branch" | grep -q '^integration/'; then role="orchestrator"
  else role="other"; fi

  # owned worktree basenames (orchestrator only): the cockpit-* tokens in THIS worktree's task_plan.md
  # streams table. Fail-safe: unreadable -> empty -> generic caution, no ●/○ tags (never fail-confident).
  local owned; owned="$(mktemp)"; : > "$owned"
  if [ "$role" = "orchestrator" ] && [ -f "$root/task_plan.md" ]; then
    grep -oE 'cockpit-[a-zA-Z0-9._-]+' "$root/task_plan.md" 2>/dev/null | sort -u > "$owned"
  fi
  local agents wts; agents="$(mktemp)"; wts="$(mktemp)"
  claude agents --json --all >"$agents" 2>/dev/null || echo '[]' >"$agents"
  git worktree list --porcelain >"$wts" 2>/dev/null || true

  python3 - "$role" "$inv_branch" "$primary" "$agents" "$wts" "$owned" "$root" <<'PY'
import sys, json, subprocess, time, os
role, inv_branch, primary, agents_f, wts_f, owned_f, root = sys.argv[1:8]
wts = {}; cur = None
for ln in open(wts_f):
    ln = ln.rstrip("\n")
    if ln.startswith("worktree "):
        cur = ln[9:]; wts[cur] = {"branch": None}
    elif ln.startswith("branch ") and cur:
        wts[cur]["branch"] = ln[len("branch refs/heads/"):]
fleet = {p: i for p, i in wts.items() if "/cockpit-" in p and p != primary}
owned = set(x.strip() for x in open(owned_f) if x.strip())
try: rows = json.load(open(agents_f))
except Exception: rows = []

def gf(wt, args):
    try: return subprocess.run(["git","-C",wt]+args, capture_output=True, text=True, timeout=15).stdout.strip()
    except Exception: return ""
def age(ts):
    try: d = int(time.time()) - int(ts)
    except Exception: return "?"
    return f"{d}s" if d < 90 else (f"{d//60}m" if d < 5400 else f"{d//3600}h")

parts = []
for r in rows:
    if r.get("kind") != "background": continue
    cwd = r.get("cwd","") or ""
    m = next((p for p in fleet if cwd == p or cwd.startswith(p + "/")), None)
    if m: parts.append((r, m))

print()
if role == "captain":
    print("fleet — CAPTAIN view: full board, ALL canon fleets machine-wide.")
elif role == "orchestrator":
    print("fleet — ⚠ ALL canon fleet sessions machine-wide, not just yours.")
    print(f"  You orchestrate `{inv_branch}`. Act ONLY on ● rows (your task_plan.md);")
    print("  ○ rows are ANOTHER orchestrator's — do not read, merge, stop, or jump into them.")
else:
    print("fleet — ⚠ full board, ALL canon fleets machine-wide. Not an orchestrator, so")
    print("  ownership can't be read from a fleet plan: ● = your current worktree only.")
    print("  Act only on sessions you own.")
print()
if not parts:
    print("  (no live fleet sessions — no background session rooted in a cockpit-* worktree)")
else:
    print(f"    {'ROLE':12} {'SID':9} {'STATE':8} {'BRANCH':24} {'COMMIT':7} {'REV':4} WORKTREE")
    for r, wt in sorted(parts, key=lambda x: x[1]):
        br = fleet[wt]["branch"] or "?"
        wrole = "orchestrator" if br.startswith("integration/") else ("builder" if br.startswith("stream/") else "?")
        rev = "?"
        try:
            out = subprocess.run(["roborev","list","--branch",br], capture_output=True, text=True, timeout=15).stdout
            rev = str(sum(1 for l in out.splitlines() if "open" in l.lower() or "fail" in l.lower()))
        except Exception: rev = "?"
        mine = os.path.basename(wt) in owned or wt == root
        tag = ("  " if role == "captain" else ("● " if mine else "○ "))
        print(f"  {tag}{wrole:12} {(r.get('sessionId','') or '')[:8]:9} {r.get('state','?'):8} {br:24} {age(gf(wt,['log','-1','--format=%ct'])):7} {rev:4} {os.path.basename(wt)}")
print()
print("  jump in: claude logs <sid>  |  detail: read <worktree>/task_plan.md  |  derived live, persists nothing")
PY
  rm -f "$owned" "$agents" "$wts"
}

# ---------------------------------------------------------------------------
# arm <repo-path> [--no-probe]
#   Scaffold the full CBR harness into another repo from templates/: the skill folder itself,
#   Probity config + hooks, RoboRev config + the roborev-clean gate, the pre-commit skeleton,
#   re-injection docs, and the CBR conventions. IDEMPOTENT and NEVER-CLOBBER: every piece is
#   create-if-absent; anything already there is reported and left untouched (settings.json gets a
#   content check — present-but-Probity-less prints a manual-merge instruction instead of a copy).
#   Ends by dispatching the operability probe (templates/probe-prompt.md) as a `claude --bg`
#   session, because guarded ≠ operable — wiring proves nothing until a gate actually BLOCKS.
#   Skeletons ship FAIL-CLOSED: the EDIT-ME pre-commit hooks exit 1 until real commands are wired.
# ---------------------------------------------------------------------------
cmd_arm() {
  local target="${1:-}" no_probe=0
  shift 1 2>/dev/null || die "usage: cbr.sh arm <repo-path> [--no-probe]"
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-probe) no_probe=1; shift ;;
      *) die "arm: unknown arg '$1'" ;;
    esac
  done
  [ -n "$target" ] && [ -d "$target" ] || die "usage: cbr.sh arm <repo-path> [--no-probe]"
  target="$(cd "$target" && pwd -P)"
  git -C "$target" rev-parse --show-toplevel >/dev/null 2>&1 || die "arm: '$target' is not a git repo (git init it first)"
  [ "$(git -C "$target" rev-parse --show-toplevel)" = "$target" ] || die "arm: point at the repo ROOT, not a subdirectory"
  [ -d "$TPL" ] || die "arm: templates dir missing at $TPL — this skill copy is incomplete"
  command -v python3 >/dev/null || die "arm: python3 not found on PATH"

  local fails=0
  echo "arm: target=$target"
  echo "     templates=$TPL"

  # put <template-rel> <dest-rel> [exec] — create-if-absent, report-and-skip, never clobber
  put() {
    local src="$TPL/$1" dst="$target/$2"
    if [ -e "$dst" ]; then note "exists, left untouched: $2"; return 0; fi
    mkdir -p "$(dirname "$dst")"
    if cp "$src" "$dst"; then
      [ "${3:-}" = exec ] && chmod +x "$dst"
      ok "installed $2"
    else
      bad "failed to install $2"; fails=$((fails+1))
    fi
  }

  # 1. the skill folder — the playbook must live IN the repo so post-compaction re-injection works
  if [ -e "$target/skills/claude-controlled-build-run" ]; then
    note "exists, left untouched: skills/claude-controlled-build-run/"
  else
    mkdir -p "$target/skills"
    if cp -R "$SKILL_DIR" "$target/skills/claude-controlled-build-run"; then
      ok "installed skills/claude-controlled-build-run/ (SKILL.md + SETUP.md + scripts + templates)"
    else
      bad "failed to copy the skill folder"; fails=$((fails+1))
    fi
  fi

  # 2. Probity — config + the PreToolUse hook wiring in settings.json
  put probity.config.ts probity.config.ts
  if [ -e "$target/.claude/settings.json" ]; then
    local miss
    miss="$(missing_hook_wiring "$target/.claude/settings.json")"
    case $? in
      0) ok ".claude/settings.json already carries the full hook wiring + model pin — left untouched" ;;
      1) bad ".claude/settings.json exists but is MISSING hook wiring — arm never clobbers; merge these blocks from $TPL/claude-settings.json in BY HAND:"
         printf '%s\n' "$miss" | sed 's/^/          - /'
         fails=$((fails+1)) ;;
      *) bad ".claude/settings.json exists but is unreadable/invalid JSON — fix it, then merge the hooks blocks from $TPL/claude-settings.json"; fails=$((fails+1)) ;;
    esac
  else
    put claude-settings.json .claude/settings.json
  fi
  put hooks/roborev-gate.sh .claude/hooks/roborev-gate.sh exec
  put hooks/roborev-session-sweep.sh .claude/hooks/roborev-session-sweep.sh exec
  put hooks/post-compact-reground.sh .claude/hooks/post-compact-reground.sh exec
  put hooks/no-interactive-ask.sh .claude/hooks/no-interactive-ask.sh exec

  # 3. RoboRev — config + the close-every-review gate script
  put roborev.toml .roborev.toml
  put roborev-clean-gate.sh scripts/roborev-clean-gate.sh exec

  # 4. pre-commit gate — skeleton hooks fail closed until real commands are wired
  put pre-commit-config.yaml .pre-commit-config.yaml
  if command -v pre-commit >/dev/null; then
    if ( cd "$target" && pre-commit install >/dev/null 2>&1 ); then
      ok "pre-commit hook installed"
    else
      bad "pre-commit install failed"; fails=$((fails+1))
    fi
  else
    bad "pre-commit not on PATH — install it, then run 'pre-commit install' in $target"; fails=$((fails+1))
  fi

  # 5. re-injection docs — only if the repo has NO agent entry doc at all (never clobber)
  if [ -e "$target/AGENTS.md" ] || [ -e "$target/CLAUDE.md" ]; then
    note "exists, left untouched: AGENTS.md/CLAUDE.md (wire the CBR pointers in yourself if missing)"
  else
    cat > "$target/AGENTS.md" <<'DOC'
# AGENTS.md

This repo is armed for controlled build runs (CBR).

- The playbook: `skills/claude-controlled-build-run/SKILL.md` — read it before any build work.
- What "armed" means and why: `skills/claude-controlled-build-run/SETUP.md`.
- During a build, `task_plan.md` at the worktree root is the source of truth for that stream.
DOC
    ok "installed AGENTS.md (CBR pointer skeleton)"
  fi

  # 6. conventions — gitignore entries + the stream/* push firewall
  local line
  for line in ".cbr-watch/" ".claude/settings.local.json"; do
    if grep -qxF "$line" "$target/.gitignore" 2>/dev/null; then
      note "gitignore already has: $line"
    else
      echo "$line" >> "$target/.gitignore"
      ok "appended '$line' to .gitignore"
    fi
  done
  local pp; pp="$(git -C "$target" rev-parse --git-path hooks/pre-push 2>/dev/null)"
  case "$pp" in /*) : ;; *) pp="$target/$pp" ;; esac
  if [ -n "$pp" ]; then
    if ensure_push_firewall "$pp"; then
      ok "push firewall current (pre-push denies stream/* and any push to main unless CBR_ALLOW_PUSH=1)"
    else
      case "$?" in
        2) bad "pre-push hook at $pp mentions CBR_ALLOW_PUSH but is not a known CBR body (custom or hand-merged?) — left untouched; merge the two-layer firewall by hand" ;;
        3) bad "push firewall at $pp could NOT be made executable — git will silently skip it; fix filesystem permissions and re-run" ;;
        *) bad "a foreign pre-push hook already exists ($pp) — the stream/* push firewall was NOT installed; add the deny by hand" ;;
      esac
      fails=$((fails+1))
    fi
  fi

  echo
  if [ "$fails" -gt 0 ]; then
    bad "$fails piece(s) need hands-on fixes (listed above) — fix them, then re-run arm (it is idempotent)"
    note "the probe was NOT dispatched onto a half-armed repo"
    return 1
  fi
  note "scaffold complete. EDIT-ME files ship FAIL-CLOSED: wire real commands into"
  note ".pre-commit-config.yaml and real globs into probity.config.ts before the first build."

  # 7. the operability probe — guarded ≠ operable; arming ENDS with a gate proven to bite
  if [ "$no_probe" -eq 1 ]; then
    note "--no-probe: skipping the operability probe. The repo is NOT proven armed until"
    note "a probe passes — dispatch one before trusting it for a build."
    return 0
  fi
  command -v claude >/dev/null || { bad "claude not found on PATH — cannot dispatch the probe; repo is NOT proven armed"; return 1; }
  local out sid
  out="$(cd "$target" && CBR_PROMPT="$(cat "$TPL/probe-prompt.md")" && claude --bg "$CBR_PROMPT" --name "cbr-arm-probe" --dangerously-skip-permissions 2>&1)" \
    || { printf '%s\n' "$out" | head -5; bad "probe dispatch failed — repo is NOT proven armed"; return 1; }
  sid="$(printf '%s' "$out" | grep -i backgrounded | grep -oiE '[0-9a-f]{8}(-[0-9a-f]{4}){0,4}' | head -1)"
  [ -n "$sid" ] || { printf '%s\n' "$out" | head -5; bad "could not parse a probe session id — repo is NOT proven armed"; return 1; }
  ok "operability probe dispatched (sessionId=$sid)"
  note "READ ITS VERDICT before trusting this repo: claude logs $sid"
  note "it must end 'PROBE-RESULT: PROVE-NO BLOCKED / PROVE-YES OK' (or PASS-WITH-NOTE)."
  note "then pre-flight every build with: cbr.sh doctor $target"
}

# ---------------------------------------------------------------------------
# doctor [<repo-path>]
#   READ-ONLY health check of an armed repo — the standard pre-flight before every build. Prints
#   per-piece PASS/FAIL facts and a summary count; changes NOTHING and prints no verdict word.
#   Includes the one silent killer static checks can't see: an expired OAuth token (breaks Probity
#   and RoboRev at once) — caught by a real agent round-trip via `roborev check-agents`.
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# closeout-pending — the merge/reap seam the ritual was missing
#   The closeout ritual is law but nothing observed it, so merged worktrees piled
#   up (17 dead ones before `closeout` existed; the ritual alone did not stop the
#   pile from re-forming). This names them: a worktree whose branch is FULLY
#   merged into main has nothing left to build and should have been reaped.
#   WARN-ONLY, on purpose — it never deletes and never gates, because "merged"
#   is a fact about commits, not about whether a human still wants the folder.
#   Two skips, both loud: a worktree with uncommitted files (a human must eyeball
#   that work before it dies) and a worktree with a live process rooted in it (a
#   session is using it RIGHT NOW). A silent skip would read as "nothing pending",
#   which is exactly how a merged worktree hides forever — so each skip prints its
#   reason. Facts only; the reap decision stays with the human.
# ---------------------------------------------------------------------------
closeout_pending_report() {
  local root="$1" ref="" c
  for c in main master; do git -C "$root" rev-parse -q --verify "$c" >/dev/null 2>&1 && { ref="$c"; break; }; done
  if [ -z "$ref" ]; then
    note "closeout-pending: no main/master branch — cannot decide what is merged"
    echo "SUMMARY closeout_pending=0 skipped_dirty=0 skipped_live=0 base=absent"
    return 0
  fi

  # One lsof sweep for every worktree: a process's cwd is the honest, outside-view
  # proof that a folder is in use, and it needs no session registry to be true.
  # If lsof is absent we cannot prove absence of life, so we still name the
  # candidate but mark its liveness UNVERIFIED rather than implying it is idle.
  local cwds="" live_known=1
  if command -v lsof >/dev/null 2>&1; then
    cwds="$(lsof -w -d cwd -F n 2>/dev/null | sed -n 's/^n//p')"
  else
    live_known=0
  fi

  # The PRIMARY checkout is the first row of `worktree list` — NOT `$root`, which
  # is the toplevel of whichever worktree asked. Getting that wrong told a builder
  # to reap the primary checkout (its branch IS the base, so it is trivially
  # "merged"), which is the one folder that must never be a candidate.
  local pending=0 dirty_n=0 live_n=0 primary p real b dirty slug live_here cwd reap parent
  primary="$(git -C "$root" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | head -1)"
  primary="$(cd "$primary" 2>/dev/null && pwd -P || echo "$primary")"
  # IFS= : the default IFS would strip leading/trailing whitespace from a legal
  # worktree path, sending every later cd/git call to a path that does not exist.
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    real="$(cd "$p" 2>/dev/null && pwd -P)" || continue
    [ "$real" = "$primary" ] && continue          # never the primary checkout
    b="$(git -C "$p" branch --show-current 2>/dev/null)"
    [ -n "$b" ] || { note "closeout-pending: DETACHED $p — no branch, inspect by hand"; continue; }
    [ "$b" = "$ref" ] && continue                                                 # the base branch is never a stream to reap
    git -C "$root" merge-base --is-ancestor "$b" "$ref" 2>/dev/null || continue   # unmerged: real work, leave it alone

    # A shell sitting in src/ is as much "in use" as one at the root, so a cwd
    # ANYWHERE under the worktree counts: matching only the root would present a
    # worktree someone is working in as safe to reap. Compared as path prefixes,
    # not as a regex — a worktree path can contain regex metacharacters.
    live_here=no
    if [ "$live_known" -eq 1 ]; then
      while IFS= read -r cwd; do
        case "$cwd" in "$real"|"$real"/*) live_here=yes; break ;; esac
      done <<< "$cwds"
    fi
    if [ "$live_here" = yes ]; then
      note "closeout-pending: SKIPPED $p (branch=$b) — merged, but a live process is rooted here (or in a subdirectory)"
      live_n=$((live_n + 1)); continue
    fi
    dirty="$(git -C "$p" status --porcelain 2>/dev/null | grep -c . || true)"
    if [ "$dirty" -gt 0 ]; then
      note "closeout-pending: SKIPPED $p (branch=$b) — merged, but $dirty uncommitted file(s); a human eyeballs them before it dies"
      dirty_n=$((dirty_n + 1)); continue
    fi

    # `cbr.sh closeout <slug>` resolves the slug to ../cockpit-<slug> and NOTHING
    # else, so offering it for a worktree that does not live there would point a
    # human at a different folder — or at one that does not exist. Name the
    # subcommand only when the path it resolves to IS this path; otherwise give a
    # command that names the path explicitly.
    slug="$(basename "$real")"; slug="${slug#cockpit-}"
    parent="$(cd "$(dirname "$primary")" 2>/dev/null && pwd -P)"
    # Every interpolated word is %q-escaped: a path may legitimately contain a
    # space or a shell metacharacter, and a suggestion a human copies must be
    # exactly one command with exactly the arguments shown.
    if [ "$real" = "$parent/cockpit-$slug" ]; then
      reap="cbr.sh closeout $(printf '%q' "$slug") --into $(printf '%q' "$ref")"
    else
      reap="git -C $(printf '%q' "$primary") worktree remove $(printf '%q' "$p") && git -C $(printf '%q' "$primary") branch -d $(printf '%q' "$b")"
    fi
    warn "CLOSEOUT PENDING  $p  branch=$b — fully merged into $ref, worktree still here; reap: $reap$([ "$live_known" -eq 0 ] && echo '  [liveness UNVERIFIED: lsof absent]')"
    pending=$((pending + 1))
  done <<EOF
$(git -C "$root" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
EOF

  [ "$pending" -eq 0 ] && ok "no merged-but-unreaped worktrees"
  echo "SUMMARY closeout_pending=$pending skipped_dirty=$dirty_n skipped_live=$live_n base=$ref"
  return 0
}

# ---------------------------------------------------------------------------
# readback — is the plan's mission/scope/OUT restated in the builder's own words?
#
# Core law (cbr-core/build-loop.md "Readback"): a dispatched builder's first act
# is to write that restatement into progress.md, and the dispatcher checks it
# before leaving the builder to run. PRESENCE is a deterministic fact, so it may
# be reported; whether the readback is FAITHFUL is a judgment, so this never
# gates and never returns non-zero (policy.md).
#
# "Present" demands substance, not the ritual word: a heading BEGINNING with
# "readback" — a builder titling its restatement, where "P-C — readback laws in
# core" is a journal entry about one — followed by at least three non-blank
# lines before the next heading of the SAME OR SHALLOWER level. A sub-heading
# does not end the readback, because the law asks for three named things
# (mission, scope, OUT) and writing them as `### Mission` / `### OUT` is
# following it, not evading it. Fenced code blocks are skipped — a quoted
# template is documentation about the format, not a builder using it. An empty
# heading is the failure this fact exists to catch: it is what a builder that
# skimmed the plan produces.
readback_state() {
  local wt="$1" f="$wt/progress.md"
  [ -f "$f" ] || { echo "no-progress-file"; return 0; }
  awk '
    { sub(/\r$/, "") }
    # CommonMark fences, both flavours: a fence closes only on a run of the SAME
    # character at least as long as the opener. Anything shorter, or the other
    # flavour, is content — patching one shape at a time never converges here,
    # so this follows the actual rule.
    /^[[:space:]]*(```|~~~)/ {
      match($0, /`+|~+/); ftype = substr($0, RSTART, 1); flen = RLENGTH
      rest = substr($0, RSTART + RLENGTH)
      if (!fence) { fence = 1; fchar = ftype; fmin = flen }        # opener may carry an info string
      else if (ftype == fchar && flen >= fmin && rest ~ /^[[:space:]]*$/) { fence = 0 }
      next                                                        # closer may carry only whitespace
    }
    fence { next }   # excluded everywhere, including under a valid heading
    /^#+[[:space:]]/ {
      match($0, /^#+/); lvl = RLENGTH
      # Leading word, not "contains": a cap on heading length rejects a heading
      # that explains itself ("Readback (mission, scope, OUT)") while still
      # admitting a short journal title.
      subject = substr($0, lvl + 1)
      sub(/^[^[:alnum:]]+/, "", subject)
      match(subject, /^[[:alnum:]]+/)
      is_rb = (tolower(substr(subject, 1, RLENGTH)) == "readback")
      if (in_rb) {
        if (lvl <= rb_lvl) {
          if (body >= 3) found = 1
          in_rb = 0
        } else next          # a sub-heading is part of the readback, not its end
      }
      if (is_rb) { in_rb = 1; rb_lvl = lvl; body = 0 }
      next
    }
    in_rb && $0 ~ /[^[:space:]]/ { body++ }
    END { if (found || (in_rb && body >= 3)) print "present"; else print "MISSING" }
  ' "$f"
}

readback_report() {
  local wt="$1" state
  state="$(readback_state "$wt")"
  case "$state" in
    present) ok   "readback present in progress.md — check it against the plan's mission/scope/OUT (faithfulness is yours to judge, not this script's)" ;;
    MISSING) warn "readback MISSING — progress.md has no restatement of mission/scope/OUT. A builder that skipped it is a builder that skimmed the plan; ask for it before letting it run further" ;;
    *)       note "no progress.md yet in $wt — too early to expect a readback" ;;
  esac
  echo "readback=$state"
  return 0
}

cmd_readback() {
  local target="${1:-$PWD}"
  local wt="$target"
  [ -d "$wt" ] || wt="$(worktree_path "$target")"
  [ -d "$wt" ] || die "readback: '$target' is neither a directory nor a provisioned slug"
  readback_report "$wt"
}

cmd_closeout_pending() {
  local target="${1:-$PWD}"
  [ -d "$target" ] || die "closeout-pending: '$target' is not a directory"
  local root; root="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)"     || die "closeout-pending: '$target' is not inside a git repo"
  closeout_pending_report "$root"
}

cmd_doctor() {
  local target="${1:-$PWD}"
  [ -d "$target" ] || die "doctor: '$target' is not a directory"
  target="$(cd "$target" && pwd -P)"
  local root; root="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)" || die "doctor: '$target' is not inside a git repo"
  command -v python3 >/dev/null || die "doctor: python3 not found on PATH"

  local fails=0
  echo "doctor: repo=$root"

  # the playbook
  [ -f "$root/skills/claude-controlled-build-run/SKILL.md" ] \
    && ok "skill folder present (skills/claude-controlled-build-run/)" \
    || { bad "skill folder missing — post-compaction re-injection has nothing to re-inject (run: cbr.sh arm $root)"; fails=$((fails+1)); }

  # Probity: config + hook wiring
  [ -f "$root/probity.config.ts" ] \
    && ok "probity.config.ts present" \
    || { bad "probity.config.ts missing — Probity has no rules to enforce"; fails=$((fails+1)); }
  if [ -f "$root/.claude/settings.json" ]; then
    local miss
    miss="$(missing_hook_wiring "$root/.claude/settings.json")"
    case $? in
      0) ok "full hook wiring + model pin live in .claude/settings.json" ;;
      1) bad "settings.json is MISSING live hook wiring (scripts on disk fire NOTHING without it):"
         printf '%s\n' "$miss" | sed 's/^/          - /'
         fails=$((fails+1)) ;;
      *) bad "settings.json unreadable/invalid JSON"; fails=$((fails+1)) ;;
    esac
    # Compaction triple (operator-set; canon prior art): compact late, at 85% of 350k.
    local acw
    acw="$(python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(d.get('autoCompactEnabled'),d.get('autoCompactWindow'),d.get('autoCompactThreshold'))" "$root/.claude/settings.json" 2>/dev/null)"
    if [ "$acw" = "True 350000 0.85" ]; then
      ok "compaction triple set (enabled, window=350000, threshold=0.85 — see SKILL.md 'Compaction window')"
    else
      bad "compaction triple missing/wrong (got '${acw:-unset}', want 'True 350000 0.85') — see SKILL.md 'Compaction window'"
      fails=$((fails+1))
    fi
  else
    bad ".claude/settings.json missing — no hooks fire at all"; fails=$((fails+1))
  fi
  local h
  for h in roborev-gate.sh roborev-session-sweep.sh post-compact-reground.sh no-interactive-ask.sh; do
    [ -x "$root/.claude/hooks/$h" ] \
      && ok "hook present + executable: .claude/hooks/$h" \
      || { bad "hook missing or not executable: .claude/hooks/$h"; fails=$((fails+1)); }
  done

  # RoboRev: config, gate script, daemon, and the OAuth round-trip
  [ -f "$root/.roborev.toml" ] \
    && ok ".roborev.toml present" \
    || { bad ".roborev.toml missing — commits get no review"; fails=$((fails+1)); }
  [ -x "$root/scripts/roborev-clean-gate.sh" ] \
    && ok "roborev-clean gate script present + executable" \
    || { bad "scripts/roborev-clean-gate.sh missing or not executable"; fails=$((fails+1)); }
  if command -v roborev >/dev/null; then
    if ( cd "$root" && roborev list >/dev/null 2>&1 ); then
      ok "roborev daemon reachable"
    else
      bad "roborev daemon not reachable (is it running?)"; fails=$((fails+1))
    fi
    # the silent killer: an expired OAuth token breaks Probity AND RoboRev at once, quietly.
    # check-agents does a REAL agent round-trip — the only check that catches it.
    if ( cd "$root" && roborev check-agents >/dev/null 2>&1 ); then
      ok "agent round-trip succeeded (OAuth token alive)"
    else
      bad "agent round-trip FAILED — likely an expired OAuth token; fix: /login in an interactive claude session"; fails=$((fails+1))
    fi
  else
    bad "roborev not on PATH"; fails=$((fails+1))
  fi

  # pre-commit gate
  if [ -f "$root/.pre-commit-config.yaml" ]; then
    grep -q "roborev-clean" "$root/.pre-commit-config.yaml" \
      && ok "roborev-clean gate wired in .pre-commit-config.yaml" \
      || { bad "roborev-clean gate MISSING from .pre-commit-config.yaml — reviews can be outrun"; fails=$((fails+1)); }
    grep -q "EDIT ME" "$root/.pre-commit-config.yaml" \
      && { bad "EDIT-ME placeholder hooks still wired — every commit fails closed until real typecheck/test commands go in"; fails=$((fails+1)); }
  else
    bad ".pre-commit-config.yaml missing — no commit gate"; fails=$((fails+1))
  fi
  local hook; hook="$(git -C "$root" rev-parse --git-path hooks/pre-commit 2>/dev/null)"
  case "$hook" in /*) : ;; *) hook="$root/$hook" ;; esac
  [ -n "$hook" ] && [ -x "$hook" ] \
    && ok "pre-commit hook installed + executable" \
    || { bad "pre-commit hook not installed (run 'pre-commit install')"; fails=$((fails+1)); }
  command -v gitleaks >/dev/null \
    && ok "gitleaks on PATH" \
    || { bad "gitleaks not on PATH — the secrets gate will 127"; fails=$((fails+1)); }

  # push firewall
  local pp; pp="$(git -C "$root" rev-parse --git-path hooks/pre-push 2>/dev/null)"
  case "$pp" in /*) : ;; *) pp="$root/$pp" ;; esac
  if [ -n "$pp" ] && [ -e "$pp" ] && grep -q "CBR_ALLOW_PUSH" "$pp" 2>/dev/null; then
    local want_pp; want_pp="$(mktemp)"; write_push_firewall "$want_pp"
    if cmp -s "$want_pp" "$pp" && [ -x "$pp" ]; then
      ok "push firewall installed (current body: branch layer + pushed-ref layer)"
    elif cmp -s "$want_pp" "$pp"; then
      bad "push firewall body is current but NOT executable — git silently skips it; re-run arm (or chmod +x $pp)"; fails=$((fails+1))
    else
      bad "push firewall is a stale or edited body — a push to main may pass; re-run arm to upgrade"; fails=$((fails+1))
    fi
    rm -f "$want_pp"
  else
    bad "push firewall missing — an unattended builder could push"; fails=$((fails+1))
  fi

  # re-injection docs
  { [ -e "$root/AGENTS.md" ] || [ -e "$root/CLAUDE.md" ]; } \
    && ok "agent entry doc present (AGENTS.md/CLAUDE.md)" \
    || { bad "no AGENTS.md/CLAUDE.md — agents boot blind"; fails=$((fails+1)); }

  # WARN-ONLY: merged-but-unreaped worktrees. Deliberately outside $fails — a
  # pending closeout is housekeeping the human owns, not a broken harness, and a
  # doctor that fails on it would block builds over a stale folder.
  echo
  closeout_pending_report "$root"

  # WARN-ONLY: stale harness tooling (strand-lib probe; fails open on missing
  # tools/network). Outside $fails — updating is a human decision, never a gate.
  if command -v cbr_tool_staleness_report >/dev/null 2>&1; then
    local pin stale
    pin="$(sed -nE 's/.*@nizos\/probity@([0-9][0-9.]*).*/\1/p' "$root/.claude/settings.json" 2>/dev/null | head -1)"
    while IFS= read -r stale; do
      [ -n "$stale" ] && warn "$stale"
    done < <(cbr_tool_staleness_report "$pin")
  fi

  echo
  echo "SUMMARY repo=$root checks_failed=$fails"
  [ "$fails" -eq 0 ] || return 1
}

# ---- dispatch ----
# ---- closeout: the death ritual, symmetric with provision (the birth ritual). A stream's
# completion event is the MERGE; closeout runs in the same motion so finished worktrees,
# branches, and watch files never pile up (17 dead worktrees accumulated before this existed,
# 2026-07-09). Fail-closed everywhere: refuses a live session, refuses unmerged code, refuses
# uncommitted files without an explicit --force-dirty after human inspection. ----
cmd_closeout() {
  local slug="${1:-}" into="" force=0
  shift 1 2>/dev/null || die "usage: cbr.sh closeout <slug> [--into <ref>] [--force-dirty]"
  while [ $# -gt 0 ]; do
    case "$1" in
      --into)        into="${2:-}"; shift 2 ;;
      --force-dirty) force=1; shift ;;
      *) die "closeout: unknown arg '$1'" ;;
    esac
  done
  [ -n "$slug" ] || die "usage: cbr.sh closeout <slug> [--into <ref>] [--force-dirty]"

  local root wt wt_real branch
  root="$(repo_root)"; wt="$(worktree_path "$slug")"
  [ -d "$wt" ] || die "closeout: worktree '$wt' does not exist — nothing to close"
  wt_real="$(cd "$wt" && pwd -P)"
  [ "$wt_real" = "$(cd "$root" && pwd -P)" ] && die "closeout: refusing to close the checkout you are running from"
  branch="$(git -C "$wt" branch --show-current 2>/dev/null)"
  [ -n "$branch" ] || die "closeout: '$wt' is on no branch (detached HEAD) — close manually"
  echo "closeout: slug=$slug branch=$branch worktree=$wt"

  # 1. LIVE-SESSION GUARD — same registry read as launch's one-writer preflight; a blocked/
  #    frozen session still owns the worktree. Unlike launch (which warns-and-proceeds because
  #    its post-dispatch probe re-checks), closeout is DESTRUCTIVE, so this guard fails CLOSED:
  #    no registry proof of no-owner means no reap.
  command -v claude >/dev/null || die "closeout: claude not found on PATH — cannot prove no live session owns $wt (the guard is mandatory for a destructive command)"
  command -v python3 >/dev/null || die "closeout: python3 not found on PATH — cannot prove no live session owns $wt (the guard is mandatory for a destructive command)"
  local occ jtmp rc; jtmp="$(mktemp)"
  if ! claude agents --json --all >"$jtmp" 2>/dev/null || [ ! -s "$jtmp" ]; then
    rm -f "$jtmp"
    die "closeout: could not read the supervisor registry (claude agents --json --all) — refusing to reap without proof that no live session owns $wt"
  fi
  occ="$(python3 - "$jtmp" "$wt_real" <<'PY'
import sys, json
path, wt = sys.argv[1], sys.argv[2]
DEAD = {"done", "stopped", "failed", "error", "killed", "exited", "cancelled", "canceled"}
try:
    rows = json.load(open(path))
except Exception:
    sys.exit(3)  # unreadable JSON -> distinct code so the caller dies, never silently proceeds
for r in rows:
    if r.get("kind") != "background":
        continue
    cwd = r.get("cwd") or ""
    if not (cwd == wt or cwd.startswith(wt + "/")):
        continue
    st = (r.get("state") or "").strip().lower()
    if st in DEAD:
        continue
    print("%s|%s" % (r.get("sessionId", "?"), st or "unknown"))
    break
PY
)"
  rc=$?
  rm -f "$jtmp"
  [ "$rc" -eq 0 ] || die "closeout: supervisor registry output was unreadable (JSON parse failed) — refusing to reap without proof that no live session owns $wt"
  [ -z "$occ" ] || die "closeout: a live background session (${occ%%|*}, state=${occ##*|}) is rooted in $wt — stop it first: claude stop ${occ%%|*}"
  ok "no live session owns the worktree (registry-proven)"

  # 1b. PROVE UNOCCUPIED — the registry only knows about sessions IT launched. A
  #     strand driven interactively, or by another harness, is invisible to it,
  #     and the merge-ownership rule (core build-loop step 9) makes that
  #     difference matter: taking a strand over is licensed by the builder being
  #     PROVEN dead. Occupancy is a live process rooted in the folder, and for a
  #     destructive command an unanswerable question is a refusal, not a pass.
  if command -v cbr_path_has_live_process >/dev/null; then
    local occrc=0
    if cbr_path_has_live_process "$wt"; then occrc=0; else occrc=$?; fi
    case "$occrc" in
      0) die "closeout: a live process is rooted in $wt — somebody is working in this strand (interactive session, or another harness). The builder owns its own merge and closeout; take it over only when it is proven dead." ;;
      1) ok "no live process is rooted in the worktree (process-table-proven)" ;;
      *) [ "${CBR_ALLOW_UNPROVEN_OCCUPANCY:-}" = "1" ] \
           || die "closeout: the process table could not be inspected, so an occupant cannot be ruled out — refusing to reap $wt on an unproven liveness answer. Install lsof, or re-run with CBR_ALLOW_UNPROVEN_OCCUPANCY=1 if you have checked by hand."
         note "occupancy UNPROVEN, and an operator asserted the worktree is empty (CBR_ALLOW_UNPROVEN_OCCUPANCY=1)" ;;
    esac
  else
    die "closeout: the shared occupancy check is unavailable — refusing to reap $wt without proof that nobody is working in it"
  fi

  # 2. PROVE MERGED — content diff over product paths must be empty vs the target ref.
  #    Content, not ancestry: bookkeeping commits (DONE.marker drop, plan edits) legitimately
  #    trail the merge and must not block the reap; a rebased merge passes here where
  #    --is-ancestor would false-negative.
  #    Known fail-closed case, accepted: a SQUASH-merged stream refuses here (its commits
  #    are unreachable from the merge base), which is the safe direction — this gate may
  #    wrongly refuse, never wrongly reap. An endpoint diff ($ref vs $branch two-dot) would
  #    instead false-refuse EVERY normal closeout, since the integration tip always carries
  #    other streams' code the branch lacks. Squash flows aren't part of this merge gate;
  #    if one ever is, prove containment per-commit (cherry/patch-id), not by endpoint diff.
  local ref="$into"
  if [ -z "$ref" ]; then
    for c in main master; do git -C "$root" rev-parse -q --verify "$c" >/dev/null 2>&1 && { ref="$c"; break; }; done
  fi
  [ -n "$ref" ] || die "closeout: no main/master found and no --into given"
  local code_diff
  code_diff="$(git -C "$root" diff --name-only "$ref...$branch" -- packages adapters e2e public scripts 2>/dev/null)"
  if [ -n "$code_diff" ]; then
    bad "'$branch' carries code not in '$ref':"
    echo "$code_diff" | sed 's/^/          /'
    die "closeout: merge it first, or pass --into <ref> if it merged into an integration branch instead"
  fi
  ok "code content of '$branch' fully present in '$ref'"

  # 3. DIRTY GUARD — uncommitted files need a human eyeball before they die.
  local dirty; dirty="$(git -C "$wt" status --porcelain 2>/dev/null)"
  if [ -n "$dirty" ]; then
    if [ "$force" -ne 1 ]; then
      bad "worktree has uncommitted files — inspect them, then re-run with --force-dirty if disposable:"
      echo "$dirty" | sed 's/^/          /'
      die "closeout: refusing to reap uncommitted work without --force-dirty"
    fi
    note "reaping over $(echo "$dirty" | wc -l | tr -d ' ') uncommitted file(s) per --force-dirty"
  fi

  # 4. THE THREE DUTIES CLOSEOUT OWES THE BASE (references/core/build-loop.md step 9):
  #    archive the strand's records out of its FINAL COMMIT, drop its completion marker
  #    from the base, and reground the base's root plan. All three are the shared,
  #    provider-neutral mechanism — this leaf supplies only the filenames and paths.
  #
  #    The archive used to read the WORKTREE and skip whatever matched this checkout's
  #    copy. After a merge those are the same bytes, so it archived nothing and a human
  #    did it by hand; and the strand's DONE.marker stayed on the base, rode the next
  #    strand's merge-from-base, and falsely latched that strand's watcher.
  command -v cbr_closeout_base_duties >/dev/null \
    || die "closeout: the shared closeout library is missing ($CBR_STRAND_LIB) — refusing to reap a strand whose records cannot be archived"

  local arch="$root/docs/streams/archive/$slug" duties n
  # Reground the plan to the branch the BASE CHECKOUT is actually on, which is what
  # the plan-coherence gate compares against — not to $ref, which may name an
  # integration branch this checkout does not have out.
  local base_branch; base_branch="$(git -C "$root" branch --show-current 2>/dev/null)"
  [ -n "$base_branch" ] || base_branch="$ref"

  duties="$(cbr_closeout_base_duties "$root" "$branch" "$base_branch" "$arch" \
              DONE.marker task_plan.md \
              task_plan.md progress.md findings.md STATUS.md DONE.marker NEEDS-OPERATOR.md \
              KNOWN-LIMITATIONS.md MORNING-REPORT.md ASK-ORCH.md ORCH-ANSWER.md \
              WAITING-ON-BACKEND.md)" \
    || die "closeout: a base-branch duty failed ($duties) — the worktree and branch are UNTOUCHED; fix it and re-run"

  # The watch digest is a record the shared duties know nothing about, and the
  # reap below deletes the only other copy of it. Copy and stage are one shared
  # call whose failure is fatal, rather than two lines joined by `&&` where a
  # failure is swallowed and the reap proceeds anyway.
  if [ -f "$root/.cbr-watch/$slug.commits" ]; then
    cbr_archive_extra_record "$root/.cbr-watch/$slug.commits" "$arch" \
      "$root" "docs/streams/archive/$slug" >/dev/null \
      || die "closeout: could not archive the watch digest — the worktree and branch are UNTOUCHED; fix it and re-run"
  fi
  n="$(printf '%s' "$duties" | sed -nE 's/.*archived=([0-9]+).*/\1/p')"
  ok "base duties: $duties → docs/streams/archive/$slug/ (all staged; commit with the closeout)"

  # 5. REAP
  local frc=""; [ "$force" -eq 1 ] && frc="--force"
  git -C "$root" worktree remove $frc "$wt" 2>/dev/null || die "closeout: git worktree remove failed for $wt (re-run with --force-dirty if it's generated files)"
  git -C "$root" branch -D "$branch" >/dev/null || die "closeout: branch delete failed for $branch"
  rm -f "$root/.cbr-watch/$slug."*
  ok "reaped: worktree removed, branch '$branch' deleted, watch files cleaned"
  echo "SUMMARY closeout slug=$slug branch=$branch archived=${n:-0} merged_into=$ref"
}

# ---- janitor: the reconciliation backstop over closeout. Diffs REALITY against the desired
# state ("no merged branch keeps a worktree; no branch outlives its purpose; no watch file
# outlives its stream") and REPORTS — it deletes nothing, a human approves each reap. Exists
# because leaks still happen (crashed sessions, abandoned experiments); policy keeps rot at
# zero, the janitor keeps a leak's lifetime to days instead of months. ----
cmd_janitor() {
  local root ref="" c
  root="$(repo_root)"
  for c in main master; do git -C "$root" rev-parse -q --verify "$c" >/dev/null 2>&1 && { ref="$c"; break; }; done
  [ -n "$ref" ] || die "janitor: no main/master branch found"
  echo "janitor: read-only reconciliation vs '$ref' — reap candidates need: cbr.sh closeout <slug> [--into <ref>]"

  local reap=0 active=0 p b d
  # IFS= : the default IFS would strip leading/trailing whitespace from a legal
  # worktree path, sending every later cd/git call to a path that does not exist.
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    [ "$(cd "$p" 2>/dev/null && pwd -P)" = "$(cd "$root" && pwd -P)" ] && continue
    b="$(git -C "$p" branch --show-current 2>/dev/null)"
    if [ -z "$b" ]; then note "DETACHED  $p — no branch, inspect manually"; continue; fi
    d="$(git -C "$p" status --porcelain 2>/dev/null | grep -c . || true)"
    if [ -z "$(git -C "$root" diff --name-only "$ref...$b" -- packages adapters e2e public scripts 2>/dev/null)" ]; then
      echo "  REAPABLE  $p  branch=$b  dirty=$d"
      reap=$((reap + 1))
    else
      echo "  ACTIVE    $p  branch=$b  dirty=$d  (code not in $ref)"
      active=$((active + 1))
    fi
  done <<EOF
$(git -C "$root" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | tail -n +2)
EOF

  local orphans
  orphans="$(git -C "$root" for-each-ref --format='%(refname:short)' 'refs/heads/stream/*' 'refs/heads/integration/*' 2>/dev/null |
    while read -r b; do
      git -C "$root" worktree list --porcelain | grep -q "^branch refs/heads/$b\$" && continue
      echo "$b"
    done)"
  if [ -n "$orphans" ]; then
    echo "  ORPHAN branches (no worktree — delete with git branch -D after confirming merged):"
    echo "$orphans" | sed 's/^/          /'
  fi

  local stale
  stale="$(ls "$root/.cbr-watch" 2>/dev/null | sed 's/\.[^.]*$//' | sort -u |
    while read -r s; do [ -d "$(dirname "$root")/cockpit-$s" ] || echo "$s"; done)"
  [ -n "$stale" ] && { echo "  STALE .cbr-watch entries (stream gone):"; echo "$stale" | sed 's/^/          /'; }

  echo "SUMMARY janitor reapable=$reap active=$active orphan_branches=$(echo "$orphans" | grep -c . || true)"
}

case "${1:-help}" in
  provision) shift; cmd_provision "$@" ;;
  launch)    shift; cmd_launch "$@" ;;
  status)    shift; cmd_status "$@" ;;
  watch)     shift; cmd_watch "$@" ;;
  fleet)     shift; cmd_fleet "$@" ;;
  arm)       shift; cmd_arm "$@" ;;
  doctor)    shift; cmd_doctor "$@" ;;
  closeout)  shift; cmd_closeout "$@" ;;
  janitor)   shift; cmd_janitor "$@" ;;
  closeout-pending) shift; cmd_closeout_pending "$@" ;;
  readback) shift; cmd_readback "$@" ;;
  help|-h|--help)
    cat <<'USAGE'
cbr.sh — controlled-build-run companion: the deterministic launch rail for parallel builders.

One entry point, a few subcommands. Each gathers facts / runs a fixed sequence and DECIDES NOTHING:
it fails closed on a hard fact, never auto-merges/relaunches/kills, and never prints a health
verdict. There is no "do everything" command — run the one for the moment you're at.

  cbr.sh provision <slug> <branch> [--base <ref>]
      Set up a fresh builder worktree so the first commit doesn't die: worktree+branch, the
      gitignored deps (node_modules symlink + uv sync), the §7 allowlist, and the armed-checks.
      Does NOT launch claude or write the plan.

  cbr.sh launch <slug> --prompt-file <file> [--model <id>] [--effort <e>]
      Dispatch the on-plan builder as a `claude --bg` background session (supervisor-managed, so it
      survives the orchestrator) and confirm it registered. Takes the dispatch prompt as a file;
      never composes it. No pty needed — works from inside a Claude session, where tmux can't.

  cbr.sh status <slug>
      One-shot ground-truth liveness from the supervisor registry (background session up? what
      state? last commit age? open reviews?). Prints facts and exits non-zero only on hard-dead
      facts. Not a verdict. Also flags UNWATCHED — a live builder with no armed watcher.

  cbr.sh watch <slug> [--watchdog [--cycle <id>]]
      Arm the captain's fire-once event trap over a dispatched builder (the step `launch` prints as
      REQUIRED). ALWAYS background as a tracked task so its exit is the wake; run it twice — bare
      (watcher) FIRST, then --watchdog --cycle <id> using the cycle id the watcher's armed line
      prints (binding the dead-man to that exact cycle is what lets it retire cleanly after DONE
      instead of paging). Wraps captain-watch.sh; clears the needs-arm sentinel.

  cbr.sh fleet
      The board: every live fleet session (orchestrators + builders), derived FRESH from the
      supervisor registry + git worktrees + roborev — persists nothing, so re-run it to recover
      the picture after a compaction. Role-aware: CAPTAIN's full board from the primary checkout;
      from an integration/* worktree it tags ● your streams vs ○ another orchestrator's. Facts only.

  cbr.sh arm <repo-path> [--no-probe]
      Scaffold the full CBR harness into another repo from this skill's templates/: skill folder,
      Probity config+hook wiring, RoboRev config + roborev-clean gate, pre-commit skeleton
      (fail-closed EDIT-MEs), re-injection docs, gitignore entries, push firewall. Create-if-absent
      and never-clobber; idempotent. ENDS by dispatching the operability probe (guarded ≠ operable)
      unless --no-probe. See SETUP.md for what the six pieces are and why.

  cbr.sh doctor [<repo-path>]
      READ-ONLY pre-flight for an armed repo (run before EVERY build): per-piece PASS/FAIL facts —
      skill folder, Probity wiring, hooks, RoboRev config/daemon, the OAuth agent round-trip (the
      silent killer), pre-commit + roborev-clean gate, push firewall, entry docs. Changes nothing.

  cbr.sh closeout <slug> [--into <ref>] [--force-dirty]
      The death ritual, symmetric with provision — run as the FINAL step of every stream merge
      (the merge is the completion event; closeout rides it, nobody has to remember). Refuses a
      live session, refuses unmerged code (content diff vs main, or --into for integration-only
      merges), refuses uncommitted files without --force-dirty after a human eyeball. Archives
      the stream's bookkeeping (plan/progress/STATUS/DONE/markers + watch digest) to
      docs/streams/archive/<slug>/, then reaps: worktree removed, branch deleted, watch files
      cleaned. A merge is not complete until closeout has run.

  cbr.sh janitor
      READ-ONLY reconciliation backstop over closeout: lists worktrees whose branch code is fully
      in main (REAPABLE), worktrees still carrying unmerged code (ACTIVE), orphan stream/*
      branches with no worktree, and stale .cbr-watch files. Deletes nothing — a human approves
      each reap. Run at merge gates and on request (no scheduler); a leak should live days, not months.

  cbr.sh closeout-pending [<repo-or-worktree>]
      WARN-ONLY: names every worktree whose BRANCH is fully merged into main — i.e. closeout was
      owed and never run — and prints the reap command for each. Skips (loudly, with the reason)
      any worktree carrying uncommitted files or with a live process rooted in it, and never the
      primary checkout. `doctor` runs this as its last step, outside checks_failed: a pending
      closeout is housekeeping, not a broken harness. Deletes nothing. Note the difference from
      `janitor`, which asks whether the branch's CODE reached main; this asks whether the BRANCH did.

  cbr.sh readback [<slug-or-worktree>]
      Reports whether a builder's progress.md carries the readback core law requires before it
      builds (mission, locked scope, OUT list, in its own words): readback=present | MISSING |
      no-progress-file. "Present" needs a heading whose SUBJECT is the readback (contains
      BEGINS with the word "readback", so a journal entry that merely mentions one does not
      count) plus at least three non-blank lines under it. A sub-heading does not END the
      readback, though only its non-blank body lines count; fenced code blocks are excluded. No
      readback STATE ever fails: all three exit 0, because presence is a fact, faithfulness is
      a judgment, and only the dispatcher reading it against the plan can decide that. (An
      unresolvable slug or path is a caller error, not a state, and still exits non-zero — a
      typo must not read as a pass.) `status` prints the same fact in every SUMMARY where the
      worktree exists, including the session-absent ones.

The model/effort defaults track SKILL.md "The model dial"; pass --model/--effort to override.
The prose in SKILL.md is the policy and the why — this script is just the hands.
USAGE
    ;;
  *) die "unknown command '${1}' — run 'cbr.sh help'" ;;
esac
