#!/usr/bin/env python3
"""Prove the Codex leaf conforms to the shared CBR core and owns only Codex mechanics."""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


HERE = Path(__file__).resolve()
LEAF = HERE.parents[2]
EMBEDDED_CORE = LEAF / "references" / "cbr-core"


def fail(message: str) -> None:
    raise SystemExit(f"CONFORMANCE-FAIL {message}")


raw_args = sys.argv[1:]
positional_args = list(raw_args)
unknown_flags = [arg for arg in positional_args if arg.startswith("-")]
if unknown_flags or len(positional_args) > 1:
    fail("usage: conformance.py [canonical-core-path]")


def canonical_core() -> Path:
    if positional_args:
        return Path(positional_args[0]).resolve()
    for ancestor in HERE.parents:
        candidate = ancestor / "skills" / "cbr-core"
        if candidate.is_dir():
            return candidate
    return EMBEDDED_CORE


def canonical_source_skill() -> Path | None:
    for ancestor in HERE.parents:
        candidate = ancestor / "skills" / "controlled-build-run" / "SKILL.md"
        if candidate.is_file():
            return candidate
    return None


def markdown_paths(root: Path) -> set[Path]:
    return {path.relative_to(root) for path in root.rglob("*.md")}


def readable_leaf_text() -> str:
    chunks: list[str] = []
    for path in LEAF.rglob("*"):
        if not path.is_file() or EMBEDDED_CORE in path.parents or path == HERE:
            continue
        try:
            chunks.append(path.read_text(encoding="utf-8"))
        except UnicodeDecodeError:
            continue
    return "\n".join(chunks)


source_core = canonical_core()
if not source_core.is_dir():
    fail(f"canonical core is missing: {source_core}")
# The canonical repo carries no embedded snapshot (deleted 2026-08-31; kit
# export materializes it). When one exists — an installed kit leaf — it must
# be byte-exact against the canonical core; when it does not, the canonical
# core itself is the text under test.
if EMBEDDED_CORE.is_dir():
    source_paths = markdown_paths(source_core)
    embedded_paths = markdown_paths(EMBEDDED_CORE)
    if source_paths != embedded_paths:
        fail(
            "embedded core file set differs from canonical core: "
            f"missing={sorted(map(str, source_paths - embedded_paths))} "
            f"extra={sorted(map(str, embedded_paths - source_paths))}"
        )
    for relative in sorted(source_paths):
        if (source_core / relative).read_bytes() != (EMBEDDED_CORE / relative).read_bytes():
            fail(f"embedded core drifted from canonical: {relative}")
    core_dir = EMBEDDED_CORE
else:
    source_paths = markdown_paths(source_core)
    core_dir = source_core

core_text = "\n".join(
    (core_dir / relative).read_text(encoding="utf-8") for relative in sorted(markdown_paths(core_dir))
)
core_primitives = (
    ".claude/",
    "claude --bg",
    "claude agents",
    "claude logs",
    "AskUserQuestion",
    "EnterWorktree",
    "settings.local.json",
    "bgIsolation",
    "--dangerously-skip-permissions",
    "autoCompactWindow",
    "/fusion-",
    ".codex/",
    "codex exec",
    "apply_patch",
    "approval_policy",
    "model_auto_compact_token_limit",
    ".cbr-codex",
)
for primitive in core_primitives:
    if primitive in core_text:
        fail(f"provider primitive survived in embedded core: {primitive}")

required_laws = (
    "None of it depends on you",
    "deterministic facts may gate; fallible judgment may only surface",
    "Compaction is the single most dangerous moment",
    "one branch ↔ one plan ↔ one folder ↔ one session",
    "small, often, and that is the LAW",
    "it produced no review at all",
    "real, independent session ROOT",
    "Files carry the run; no context window is load-bearing",
    "silence is the failure mode",
    "watchdog must be independent of the watched",
)
flat_core = re.sub(r"\s+", " ", core_text).replace("*", "").replace("`", "")
for law in required_laws:
    if law not in flat_core:
        fail(f"shared core lost source-strength law: {law}")

leaf_text = readable_leaf_text()
other_leaf_primitives = (
    ".claude/",
    "claude --bg",
    "claude agents",
    "claude logs",
    "AskUserQuestion",
    "EnterWorktree",
    "settings.local.json",
    "bgIsolation",
    "--dangerously-skip-permissions",
    "autoCompactWindow",
    "/fusion-",
)
for primitive in other_leaf_primitives:
    if primitive in leaf_text:
        fail(f"other-provider primitive survived in Codex leaf: {primitive}")

