#!/usr/bin/env python3
"""Static structural invariants whose mutations must fail before live smoke."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path


def require(condition: bool, message: str) -> None:
    if not condition:
        print(f"STATIC-FAIL {message}", file=sys.stderr)
        raise SystemExit(1)


root = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parents[1])
hooks = json.loads((root / "templates/codex-hooks.json").read_text())["hooks"]
project = json.loads((root / "templates/cbr-codex.json").read_text())

pre = hooks.get("PreToolUse", [])
pre_blob = json.dumps(pre)
require("--agent codex" in pre_blob, "Probity host is not Codex")
require("--agent claude-code" not in pre_blob, "Probity includes a Claude host path")
require("@nizos/probity@1.10.0" in pre_blob, "Probity fallback is not pinned")
require("apply_patch" in pre_blob and "Bash" in pre_blob, "Probity matcher misses shell or patch")
require("no-interactive-question.sh" in pre_blob, "question guard missing")
other_question_tool = "Ask" + "UserQuestion"
require(other_question_tool not in pre_blob, "question guard includes another provider's tool")
adapter_guarded_paths = [
    path for path in project.get("guardedPaths", []) if path.startswith("adapters/")
]
require(len(adapter_guarded_paths) == 1, "expected exactly one adapter TDD guarded path")

probity = (root / "templates/probity.config.ts").read_text()
require("forbidContentPattern({" in probity, "vendor-neutral content guard missing")
require("'packages/**'" in probity, "vendor-neutral content guard is not scoped to packages")
probe = (root / "templates/probe-prompt.md").read_text()
require("PROVE-ADAPTER" in probe, "live probe does not exercise adapter TDD")
probe_adapter_paths = re.findall(r"`(adapters/[^`]+)`", probe)
require(len(probe_adapter_paths) == 1, "live probe must declare exactly one adapter path")
require(
    probe_adapter_paths[0] == adapter_guarded_paths[0],
    "live adapter probe path does not equal the configured guarded path",
)

post_blob = json.dumps(hooks.get("PostToolUse", []))
require("roborev-gate.sh" in post_blob, "RoboRev PostToolUse feedback missing")
stop_blob = json.dumps(hooks.get("Stop", []))
require("builder-stop-check.sh" in stop_blob, "Stop continuity missing")

session_blob = json.dumps(hooks.get("SessionStart", []))
require("roborev-session-sweep.sh" in session_blob, "SessionStart review sweep missing")
require("^compact$" not in session_blob, "dead SessionStart compact matcher returned")
resume = [
    hook
    for entry in hooks.get("SessionStart", [])
    if entry.get("matcher") == "^resume$"
    for hook in entry.get("hooks", [])
]
require(len(resume) == 1 and "post-compact-reground.sh" in resume[0].get("command", ""), "pending re-ground resume fallback missing")
require(resume[0].get("additionalContextLimit") == 0, "resume fallback truncates re-ground context")
post_compact = [
    hook
    for entry in hooks.get("PostCompact", [])
    for hook in entry.get("hooks", [])
]
require(len(post_compact) == 1, "compaction marker must be exactly one PostCompact hook")
require("mark-post-compact.sh" in post_compact[0].get("command", ""), "PostCompact marker hook missing")
require(post_compact[0].get("additionalContextLimit") is None, "PostCompact falsely claims it can inject context")
prompt_submit = [
    hook
    for entry in hooks.get("UserPromptSubmit", [])
    for hook in entry.get("hooks", [])
]
require(len(prompt_submit) == 1 and "post-compact-reground.sh" in prompt_submit[0].get("command", ""), "context-bearing prompt re-ground hook missing")
require(prompt_submit[0].get("additionalContextLimit") == 0, "prompt re-ground truncates additionalContext")

clean = (root / "templates/roborev-clean-gate.sh").read_text()
require(clean.count('--branch "$branch"') >= 2, "RoboRev lists are not branch scoped")
require('roborev show "$head_sha"' in clean, "missing per-SHA crash/no-row backstop")
require("if value is None:" in clean and "return []" in clean, "RoboRev null is not treated as empty")

rail = (root / "scripts/cbr-codex.sh").read_text()
require("codex roborev pre-commit gitleaks python3 git node jq" in rail, "doctor does not require jq for compaction recovery")
require("--sandbox workspace-write" in rail, "builder sandbox is not workspace-write")
require("approval_policy=\"never\"" in rail, "non-interactive approval policy missing")
require("--ephemeral" not in rail, "persistent builder rail contains --ephemeral")
require("danger-full-access" not in rail, "builder rail contains danger-full-access")
require("provision PASS not recorded in this worktree" in rail and '"result":"PASS"' in rail, "launch can bypass provision proof")
require("same-phase resume limit exceeded" in rail, "crash-storm bound missing")

watch = (root / "scripts/captain-watch-codex.sh").read_text()
require('done0="$(digest "$wt/DONE.marker")"' in watch, "DONE baseline hash latch missing")
require('if [ "$done1" != "$done0" ]' in watch, "DONE change latch missing")
require("stale-heartbeat" in watch, "watchdog heartbeat check missing")

graph = (root / "scripts/cbr_graph.py").read_text()
require("dependency cycle" in graph, "DAG cycle check missing")
require("ownership collision is not serialized" in graph, "ownership collision check missing")
require("provision predates dependency merge" in graph, "late-unlock provision ordering missing")

reground = (root / "templates/hooks/post-compact-reground.sh").read_text()
marker = (root / "templates/hooks/mark-post-compact.sh").read_text()
require('cbr-codex-post-compact.$thread.pending' in marker, "PostCompact marker is not thread scoped")
require('cbr-codex-post-compact.$thread.pending' in reground, "re-ground does not consume the thread-scoped marker")
require('case "$thread" in ""|*[!A-Za-z0-9_-]*)' in marker, "PostCompact marker thread ID is not validated")
require('case "$thread" in ""|*[!A-Za-z0-9_-]*)' in reground, "re-ground thread ID is not validated")
require('UserPromptSubmit|SessionStart' in reground and 'hookEventName: $event' in reground, "re-ground output event does not match its context-bearing caller")
require('inject "DURABLE FINDINGS (' in reground and '"$plan_dir/findings.md"' in reground, "findings are not reinjected")
require('inject "SESSION PROGRESS (' in reground and '"$plan_dir/progress.md"' in reground, "progress is not reinjected")
require("reread progress.md" not in reground.lower(), "post-compact hook asks for orientation reads")
for core_path in (
    "$core/policy.md",
    "$core/strand.md",
    "$core/reviews.md",
    "$core/judgment.md",
    "$core/GLOSSARY.md",
    "$core/build-loop.md",
    "$core/modes/solo.md",
    "$core/modes/fleet.md",
):
    require(core_path in reground, f"role-aware re-ground path missing: {core_path}")
require('orchestrator)' in reground and '"$refs/fleet.md"' in reground, "orchestrator payload missing")
require('workstream)' in reground and '"$refs/build-loop.md"' in reground, "workstream payload missing")
require('[[ "$branch" =~ $builder_pattern ]]' in reground, "solo-vs-stream role selection missing")

dispatch = (root / "templates/dispatch-prompt.md").read_text()
for clause in (
    "$codex-controlled-build-run", "task_plan.md", "contracts", "outside this worktree",
    "prove-NO", "watched-fail TDD", "RoboRev", "checkpoint", "Never request UI input",
    "ASK-ORCH.md", "DONE.marker",
):
    require(clause in dispatch, f"dispatch prompt clause missing: {clause}")

print("STATIC-PASS Codex CBR structural invariants")
