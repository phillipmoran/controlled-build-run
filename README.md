# Controlled-Build-Run (CBR)

Controlled-Build-Run (CBR) is a harness-agnostic control plane that governs
long-running coding agents through durable context, deterministic enforcement,
independent verification, and lifecycle gates.

Put simply: CBR keeps coding agents on the rails through long builds, days or
weeks if needed, without them screwing things up. It does the remembering,
checking, and reviewing mechanically, so nothing depends on the agent staying
disciplined on its own.

## Why this exists

Everyone writes rules for their agents: a CLAUDE.md, an AGENTS.md, a system
prompt full of "always write tests" and "never push to main." Long sessions
ignore them. Not out of defiance: the agent's context gets compacted, the
rules become a summary of a summary, and by hour six the session is
confidently building the wrong thing with no tests.

Written directions are advice. CBR is enforcement. Its gates are hooks in the
repo, so they fire whether or not the agent remembers they exist. One rule
decides what may block: deterministic facts gate, fallible judgment only
advises. A type error blocks a commit. An LLM reviewer's opinion never does,
until the merge boundary, where its findings have to be answered. And every
judgment that is genuinely a human's (scope, vision, deploys, deleting
ambiguous work) escalates to the operator rather than defaulting past them.

CBR is not a harness. Claude Code and Codex are harnesses. CBR rides inside
whichever one you use: the process law is provider-neutral, and a thin
adapter per harness supplies the tool names, paths, and hook wiring.

Right now those two adapters are the ones that exist. The design supports
more: if you want CBR on another harness, open an issue and tell me which
one, or write the adapter yourself and PR it. An adapter is a few dozen small
files (the Claude Code one is about 30: hook scripts, config templates, one
companion script, and the skill text). The core law is shared verbatim and
never changes per harness, and the existing two adapters are working examples
of exactly what one has to supply.

## The flow (CBR handles this for you)

1. A plan is written as a durable artifact. Keep your own planning
   methodology if you have one. CBR just needs the plan in a file it can
   re-inject, because that file is the agent's memory when its context gets
   wiped.
2. The plan is reviewed before the build starts. A bad plan executed
   faithfully by a frontier model is the most expensive failure available, so
   the plan gets checked first: scope locked, steps test-drivable,
   verification commands present.
3. The build gets its own isolated workspace. CBR provisions a git worktree
   on a fresh branch and roots the agent session inside it (we call the
   bundle a strand: one branch, one plan, one folder, one session). Work
   can't collide with other builds, and everything stays revertable as a
   unit. One design rule behind this: builder agents are always full sessions
   rooted in their own worktree, never in-harness subagents, because
   subagents don't reliably get the full hook suite, and an unguarded writer
   defeats the whole point. This is also part of what makes CBR portable: it
   never depends on any harness's subagent machinery to write code.
4. TDD is enforced at write time. An agent judge (Probity) blocks production
   code until a real failing test has been watched to fail for the right
   reason. It also catches tests written to game the gate.
5. Deterministic checks run on every commit: format, lint, types, tests, and
   optionally a complexity ceiling so the tree doesn't fill up with slop.
6. An AI reviewer reads each commit and sends advisory findings to your
   agent. Advisory means advisory: nothing holds up the next commit.
7. At the PR boundary the homework comes due. A reviewer reads the full
   branch diff, and every finding must be fixed or declined with a written
   reason. Open commit reviews get closed here too. Fix rounds are capped, so
   a reviewer that invents problems can't hold the branch hostage; past the
   cap, a human ruling gets recorded.
8. A merge gate refuses a bad merge: no merge while the branch has open
   blocking findings, no completed review at its tip, or an over-cap round
   count with no ruling on file.
9. When the agent's context gets compacted (the most dangerous moment of a
   long run), a hook re-injects the plan, the house rules, and pointers to
   the process law. The build survives its own memory loss.
10. For bigger work there is a built-in orchestration layer: you talk to one
    orchestrator, and it parallelizes the work across a fleet of builder
    agents, each in its own strand, watched from outside.

One command, `doctor`, verifies all of it is armed in your repo. Reading docs
arms nothing; the check proves it.

## Getting started

1. Copy this whole folder into the target repo (or clone it there).
2. Choose the setup for the coding agent you will use:
   - **Claude Code:** point Claude at [`SETUP.md`](SETUP.md).
   - **Codex:** point Codex at
     [`skill/codex-controlled-build-run/SETUP.md`](skill/codex-controlled-build-run/SETUP.md).
3. Do the setup's human trust/login steps on the new machine. Everything else
   the agent can do.
4. Run the provider's `doctor` and the live Probity probe. CBR is not armed
   until both pass.

Do not send Codex through the root `SETUP.md`; that file is the Claude Code
installer. Each setup installs its adapter, hooks, Probity judge, commit
gates, review wiring, and compaction recovery from one entry point.

## What's inside

```
controlled-build-run/
├─ README.md            ← you are here
├─ SETUP.md             ← Claude Code entry point
├─ MANIFEST.md          ← every file: source, verbatim vs template, where it installs
├─ generate-manifest.sh ← refresh MANIFEST.sha256 after edits
├─ verify-manifest.sh   ← integrity check of a copy against the manifest
│
├─ skill/claude-controlled-build-run/   ← Claude Code adapter (SKILL.md, references/, scripts/cbr.sh)
├─ skill/codex-controlled-build-run/    ← Codex adapter (SETUP.md, skill, companion script)
├─ sibling-skills/      ← planning-with-files + test-driven-development +
│                         cyclomatic-complexity (required);
│                         fusion, stage-review, closeout (optional)
├─ harness/             ← the arming: hook scripts (verbatim), the settings hooks
│                         block to merge, and config templates to fill in
├─ examples/            ← real configs from the reference host, as worked references
└─ verify/              ← CBR's own regression suite + smoke.sh static arming check
```

The provider-neutral process law lives in the adapter snapshots
(`skill/claude-controlled-build-run/references/core/` and
`skill/codex-controlled-build-run/references/cbr-core/`). The two snapshots
are byte-identical by contract; `verify/core-mirrors.test.sh` enforces it.

This repository is the canonical source. Its identity is `MANIFEST.sha256`, a
content fingerprint of every file, plus `VERSION`. Regenerate the manifest
with `./generate-manifest.sh` after any change, and check the integrity of a
copy with `./verify-manifest.sh`. The package was extracted from a production
deployment hardened in place across two host projects; the real configs from
that reference host ship under `examples/` as worked references.

## Two things that are NOT portable (by design)

- Agent login and repository/hook trust are per-machine, per-repo human
  steps. Claude and Codex store these outside the package, so do them again
  on each machine.
- The config templates encode one repo's shape. `probity.config.ts`,
  `.pre-commit-config.yaml`, `.roborev.toml`, and the re-ground hook's doc
  list must be adapted to the target's languages, package layout, and binding
  docs. The package ships the engine verbatim and the configs as templates,
  with the reference host's originals in `examples/` as worked references.
  The setup agent fills the templates in during setup.

## The honest boundary

The hook scripts, gates, provider rails, and planning/TDD law are
project-agnostic. The configs and the re-ground document list are
repo-specific. The chosen provider setup wires the engine, adapts the
templates, and verifies that every gate actually bites. The rule throughout:
merge, adapt, verify, never blind-overwrite.
