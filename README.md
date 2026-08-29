# controlled-build-run

A portable, self-contained harness for **controlled build runs**: drop this
package into any repository, point a coding agent at it, and get a
disciplined, plan-driven, gate-guarded build process — one that stays honest
through long and unattended runs because the discipline is enforced by
mechanisms, not memory.

This repository is the canonical source. Its identity is `MANIFEST.sha256` —
a content fingerprint of every file — plus `VERSION`; regenerate the manifest
with `./generate-manifest.sh` after any change, and check integrity of a copy
with `./verify-manifest.sh`. The package was extracted from a production
harness that was hardened in place across two host projects; the real configs
from that reference host ship under `examples/` as worked references.

## What it gives the target repo

A build that runs off a **written plan**, with **four automatic gates** and
**drift-proof hooks**:

| Gate | Fires | Blocks? |
|---|---|---|
| **Probity** (TDD + naming guard) | before every write/edit | yes — no prod code before a watched-fail test |
| **pre-commit** (format/lint/types/tests) | on `git commit` | yes — deterministic facts |
| **RoboRev** (per-commit LLM review) | after each commit | no — advises |
| **roborev-clean gate** | on `git commit` | yes — until every review is closed |

…plus a session-start FAIL sweep, a **post-compaction re-ground** hook (the
lifeline that re-injects the rules + plan after the agent's context is
compacted), and provider-native rails for isolated solo or fleet work.

The governing principle throughout: **deterministic facts may gate; fallible
judgment may only surface.** And every judgment that is genuinely a human's —
scope, vision, deploys, deleting ambiguous work — escalates to the
**operator** (defined in the glossary) rather than defaulting past them.

## How to use it

1. Copy this whole folder into the target repo (or clone it there).
2. Choose the setup for the coding agent you will use:
   - **Codex:** point Codex at
     **[`skill/codex-controlled-build-run/SETUP.md`](skill/codex-controlled-build-run/SETUP.md)**.
   - **Claude Code:** point Claude at **[`SETUP.md`](SETUP.md)**.
3. Do the setup's human trust/login steps on the new machine. Everything else
   the agent can do.
4. Run the provider's `doctor` and live Probity probe. The harness is not armed
   until both pass.

Do not send Codex through the root `SETUP.md`; that file is the Claude Code
installer. The Codex setup installs the Codex leaf, hooks, Probity judge,
pre-commit gate, RoboRev gate, and compaction recovery from one entry point.

## What's inside

```
controlled-build-run/
├─ README.md            ← you are here
├─ SETUP.md             ← Claude Code entry point
├─ MANIFEST.md          ← every file: source, verbatim vs template, where it installs
├─ generate-manifest.sh ← refresh MANIFEST.sha256 after edits
├─ verify-manifest.sh   ← integrity check of a copy against the manifest
│
├─ skill/claude-controlled-build-run/   ← the skill (SKILL.md, references/, scripts/cbr.sh) + PORTING.md
├─ skill/codex-controlled-build-run/    ← Codex entry point (SETUP.md) + skill + self-contained core
├─ sibling-skills/               ← planning-with-files + test-driven-development +
│                                  cyclomatic-complexity (required);
│                                  fusion, stage-review, closeout (optional)
├─ harness/                      ← the "arming": hook scripts (verbatim), the settings.json
│                                  hooks block to merge, and config templates to fill in
├─ examples/                     ← real configs from the reference host, as worked references (read-only)
└─ verify/                       ← the harness's own regression suite + smoke.sh static arming check
```

The provider-neutral process law lives in the leaf snapshots
(`skill/claude-controlled-build-run/references/core/` and
`skill/codex-controlled-build-run/references/cbr-core/`). The two snapshots
are byte-identical by contract — `verify/core-mirrors.test.sh` enforces it.

## Two things that are NOT portable (by design)

- Agent login and repository/hook trust are per-machine, per-repo human steps.
  Claude and Codex store these outside the package, so do them again on each
  machine.
- **The config templates encode one repo's shape.** `probity.config.ts`,
  `.pre-commit-config.yaml`, `.roborev.toml`, and the reground hook's doc list
  must be adapted to the target's languages, package layout, and binding docs.
  The package ships the engine **verbatim** and the configs as **templates**,
  with the reference host's originals in `examples/` as worked references. The
  setup agent fills the templates in Step 5.

## The honest boundary

The hook scripts, review-clean gate, provider rails, and planning/TDD law are
**project-agnostic**. The configs and re-ground document list are
**repo-specific**. The chosen provider setup wires the engine, adapts the
templates, and verifies that every gate actually bites. The rule throughout:
**merge, adapt, verify — never blind-overwrite.**
