#!/usr/bin/env python3
"""Deterministic CBR fleet graph, ownership, and dispatchability facts."""
from __future__ import annotations

import argparse
import json
import os
import signal
import subprocess
import sys
from pathlib import Path


def die(message: str) -> None:
    print(f"cbr-graph: {message}", file=sys.stderr)
    raise SystemExit(1)


def load(path: Path) -> tuple[dict, dict[str, dict]]:
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError) as exc:
        die(f"cannot read {path}: {exc}")
    rows = data.get("streams")
    if not isinstance(rows, list):
        die("streams must be a list")
    if not isinstance(data.get("integrationBranch"), str) or not data["integrationBranch"]:
        die("integrationBranch must be a non-empty string")
    by_slug: dict[str, dict] = {}
    for index, row in enumerate(rows):
        if not isinstance(row, dict):
            die(f"stream row {index} is not an object")
        missing = [k for k in ("slug", "branch", "worktree", "dependsOn", "filesOwned", "status", "findingsLogged") if k not in row]
        if missing:
            die(f"row {index} missing {', '.join(missing)}")
        slug = row["slug"]
        if not isinstance(slug, str) or not slug or slug in by_slug:
            die(f"invalid or duplicate slug {slug!r}")
        if not isinstance(row["dependsOn"], list) or not isinstance(row["filesOwned"], list):
            die(f"{slug}: dependsOn/filesOwned must be lists")
        if not isinstance(row["findingsLogged"], bool):
            die(f"{slug}: findingsLogged must be boolean")
        if row["status"] not in {"planned", "ready", "active", "blocked", "done", "merged", "parked"}:
            die(f"{slug}: invalid status {row['status']!r}")
        if not os.path.isabs(row["worktree"]):
            die(f"{slug}: worktree must be absolute")
        for owned in row["filesOwned"]:
            if not isinstance(owned, str) or not owned:
                die(f"{slug}: invalid ownership path")
            trimmed = owned[:-3] if owned.endswith("/**") else owned
            if any(marker in trimmed for marker in ("*", "?", "[")):
                die(f"{slug}: ownership globs may use wildcards only as a terminal /**: {owned}")
        by_slug[slug] = row
    return data, by_slug


def reaches(by_slug: dict[str, dict], start: str, target: str) -> bool:
    pending = list(by_slug[start]["dependsOn"])
    seen: set[str] = set()
    while pending:
        current = pending.pop()
        if current == target:
            return True
        if current in seen:
            continue
        seen.add(current)
        pending.extend(by_slug[current]["dependsOn"])
    return False


def ownership_overlap(left: str, right: str) -> bool:
    def stem(value: str) -> str:
        for marker in ("*", "?", "["):
            value = value.split(marker, 1)[0]
        return value.rstrip("/")
    a, b = stem(left), stem(right)
    return bool(a and b and (a == b or a.startswith(b + "/") or b.startswith(a + "/")))


def validate(path: Path, plan: Path | None = None) -> tuple[dict, dict[str, dict]]:
    data, rows = load(path)
    branches: set[str] = set()
    worktrees: set[str] = set()
    for slug, row in rows.items():
        if row["branch"] in branches:
            die(f"duplicate branch {row['branch']}")
        if row["worktree"] in worktrees:
            die(f"duplicate worktree {row['worktree']}")
        branches.add(row["branch"]); worktrees.add(row["worktree"])
        for dep in row["dependsOn"]:
            if dep not in rows:
                die(f"{slug}: unknown dependency {dep}")
        if row["status"] == "merged" and not isinstance(row.get("mergedAt"), int):
            die(f"{slug}: merged status requires integer mergedAt")

    visiting: set[str] = set(); visited: set[str] = set()
    def visit(slug: str) -> None:
        if slug in visiting: die(f"dependency cycle through {slug}")
        if slug in visited: return
        visiting.add(slug)
        for dep in rows[slug]["dependsOn"]: visit(dep)
        visiting.remove(slug); visited.add(slug)
    for slug in rows: visit(slug)

    for slug, row in rows.items():
        if row["status"] != "merged":
            continue
        for dep in row["dependsOn"]:
            if rows[dep]["status"] != "merged" or rows[dep]["mergedAt"] > row["mergedAt"]:
                die(f"{slug}: merge order contradicts dependency {dep}")

    slugs = list(rows)
    for i, left in enumerate(slugs):
        for right in slugs[i + 1:]:
            overlap = any(ownership_overlap(a, b) for a in rows[left]["filesOwned"] for b in rows[right]["filesOwned"])
            if overlap and not reaches(rows, left, right) and not reaches(rows, right, left):
                die(f"ownership collision is not serialized: {left} vs {right}")
    if plan:
        text = plan.read_text()
        for slug in rows:
            if slug not in text:
                die(f"fleet plan omits stream {slug}")
    print(f"FACT graph streams={len(rows)} acyclic=true ownership_serialized=true")
    return data, rows