for primitive in (
    ".codex/",
    "codex exec",
    "apply_patch",
    'approval_policy="never"',
    "model_auto_compact_token_limit",
    ".cbr-codex",
):
    if primitive not in leaf_text:
        fail(f"Codex leaf does not name its own mechanism: {primitive}")

probity_template = (LEAF / "templates" / "probity.config.ts").read_text(encoding="utf-8")
probity_integration = (LEAF / "templates" / "probity-integration.mjs").read_text(encoding="utf-8")
for witness in ("project_root_markers: []", "workingDirectory: tmpdir()"):
    if witness not in probity_integration:
        fail(f"nested Probity judge can inherit project hooks: missing {witness}")
probity_parser = (LEAF / "templates" / "probity-verdict-parser.mjs").read_text(encoding="utf-8")
if "if (start === 0) break" not in probity_parser:
    fail("Probity verdict parser can loop forever when JSON starts at offset zero")
if "content: contentForVendorPolicy(action.content)" not in probity_integration:
    fail("content policy can mistake an absolute apply_patch header for file content")
policy_test = subprocess.run(
    ["node", "--test", str(LEAF / "scripts" / "tests" / "probity-content-policy.test.mjs")],
    capture_output=True,
    text=True,
)
if policy_test.returncode != 0:
    fail(f"Probity content policy behavioral test failed:\n{policy_test.stdout}{policy_test.stderr}")
parser_test = subprocess.run(
    ["node", "--test", str(LEAF / "scripts" / "tests" / "probity-verdict-parser.test.mjs")],
    capture_output=True,
    text=True,
)
if parser_test.returncode != 0:
    fail(f"Probity verdict parser behavioral test failed:\n{parser_test.stdout}{parser_test.stderr}")
integration_test = subprocess.run(
    ["node", "--test", str(LEAF / "scripts" / "tests" / "probity-integration.test.mjs")],
    capture_output=True,
    text=True,
)
if integration_test.returncode != 0:
    fail(f"Probity active integration behavioral test failed:\n{integration_test.stdout}{integration_test.stderr}")
doctor_script = (LEAF / "scripts" / "cbr-codex.sh").read_text(encoding="utf-8")
for witness in (
    '"$root/probity-content-policy.mjs"',
    '"$root/probity-content-policy.d.mts"',
    '"$root/probity-verdict-parser.mjs"',
    '"$root/probity-verdict-parser.d.mts"',
    '"$root/probity-integration.mjs"',
    '"$root/probity-integration.d.mts"',
    'isIntegratedProbityConfig(config)',
):
    if witness not in doctor_script:
        fail(f"doctor does not verify complete Probity runtime: missing {witness}")
for witness in (
    'probity_config_behavior_check "$target"',
    'probity_config_behavior_check "$root"',
    'probity_runtime_helpers_check "$target"',
    'probity_runtime_helpers_check "$root"',
    'existing probity.config.ts needs a manual merge; not overwritten',
):
    if witness not in doctor_script:
        fail(f"stale Probity config can survive arm/doctor: missing {witness}")

router = (LEAF / "SKILL.md").read_text(encoding="utf-8")
if len(router.splitlines()) > 250:
    fail(f"SKILL.md is not a short router ({len(router.splitlines())} lines)")
for witness in ("`CBR_CORE`", "`skills/cbr-core/`", "`references/cbr-core/`"):
    if witness not in router:
        fail(f"router does not name its shared-core resolver: {witness}")
for relative in (
    "$CBR_CORE/policy.md",
    "$CBR_CORE/strand.md",
    "$CBR_CORE/build-loop.md",
    "$CBR_CORE/reviews.md",
    "$CBR_CORE/judgment.md",
    "$CBR_CORE/GLOSSARY.md",
    "$CBR_CORE/modes/solo.md",
    "$CBR_CORE/modes/fleet.md",
    "references/acceptance.md",
):
    if relative not in router:
        fail(f"router does not route to required component: {relative}")

print(
    "CONFORMANCE-PASS "
    f"core_files={len(source_paths)} "
       f"router_lines={len(router.splitlines())}"
)
