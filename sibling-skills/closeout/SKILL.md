---
name: closeout
description: >-
  Gather the deterministic, repeatable facts a reference-host closeout opens with, in one
  read-only command — current HEAD, commits ahead of origin, the commit range since
  the last closeout, the suite pass/xfail count, the UTC timestamp for new filenames,
  and the SOUL.md word-ceiling check.
  Use it at the START of a closeout — when the operator says "close out" / "closeout", or any
  time you need the since-last-closeout commit list or the repo facts the closeout
  steps open with. It decides nothing and writes nothing; it just hands you the
  numbers so you stop hand-running the same git commands every session. The writing
  and the judgment stay yours.
---

# Closeout facts

The closeout ritual (in `AGENTS.md` `<closeout>`) opens several steps with the same
handful of repo facts: what HEAD is, how far ahead of origin we are, what landed since
the last closeout, whether the suite is green, what UTC stamp any new filenames take, and
whether `SOUL.md` is still under its word ceiling. Hand-gathering those means five or
six separate `git` / `pytest` / `date` calls every single session. This script collects
them in one shot.

```bash
python3 .claude/skills/closeout/scripts/closeout-facts.py
# add --skip-tests to skip the pytest run (e.g. when you already know it's green)
```

## The session-range anchor

"Commits since last closeout" anchors, in order of preference:

1. The most recent commit whose subject starts with `closeout` (when HEAD itself is one —
   you re-ran after committing the closeout — the one before it, so the session still shows).
2. Else the *creation* commit of the newest handoff in `docs/_handoffs/` (handoffs are
   conditional now, so this is a fallback for history that predates closeout commits).
3. Else the merge-base with `origin/main`.

For the anchor to keep working, the closeout's final commit subject must start with
`closeout` (e.g. `closeout: ...` or `closeout(scope): ...`).

## What each fact is for

| Fact it prints | Which closeout step uses it |
|---|---|
| HEAD + branch | Orientation; the header of a handoff if one is warranted |
| Commits ahead of `origin/main` | Push-state check |
| Range + oneline **since last closeout** | What this session is accountable for — review pass scope, and the handoff body if one is warranted |
| Suite pass/xfail count | Green-base sanity check |
| UTC timestamp | New filenames (handoff, archived plan) |
| `SOUL.md` word count vs 2000 | Step 5 — warns you before you add to an over-ceiling blob |
| Ready-to-use filenames | Paste target for the handoff — only if one is warranted (closeout step 2) |

## What it does NOT do — the line that keeps it safe

It **gathers facts; it does not make judgments.** It does not write the handoff or the
memory entries; it does not run the pre-closeout review; it does not touch the roadmap; it
commits nothing. Those are judgment calls and they stay with you — automating them is
exactly where this kind of helper goes wrong. The split is the same one the reference host's gate lives
by: *deterministic facts may be gathered and gated; fallible judgment may only be
surfaced.* This script is pure deterministic facts. A bug in it shows up as a
wrong-looking number you can eyeball against reality, never as corrupted state.

## Implementation notes (if you edit the script)

- **Read-only by construction.** It runs only `git log/rev-list/rev-parse/merge-base`,
  `pytest`, and file reads. Keep it that way — no writes, no commits. That is what makes
  it safe to run blindly at the top of every closeout.
- **The handoff fallback anchors on the handoff's *creation* commit, not its last-touched
  commit.** A later session sometimes amends an older handoff, which would drag a
  "last-touched" anchor forward and undercount. The script uses `git log --diff-filter=A`
  to find the commit that *added* the file.
- **Parallel sessions move HEAD.** the reference host sometimes has more than one session live (see
  `<work_discipline>`). HEAD and the ahead-count can change between two runs. That is the
  script reading reality correctly, not a bug — re-run it if a parallel merge lands while
  you are mid-closeout.
- **`python3`, not `python`.** This repo's PATH has `python3`; bare `python` is absent.
