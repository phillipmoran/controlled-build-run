# Controlled-Build-Run (CBR)

Controlled-Build-Run (CBR) is a harness-agnostic control plane that governs
long-running coding agents through durable context, deterministic enforcement,
independent verification, and lifecycle gates.

Put simply: CBR keeps coding agents on the rails through long builds, days or
weeks if needed, without them screwing things up. It does the remembering,
checking, and reviewing mechanically, so nothing depends on the agent staying
disciplined on its own.

The point is that you can walk away. Hand off the work, go do something
else, let it run overnight or across days, and trust that the process
is enforced while you're away.

[![Watch: Controlled-Build-Run in practice](https://img.youtube.com/vi/G7ZofvCeaNE/maxresdefault.jpg)](https://youtu.be/G7ZofvCeaNE)

*Video: what CBR does and why, in practice.*

## When to use CBR

On extended agent development tasks, especially tasks where
* You expect compaction (e.g., tasks >45 minutes)
* You would like programmatically enforced guardrails for your agent
* You want a control-plane that does not vendor lock you to a provider

## Why this exists

Everyone writes rules for their agents: a CLAUDE.md, an AGENTS.md, a system
prompt full of "always write tests" and "never push to main." Long sessions
ignore them. Eventually, the agent's context gets compacted, the
rules become a summary of a summary, and by hour six the session is
building the wrong thing.

Written directions are advice. CBR is enforcement. Its gates are hooks in the
repo, so they fire whether or not the agent remembers they exist. And every
judgment that is genuinely a human's (scope, vision, deploys, deleting
ambiguous work) escalates to the operator rather than defaulting past them.

CBR is not a harness. Claude Code and Codex are harnesses. CBR rides inside
whichever one you use.

The process law is provider-neutral, and a thin adapter per harness supplies
the tool names, paths, and hook wiring.

Right now CBR has adapters for Claude Code and Codex. The design supports
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

CBR is vendored into your repo once, then armed per harness. The repo-level
gates (pre-commit wall, review config, Probity config) are shared; each
harness installs its own session hooks and runs its own proof. Pick yours:

### Claude Code

Plugin (easiest):

```
/plugin marketplace add phillipmoran/controlled-build-run
/plugin install controlled-build-run@phillipmoran
```

Then open the target repo and type `/cbr`. It will notice the repo is not
armed yet and offer `/cbr-setup`, which vendors this whole package into the
repo (both adapters included) and runs the Claude Code installer.

Manual: copy this whole folder into the repo and point Claude at
[`SETUP-claude-code.md`](SETUP-claude-code.md).

### Codex

Copy this whole folder into the repo and point Codex at
[`skill/codex-controlled-build-run/SETUP.md`](skill/codex-controlled-build-run/SETUP.md).

### Both

Run both installers in the same repo. The second merges into the shared
config the first wrote; each installs its own hooks.

Whichever you pick: do the setup's human trust/login steps on each machine
(everything else the agent can do), then run that harness's `doctor` and
live Probity probe. CBR is not armed for a harness until both pass there.

## How to use CBR

In Claude Code, five slash commands cover the whole lifecycle.
Plain words work too — "set up CBR in this project" or "do this per the CBR
control plane" reach the same skills.

- `/cbr` — the front door. Checks the repo's state and routes you: not
  armed → offers setup, no plan → plan, plan ready → build.
- `/cbr-setup` — arms a repo. Vendors the package, adapts the configs to
  your stack, and proves the gates actually fire.
- `/cbr-doctor` — read-only health check: what's armed, what's dead, what
  to do about it.
- `/cbr-plan` — compiles planning output you already have (a design
  conversation, a PRD, a Wayfinder session) into a gated plan file.
- `/cbr-build` — executes the current plan under the loop, solo or as an
  orchestrated fleet, whichever the plan calls for.
- On Codex, the same lifecycle runs through `scripts/cbr-codex.sh` verbs:
  `arm`, `doctor`, `provision`, `launch`, `closeout`.

### How I actually use it

The commands are the plumbing. A real session looks like this:

1. **Talk it through first.** Before any CBR command, I have a normal
   conversation with the agent about the feature: what it is, what it
   touches, what "done" means. This is the spec. CBR doesn't replace it.
2. **Hand it to CBR.** Once the shape is clear, I say something like "run
   this feature build per CBR." The agent compiles the conversation into a
   plan, gets my yes, and builds under the gates from there.
3. **Or fan it out.** For bigger work: "parallelize this per CBR, you act as
   orchestrator." The agent splits the plan into strands, spins up builder
   sessions in their own worktrees, and watches them from outside.

That's it. The discussion is where the thinking happens; CBR is what keeps
the build honest once the thinking is done.

## What's inside

```
controlled-build-run/
├─ README.md            ← you are here
├─ SETUP.md             ← start here: pick your harness
├─ SETUP-claude-code.md ← Claude Code installer
├─ MANIFEST.md          ← every file: source, verbatim vs template, where it installs
├─ generate-manifest.sh ← refresh MANIFEST.sha256 (pre-commit does this for you)
├─ verify-manifest.sh   ← integrity check of a copy against the manifest
│
├─ skill/claude-controlled-build-run/   ← Claude Code adapter (SKILL.md, references/, scripts/cbr.sh)
├─ skill/codex-controlled-build-run/    ← Codex adapter (SETUP.md, skill, companion script)
├─ sibling-skills/      ← planning-with-files + test-driven-development +
│                         cyclomatic-complexity (required);
│                         fusion, stage-review, closeout (optional)
├─ control-plane/       ← the arming: hook scripts (verbatim), the settings hooks
│                         block to merge, and config templates to fill in
├─ examples/            ← real configs from the reference host, plus a worked
│                         example of composing CBR with an external planner
├─ verify/              ← CBR's own regression suite + smoke.sh static arming check
│
├─ skills/              ← Claude Code plugin layer (/cbr commands); repo-native,
└─ .claude-plugin/        not vendored into target repos
```

The provider-neutral process law lives in the adapter snapshots
(`skill/claude-controlled-build-run/references/core/` and
`skill/codex-controlled-build-run/references/cbr-core/`). The two snapshots
are byte-identical by contract; `verify/core-mirrors.test.sh` enforces it.

This repository is the canonical source. Its identity is `MANIFEST.sha256`, a
content fingerprint of every shipped file, plus `VERSION`. Repo housekeeping
(this README, CI, the plugin wrapper) is listed in `MANIFEST.ignore` and is
not fingerprinted. `./generate-manifest.sh` refreshes the manifest (the
repo's pre-commit hook runs it for you); `./verify-manifest.sh` checks the
integrity of a copy. The package was extracted from a production
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

## Built on

CBR drives [Probity](https://github.com/nizos/probity) (write-time TDD
judge), [RoboRev](https://github.com/kenn-io/roborev) (AI code review),
[gitleaks](https://github.com/gitleaks/gitleaks), and
[pre-commit](https://github.com/pre-commit/pre-commit). It vendors skills
from [obra/superpowers](https://github.com/obra/superpowers) (TDD),
[saurabhkumar8112/cyclomatic-complexity-skill](https://github.com/saurabhkumar8112/cyclomatic-complexity-skill),
and [OthmanAdi/planning-with-files](https://github.com/OthmanAdi/planning-with-files),
and adapts [duolahypercho/fusion-fable](https://github.com/duolahypercho/fusion-fable).
Licenses and details: [`THIRD-PARTY.md`](THIRD-PARTY.md).

## The honest boundary

The hook scripts, gates, provider rails, and planning/TDD law are
project-agnostic. The configs and the re-ground document list are
repo-specific. The chosen provider setup wires the engine, adapts the
templates, and verifies that every gate actually bites. The rule throughout:
merge, adapt, verify, never blind-overwrite.
