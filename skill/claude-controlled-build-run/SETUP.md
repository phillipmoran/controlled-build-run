# SETUP — what a CBR-armed repo has, and why

Plain words. A repo is "armed" for controlled build runs when seven pieces are
in place. `scripts/cbr.sh arm <repo>` installs all seven and then proves they
bite; `scripts/cbr.sh doctor` health-checks them any time after (run it before
every overnight build — it is cheap). Arming is a CBR-DISCIPLINE concern only:
the recorder/cockpit observability side stays ZERO-TOUCH — never add a setup
requirement there just to make watching easier.

## The seven pieces

1. **The skill folder** (`skills/claude-controlled-build-run/`). The playbook
   itself: SKILL.md is the provider ROUTER; the process law lives in
   `references/core/` (a hash-gated byte-copy of `skills/cbr-core/`) and the
   Claude mechanics in `references/claude.md`; `scripts/cbr.sh` and
   `scripts/captain-watch.sh` are the hands. It lives IN the repo so the
   post-compaction hook can re-inject it — an agent that gets compacted
   mid-build reads the same rules it booted with, not a fuzzy summary.

2. **Probity — the write-time TDD gate.** A PreToolUse hook (in
   `.claude/settings.json`) that judges every Write/Edit/Bash against
   `probity.config.ts`: untested production logic gets BLOCKED at the moment
   of writing, not discovered at review. It is an LLM judge, not a mechanism —
   that is why arming ends with a live probe (see below) and why every exempt
   zone must name its substitute proof.
   **Cost note (2026-07-03):** the hook prefers the LOCAL install
   (`node_modules/.bin/probity`, via the root devDependency `@nizos/probity`)
   and only falls back to `npx --yes` when node_modules is absent (fresh
   clone, pre-install). The old always-npx form paid an npm resolution + cold
   node process on EVERY edit — with several builders running that was
   measurable CPU for zero extra safety. On a new machine nothing to
   configure: `pnpm install` makes the fast path live; the npx fallback keeps
   the guard armed before that. The version is pinned in TWO places that must
   be bumped together: `package.json` (`@nizos/probity` devDependency) and the
   hook's npx fallback in `.claude/settings.json` (review 268).

3. **RoboRev, advisory per commit.** Every commit gets an automatic
   AI review (`.roborev.toml` sets the agent/model and the repo's review
   guidelines). Per-commit reviews are ADVISORY (2026-08-31 cadence move):
   nothing blocks the next commit — the blocking check is the merge-path
   review gate, which refuses a merge while blocking findings are open.
   Known upstream sharp edges live in `references/upstream-issues.md`.

4. **The pre-commit test gate.** Typecheck + tests + format + secrets scan run
   on every commit (`.pre-commit-config.yaml`, installed with
   `pre-commit install`). Facts block; opinions advise. This is what makes
   "commit small, commit often" safe — the law is frequent commits BECAUSE
   every one of them passes the same wall.

5. **Re-injection docs.** `AGENTS.md` / `CLAUDE.md` route an agent to the
   repo's real rules, and the `post-compact-reground` SessionStart hook
   re-injects, after every context compaction: the binding docs, the router
   SKILL.md, the role-matched `references/core/` law files,
   `references/claude.md`, the TDD skill, and the plan trio (spec §6). Without this, a long build drifts the moment its
   context is summarized. Alongside it, `.claude/settings.json` (root AND the
   stream template) sets `"autoCompactWindow": 350000` — compact as late as
   the model allows so the dangerous moment happens less often (clamped
   automatically on smaller-window models; operator-set).

6. **The CBR conventions.** `task_plan.md` (the plan the re-ground hook
   re-injects, with the exempt-zone declaration and phase checkboxes),
   `STATUS.md` (build/phase/state/blocked-on — what the orchestrator and cockpit
   watch), `NEEDS-OPERATOR.md` (human-only decisions, parked not blocking),
   `docs/streams/` (where finished stream records retire), the stream/* push
   firewall, and `.cbr-watch/` (gitignored watcher state). The record
   skeletons are under `templates/` (`task_plan.skeleton.md`,
   `status.skeleton.md`, `needs-operator.skeleton.md`); the push firewall is
   written by `cbr.sh arm`, and `.cbr-watch/` is created by the watcher.
   Each skeleton names the facts it OWNS and links to the file that owns the
   rest — one fact, one record file (`references/core/build-loop.md`), which
   the host enforces at commit time rather than by asking a reviewer to
   notice.

7. **The control-plane guard.** Everything above is a file in the worktree,
   and a builder runs with permissions skipped, so without this piece the
   whole battery is one shell call from `exit 0`. A PreToolUse hook
   (`.claude/hooks/control-plane-guard.sh`) denies an agent's edits to the
   session hooks and their wiring, `.git/`, and the gate scripts, and the
   git bypass idioms (`--no-verify`, `core.hooksPath`, `merge.ff`) — the
   gate configs stay editable, since setup fills them after arm and every
   change to them lands in the reviewed diff. The
   operator unlocks a maintenance session with `CBR_CONTROL_PLANE_UNLOCK=1`
   in the launching environment. It is a bar against the casual disarm, not
   a vault (spec §9): the honest claim is "rules the agent cannot forget."
   Arm also sets `merge.ff=false` — a fast-forward merge fires no commit
   hook, so without it a fresh branch merged into an unmoved integration
   branch skips the review wall entirely.

## Guarded ≠ operable

Wiring all seven pieces proves nothing until a gate actually BLOCKS something.
`cbr.sh arm` therefore ends by dispatching the operability probe
(`templates/probe-prompt.md`, a tiny `claude --bg` session): it attempts an
untested production write and must see it DENIED (prove-NO), then a harmless
scratch write that must SUCCEED (prove-YES). Never trust an armed repo for an
overnight build before its probe has passed — and re-run `cbr.sh doctor`
before each build to catch the silent killers (an expired OAuth token breaks
Probity and RoboRev at once; `doctor`'s agent round-trip catches it).
