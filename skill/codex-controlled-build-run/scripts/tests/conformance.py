#!/usr/bin/env python3
"""Prove the Codex leaf conforms to the shared CBR core and owns only Codex mechanics."""
from __future__ import annotations

import hashlib
import re
import subprocess
import sys
from pathlib import Path


HERE = Path(__file__).resolve()
LEAF = HERE.parents[2]
EMBEDDED_CORE = LEAF / "references" / "cbr-core"
CODEX_COVERAGE = LEAF / "references" / "CODEX-COVERAGE.md"


def fail(message: str) -> None:
    raise SystemExit(f"CONFORMANCE-FAIL {message}")


raw_args = sys.argv[1:]
STRICT_SOURCE_IDENTITY = "--canonical-source-repo" in raw_args
positional_args = [arg for arg in raw_args if arg != "--canonical-source-repo"]
unknown_flags = [arg for arg in positional_args if arg.startswith("-")]
if unknown_flags or len(positional_args) > 1:
    fail("usage: conformance.py [--canonical-source-repo] [canonical-core-path]")


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
if not EMBEDDED_CORE.is_dir():
    fail("embedded core snapshot is missing from references/cbr-core")

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

core_text = "\n".join(
    (EMBEDDED_CORE / relative).read_text(encoding="utf-8") for relative in sorted(embedded_paths)
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

coverage = (EMBEDDED_CORE / "COVERAGE.md").read_text(encoding="utf-8")
if re.search(r"^\|[^|]+\|\s*pending-P\d+\s*\|", coverage, re.MULTILINE):
    fail("coverage map still contains a pending disposition")
for mapped in re.findall(r"core:([A-Za-z0-9_./-]+\.md)", coverage):
    if not (EMBEDDED_CORE / mapped).is_file():
        fail(f"coverage maps to a missing core file: {mapped}")

source_skill = canonical_source_skill()
if source_skill is not None:
    coverage_law = coverage.split("Acceptance sources", 1)[0]
    covered: set[int] = set()
    for start, end in re.findall(r"\((\d+)[–-](\d+)\)", coverage_law):
        covered.update(range(int(start), int(end) + 1))
    orphaned = [
        number
        for number, line in enumerate(source_skill.read_text(encoding="utf-8").splitlines(), 1)
        if line.strip() and number not in covered
    ]
    if orphaned:
        fail(f"coverage map leaves nonblank source lines unaccounted: {orphaned[:12]}")

if not CODEX_COVERAGE.is_file():
    fail("Codex provider-mechanical coverage map is missing")
codex_coverage = CODEX_COVERAGE.read_text(encoding="utf-8")
commit_match = re.search(r"^- commit: `([0-9a-f]{40})`$", codex_coverage, re.MULTILINE)
path_match = re.search(r"^- path: `([^`]+)`$", codex_coverage, re.MULTILINE)
lines_match = re.search(r"^- lines: `(\d+)`$", codex_coverage, re.MULTILINE)
sha_match = re.search(r"^- sha256: `([0-9a-f]{64})`$", codex_coverage, re.MULTILINE)
if not all((commit_match, path_match, lines_match, sha_match)):
    fail("Codex coverage source identity is incomplete")
source_line_count = int(lines_match.group(1))
section_map = codex_coverage.split("## Complete section disposition", 1)[1].split(
    "## Provider-mechanical destination inventory", 1
)[0]
if re.search(r"^\|[^|]+\|[^|]*pending", section_map, re.MULTILINE | re.IGNORECASE):
    fail("Codex coverage map contains a pending disposition")
ranges = [(int(start), int(end)) for start, end in re.findall(r"^\| (\d+)[–-](\d+) \|", section_map, re.MULTILINE)]
counts = {number: 0 for number in range(1, source_line_count + 1)}
for start, end in ranges:
    for number in range(start, end + 1):
        if number in counts:
            counts[number] += 1
bad_tiling = [number for number, count in counts.items() if count != 1]
if bad_tiling:
    fail(f"Codex source coverage does not tile every line exactly once: {bad_tiling[:12]}")
for kind, destination in re.findall(r"(core|leaf):([A-Za-z0-9_./-]+)", section_map):
    target = (EMBEDDED_CORE if kind == "core" else LEAF) / destination
    if not target.is_file():
        fail(f"Codex section coverage maps to a missing destination: {kind}:{destination}")

witness_rows = re.findall(
    r"^\| (C\d+) \|.*\| leaf:([A-Za-z0-9_./-]+) \| `([^`]+)` \|$",
    codex_coverage,
    re.MULTILINE,
)
expected_witness_ids = {f"C{number:02d}" for number in range(1, 24)}
actual_witness_ids = {row[0] for row in witness_rows}
if actual_witness_ids != expected_witness_ids:
    fail(
        "Codex provider-mechanical inventory is incomplete: "
        f"missing={sorted(expected_witness_ids - actual_witness_ids)} "
        f"extra={sorted(actual_witness_ids - expected_witness_ids)}"
    )
for witness_id, destination, witness in witness_rows:
    target = LEAF / destination
    if not target.is_file():
        fail(f"Codex inventory {witness_id} maps to a missing leaf file: {destination}")
    if witness not in target.read_text(encoding="utf-8"):
        fail(f"Codex inventory {witness_id} lost its required witness in {destination}: {witness}")

# Repository history is deliberately opt-in: a portable target can reproduce
# every path and marker from the source repository without carrying its Git
# objects. The cockpit's own gate passes --canonical-source-repo explicitly.
if STRICT_SOURCE_IDENTITY:
    source_repo: Path | None = None
    for ancestor in HERE.parents:
        if (ancestor / ".git").exists() and LEAF.resolve() == (
            ancestor / "skills" / "codex-controlled-build-run"
        ).resolve():
            source_repo = ancestor
            break
    if source_repo is None:
        fail("canonical source mode requires the leaf at <repo>/skills/codex-controlled-build-run")
    source_spec = f"{commit_match.group(1)}:{path_match.group(1)}"
    shown = subprocess.run(
        ["git", "-C", str(source_repo), "show", source_spec],
        capture_output=True,
        check=False,
    )
    if shown.returncode != 0:
        fail(f"declared pre-conversion Codex source cannot be read: {source_spec}")
    if len(shown.stdout.decode("utf-8").splitlines()) != source_line_count:
        fail("declared pre-conversion Codex source line count is wrong")
    if hashlib.sha256(shown.stdout).hexdigest() != sha_match.group(1):
        fail("declared pre-conversion Codex source hash is wrong")

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
for relative in (
    "references/cbr-core/policy.md",
    "references/cbr-core/strand.md",
    "references/cbr-core/build-loop.md",
    "references/cbr-core/reviews.md",
    "references/cbr-core/judgment.md",
    "references/cbr-core/GLOSSARY.md",
    "references/cbr-core/modes/solo.md",
    "references/cbr-core/modes/fleet.md",
    "references/cbr-core/modes/captain.md",
    "references/cbr-core/acceptance/checklist.md",
    "references/acceptance.md",
    "references/CODEX-COVERAGE.md",
):
    if relative not in router:
        fail(f"router does not route to required component: {relative}")

core_leaf_rows = set(
    re.findall(
        r"\*\*([A-Z]\d+[a-z]?)\*\* \(leaf-row\)",
        (EMBEDDED_CORE / "acceptance" / "checklist.md").read_text(encoding="utf-8"),
    )
)
leaf_acceptance = (LEAF / "references" / "acceptance.md").read_text(encoding="utf-8")
leaf_rows = set(re.findall(r"^- \*\*([A-Z]\d+[a-z]?)\*\*", leaf_acceptance, re.MULTILINE))
if leaf_rows != core_leaf_rows:
    fail(
        "Codex leaf acceptance rows do not exactly satisfy core leaf-row set: "
        f"missing={sorted(core_leaf_rows - leaf_rows)} extra={sorted(leaf_rows - core_leaf_rows)}"
    )

print(
    "CONFORMANCE-PASS "
    f"core_files={len(source_paths)} coverage_source={'yes' if source_skill else 'portable'} "
    f"history={'canonical' if STRICT_SOURCE_IDENTITY else 'portable'} "
    f"codex_witnesses={len(witness_rows)} leaf_rows={len(leaf_rows)} "
    f"router_lines={len(router.splitlines())}"
)