def process_alive(path: Path) -> bool:
    try:
        pid = int(path.read_text().strip())
        os.kill(pid, 0)
        return True
    except (OSError, ValueError):
        return False


def dispatchable(
    path: Path,
    slug: str,
    repo: Path,
    plan: Path | None,
    expected_worktree: Path | None = None,
) -> None:
    _, rows = validate(path, plan)
    if slug not in rows: die(f"unknown stream {slug}")
    row = rows[slug]
    if row["status"] not in {"planned", "ready"}:
        die(f"{slug}: status {row['status']} is not launchable")
    for dep in row["dependsOn"]:
        if rows[dep]["status"] != "merged" or not rows[dep].get("mergedAt"):
            die(f"{slug}: dependency {dep} is not merged with a timestamp")
    wt = Path(row["worktree"]).resolve()
    if expected_worktree is not None and wt != expected_worktree.resolve():
        die(
            f"{slug}: fleet worktree {wt} does not match launch worktree "
            f"{expected_worktree.resolve()}"
        )
    provision_path = wt / ".cbr-codex" / "provision.json"
    try: provision = json.loads(provision_path.read_text())
    except (OSError, ValueError) as exc: die(f"{slug}: provision record unavailable: {exc}")
    if provision.get("result") != "PASS" or provision.get("branch") != row["branch"]:
        die(f"{slug}: provision did not pass for declared branch")
    latest_dep = max((int(rows[d]["mergedAt"]) for d in row["dependsOn"]), default=0)
    if int(provision.get("completed", 0)) < latest_dep:
        die(f"{slug}: provision predates dependency merge")
    actual = subprocess.check_output(["git", "-C", str(wt), "branch", "--show-current"], text=True).strip()
    if actual != row["branch"]:
        die(f"{slug}: worktree branch is {actual}, expected {row['branch']}")
    for name in ("task_plan.md", "findings.md", "progress.md"):
        if not (wt / name).is_file(): die(f"{slug}: missing {name}")
    plan_branch = ""
    for line in (wt / "task_plan.md").read_text().splitlines():
        if "**Branch:**" in line:
            plan_branch = line.split("**Branch:**", 1)[1].strip().split()[0].rstrip("·")
            break
    if plan_branch != row["branch"]:
        die(f"{slug}: task plan branch mismatch ({plan_branch or 'absent'})")
    pid_path = repo / ".cbr-codex" / "runs" / slug / "pid"
    if process_alive(pid_path): die(f"{slug}: a live registered writer already exists")
    print(f"FACT dispatchable slug={slug} provision_after_deps=true no_live_writer=true")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("check", "dispatchable"))
    parser.add_argument("fleet", type=Path)
    parser.add_argument("slug", nargs="?")
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    parser.add_argument("--plan", type=Path)
    parser.add_argument("--worktree", type=Path)
    args = parser.parse_args()
    if args.command == "check": validate(args.fleet, args.plan)
    else:
        if not args.slug: parser.error("dispatchable requires slug")
        if not args.worktree: parser.error("dispatchable requires --worktree")
        dispatchable(
            args.fleet,
            args.slug,
            args.repo.resolve(),
            args.plan,
            args.worktree,
        )


if __name__ == "__main__":
    main()
