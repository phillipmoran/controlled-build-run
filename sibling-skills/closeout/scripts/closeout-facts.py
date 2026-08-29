#!/usr/bin/env python3
"""Run this FIRST in a closeout. "Since last closeout" anchors on the most recent
closeout commit (subject starting "closeout"), falling back to the newest handoff's
creation commit, falling back to the merge-base with origin/main.

A bug here surfaces as a wrong-looking fact you can eyeball, never as corrupted state —
which is what makes it safe to run blind at the top of every closeout.

Usage: python3 closeout-facts.py [--skip-tests]
"""

from __future__ import annotations

import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


def run(cmd: list[str], cwd: Path | None = None) -> str:
    # Failures surface as obviously-wrong output the caller eyeballs, never as an
    # exception halting a script that runs blind at the top of every closeout.
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True).stdout.strip()


def main() -> int:
    skip_tests = "--skip-tests" in sys.argv

    root = Path(run(["git", "rev-parse", "--show-toplevel"]) or ".")
    now = datetime.now(timezone.utc)
    stamp = now.strftime("%Y-%m-%dT%H%MZ")

    print(f"=== CLOSEOUT FACTS  (generated {now.strftime('%Y-%m-%d %H:%M:%SZ')}) ===\n")

    head = run(["git", "log", "-1", "--format=%h %s"], root)
    branch = run(["git", "rev-parse", "--abbrev-ref", "HEAD"], root)
    ahead = run(["git", "rev-list", "--count", "origin/main..HEAD"], root)
    print(f"HEAD:    {head}")
    print(f"Branch:  {branch}")
    print(f"Ahead:   {ahead + ' commits ahead of origin/main' if ahead else 'origin/main not found'}")
    print(f"UTC now: {stamp}   (use for new filenames)\n")

    # Handoffs are conditional now, so the anchor prefers the last closeout commit.
    # When HEAD itself is a closeout commit (re-running after committing the closeout),
    # anchor on the one before it so the session still shows, not an empty range.
    matches = run(["git", "log", "-2", "--format=%h", "--grep=^closeout", "HEAD"], root).splitlines()
    head_sha = run(["git", "rev-parse", "--short", "HEAD"], root)
    commit = ""
    if matches:
        commit = matches[1] if matches[0] == head_sha and len(matches) > 1 else ("" if matches[0] == head_sha else matches[0])
    label = f"closeout commit {commit}" if commit else ""
    if not commit:
        # Lexical sort works because handoff names start with an ISO-8601 UTC timestamp.
        # Anchor on the commit that CREATED the handoff, not the last one to touch it:
        # a later session may amend a prior handoff, dragging a "last-touched" anchor
        # forward and undercounting. --diff-filter=A lists adds newest-first.
        handoffs = sorted((root / "docs/_handoffs").glob("*.md"))
        if handoffs:
            adds = run(["git", "log", "--diff-filter=A", "--format=%h", "--", str(handoffs[-1])], root).splitlines()
            commit = adds[0] if adds else ""
            label = f"handoff {handoffs[-1].name}" if commit else ""
    if not commit:
        commit = run(["git", "merge-base", "origin/main", "HEAD"], root)
        label = f"merge-base {commit}" if commit else ""
    if commit:
        n = run(["git", "rev-list", "--count", f"{commit}..HEAD"], root)
        print(f"--- Since last {label} ---")
        print(f"Range: {commit}..HEAD  ({n} commits)")
        log = run(["git", "log", "--oneline", f"{commit}..HEAD"], root)
        print(log if log else "(none — anchor is already at HEAD)")
    else:
        print("--- No anchor found (no closeout commit, handoff, or origin/main) ---")
    print()

    print("--- Suite ---")
    if skip_tests:
        print("(skipped: --skip-tests)")
    else:
        out = subprocess.run(["uv", "run", "pytest", "-q"], cwd=root, capture_output=True, text=True)
        lines = [ln for ln in out.stdout.splitlines() if ln.strip()]
        print(lines[-1] if lines else "(no pytest summary captured)")
    print()

    print("--- Sizes / ceilings ---")
    lt = root / "spiritual-explorations/memory/SOUL.md"
    if lt.exists():
        words = len(lt.read_text().split())
        flag = f"OVER by {words - 2000} — compress before adding" if words > 2000 else "ok"
        print(f"SOUL.md: {words} words / 2000 ceiling  [{flag}]")
    print()

    print("--- Bookkeeping ---")
    plan = root / "task_plan.md"
    if plan.exists():
        nums = [int(m) for m in re.findall(r"\*\*(\d+)\.", plan.read_text())]
        if nums:
            print(f"Highest decision #: {max(nums)}  ->  next likely: {max(nums) + 1} (verify in task_plan.md)")
    print()

    print("--- New filenames (fill the <slug>; handoff only if warranted) ---")
    print(f"Handoff:    docs/_handoffs/{stamp}-<slug>.md")
    print("\n=== END (read-only — nothing written, nothing committed) ===")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
