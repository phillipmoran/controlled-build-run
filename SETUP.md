# SETUP — arm the controlled-build-run control plane on this repo

**You are an agent. You have been pointed at this folder, which was dropped into a
target repository. Your job: install and arm the controlled-build-run control plane on
THIS repo, then verify it.** Follow the steps in order. Steps marked **[HUMAN]**
need a person — do them, or pause and ask for them; you cannot do them yourself.

> What you are installing: a plan-driven control plane with **four automatic
> gates** — **Probity** (TDD + naming guard, blocks untested writes), **pre-commit**
> (format/lint/types/tests, blocks the commit), and **RoboRev** (per-commit LLM
> review, ADVISORY since the 2026-08-31 cadence move — the blocking review
> check rides the merge path) — plus
> **drift-proof hooks** (session-start sweep + post-compaction re-ground) and an
> optional **`cbr.sh`** rail for dispatching parallel `claude --bg` builders. The
> skill prose in `skill/claude-controlled-build-run/SKILL.md` is the policy and the *why*;
> this file is the install procedure.

The golden rule for every step: **MERGE, ADAPT, VERIFY — never blind-overwrite.**
This control plane is powerful; clobbering an existing `.claude/settings.json`,
`.pre-commit-config.yaml`, or `.roborev.toml` is the main hazard. If a file
already exists, merge into it.

---

## Step 0 — Prerequisites

Check what's installed; install what's missing.

```bash
for c in claude roborev git jq node npx python3; do command -v "$c" >/dev/null && echo "ok  $c" || echo "MISSING $c"; done
command -v uv >/dev/null && echo "ok  uv (optional)" || echo "-- uv (optional, only if your repo is Python/uv)"
command -v gitleaks >/dev/null && echo "ok  gitleaks (optional)" || echo "-- gitleaks (optional secret scan)"
claude --version   # need a build with `--bg` + `claude agents` (reference host proven on 2.1.186) for fleet dispatch
roborev version
```

Install the missing ones (macOS/Homebrew shown; adapt for your OS):
- `roborev`: `brew install roborev` (or see the RoboRev project). Required.
- `jq`: `brew install jq`. Required — the hooks emit their JSON through it and **fail open without it** (the control plane silently degrades).
- `node`/`npx`: any recent Node (reference: node 24, npm 11). Required — Probity is fetched by `npx`.
- `uv`: `brew install uv`. Only if your repo uses Python via uv.
- `gitleaks`: `brew install gitleaks`. Only if you keep the gitleaks pre-commit hook.
- `pre-commit`: install directly (`pipx install pre-commit`) **or** rely on `uv run pre-commit` if you use uv. (the reference host runs it through uv; it is not on PATH there.)
- `mattpocock-skills` plugin: **optional, per machine** — interactive design
  tooling (`/grill-me` planning interviews, `/improve-codebase-architecture`
  module-depth scans at plan formation and acceptance). The control plane's law
  references these methods in its own words, so nothing breaks without the
  plugin; install it from the official plugin marketplace where you want the
  interactive versions.

**Hard floor:** if `claude --bg` is unsupported by the installed CLI, the parallel
*builder dispatch* (`cbr.sh`) won't work — the solo control plane still does. Don't
proceed to fleet dispatch on an older CLI.

## Tool notes (the gotchas — pointed at from the steps below)

Two external tools have sharp edges worth knowing once. The steps and the other kit
docs point **here** instead of repeating it, so there is one copy to keep current.

1. **RoboRev sends usage telemetry by default — disable it with `TELEMETRY_ENABLED=0`.**
   The `roborev` binary has the PostHog analytics SDK compiled in (a baked-in key; the
   **daemon** holds an open connection to `https://us.i.posthog.com`). The off-switch is
   an env var on the daemon — but the value **must be `0`**. Network-trace verified
   2026-06-26 (v0.57.1): `TELEMETRY_ENABLED=0` → zero PostHog connections; **`=false` is
   a TRAP** — anything other than `0` reads as still-on and keeps leaking. No config-file
   key exists. Reviews are unaffected.
   - Set `TELEMETRY_ENABLED=0` in the environment that launches the roborev **daemon**
     (the daemon is the sender, not the CLI), then restart it (`roborev daemon stop`,
     next call restarts it — or `TELEMETRY_ENABLED=0 roborev daemon start`).
   - Persist it however your OS starts the daemon — e.g. a macOS launchd agent running
     `roborev daemon run` with `TELEMETRY_ENABLED=0` in its env, or an `export` in the
     shell env the daemon inherits.
   - Verify: with it set, the daemon opens **no** connection to PostHog —
     `lsof -nP -iTCP -p <daemon-pid>` shows nothing to `us.i.posthog.com`'s addresses.
   - Last resort only (if a future build ignores the var): block PostHog for the
     `roborev` process with a **per-app** firewall — never a machine-wide `/etc/hosts`
     block, which also kills your own PostHog use.

   Step 6 installs RoboRev — do this there.

2. **The gates are Claude Code hooks, so they only bite on Claude Code.** Probity
   (`PreToolUse`) and the RoboRev wake (`PostToolUse`) fire because `.claude/settings.json`
   wires them into Claude Code's hook events, and Probity acts only on the files its
   `probity.config.ts` globs name (your code tree — not docs/config). Run this kit on a
   **different** agent harness (Codex, Copilot, etc.) and that agent harness may not expose the same hook mechanism
   at all — the gate can be **silently dead**. Don't assume it's armed: run the smoke test
   (Step 7) and the live prove-NO / prove-YES (Step 8) on your agent harness before trusting it.

## Step 1 — [HUMAN] Auth + repo trust (the only unavoidable human steps)

1. **[HUMAN]** Make sure the Claude Code login is fresh: run `/login` in an
   interactive Claude session. This one login powers **three** things — the `claude`
   CLI, RoboRev's reviewer (`agent = claude-code`), and Probity's judge. One expired
   token 401s all three at once. (Fix is `/login`, not `setup-token`.)
2. **[HUMAN]** Open this repo once in an interactive Claude session and accept the
   workspace-trust prompt ("Yes, I trust this folder"). Trust is keyed by repo (the
   shared `.git`). A `claude --bg` builder **stalls forever** on an unanswered trust
   prompt and cannot be rescued, so trust must be accepted BEFORE any `--bg` dispatch.
   Verify: `~/.claude.json` → `projects["<repo path>"].hasTrustDialogAccepted == true`.

## Step 2 — Learn this repo's shape (you do this)

Before editing any template you must know the target. Determine and note:
- Languages + package/source layout (what Probity should guard, what the gates run on).
- The real **format / lint / typecheck / test** commands.
- The repo's **binding docs** — its equivalents of the reference host's `CONSTITUTION.md` /
  `ENGINEERING.md` / `GLOSSARY.md` / `AGENTS.md` / `contracts/` — or note it has none.
- Its **closeout** ritual, if any.

Everything below keys off these.

## Step 3 — Install the skills

The controlled-build-run skill must land where Claude Code discovers skills in this
repo (`skills/` or `.claude/skills/` — match the repo's existing convention). Default
to project-local so the kit is self-contained.

```bash
KIT="$(pwd)/controlled-build-run-kit"   # adjust if the folder sits elsewhere
mkdir -p skills .claude/skills .claude/commands scripts .claude/hooks

# the skill itself + its references + the dispatch rail
cp -R "$KIT/skill/claude-controlled-build-run"            skills/
# required sibling skills
cp -R "$KIT/sibling-skills/test-driven-development" skills/
cp -R "$KIT/sibling-skills/planning-with-files"     .claude/skills/   # see caveat below
# optional sibling skills (install if you want them)
cp -R "$KIT/sibling-skills/cyclomatic-complexity"   skills/            # optional per-project complexity ceiling (operator-ratified 2026-08-30)
cp -R "$KIT/sibling-skills/fusion"                  .claude/skills/    # design-panel; needs `codex`/`gemini` CLIs
cp "$KIT/sibling-skills/fusion/commands/"*.md       .claude/commands/  # /fusion-gpt5.5, /fusion-opus4.8
cp -R "$KIT/sibling-skills/stage-review"            skills/            # optional, reference-host-shaped review cadence
cp -R "$KIT/sibling-skills/closeout"                .claude/skills/    # optional, reference-host-shaped closeout
```

- **`planning-with-files` caveat (important):** it ships its OWN hooks in its
  frontmatter (UserPromptSubmit/PreToolUse/PostToolUse/**Stop**). Three of them use
  relative paths and inline commands and work anywhere. The **Stop** hook resolves
  `${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/planning-with-files}/scripts/...` — if
  you install it as a plain project skill, `CLAUDE_PLUGIN_ROOT` is unset, so that one
  hook only resolves if its scripts are ALSO at `$HOME/.claude/plugins/planning-with-files/scripts/`.
  It **fails open** (just a "did you finish?" nudge), so the core planning works
  regardless. To make the Stop check resolve too, either install planning-with-files
  at user level (`~/.claude/skills/planning-with-files/`) or mirror its scripts:
  `mkdir -p ~/.claude/plugins/planning-with-files && cp -R "$KIT/sibling-skills/planning-with-files/scripts" ~/.claude/plugins/planning-with-files/`.
- **`fusion`** is OPTIONAL and only used to resolve design-weighty engineering forks
  (`/fusion-gpt5.5` in SKILL.md). It needs the `codex` CLI (GPT-5.5 panel) and/or
  `gemini` CLI for the richer panels; without them it falls back to the
  always-available two-Opus panel. The core build loop never requires fusion.

## Step 4 — Install the control-plane hook + gate scripts (verbatim)

```bash
cp "$KIT/control-plane/hooks/roborev-gate.sh"            .claude/hooks/
cp "$KIT/control-plane/hooks/roborev-session-sweep.sh"   .claude/hooks/
cp "$KIT/control-plane/hooks/post-compact-reground.sh"   .claude/hooks/   # TEMPLATE — edit in Step 5
cp "$KIT/skill/claude-controlled-build-run/references/core/scripts/merge-review-gate.sh" scripts/  # the merge-boundary review wall (the pre-commit entry hardcodes ./scripts/merge-review-gate.sh)
chmod +x .claude/hooks/*.sh scripts/merge-review-gate.sh
```

`roborev-gate.sh` and `roborev-session-sweep.sh` are fully
project-agnostic (they use only `roborev`/`git`/`jq`/`python3`) — leave them as-is.

## Step 5 — Merge config + fill in the templates (the judgment work)

1. **`.claude/settings.json`** — **MERGE** `control-plane/settings.hooks.json` into it
   (preserve any existing hooks; don't overwrite). It wires Probity (PreToolUse),
   the RoboRev gate (PostToolUse, `asyncRewake`), and the two SessionStart hooks
   (sweep + reground/`compact`). Then set/confirm the top-level `"model"` to a model
   your account can actually use (NOT a friendly alias, NOT an unavailable one). The
   Probity version is pinned (`@nizos/probity@1.8.1`) — keep a pin, and bump the package.json devDependency and the hook fallback TOGETHER.
2. **`probity.config.ts`** (repo root) ← `control-plane/templates/probity.config.ts.template`.
   Set the `files` globs to your production tree; keep `enforceTdd()`; set/remove the
   naming bans. (Worked reference: `examples/reference-probity.config.ts`.)
3. **`.pre-commit-config.yaml`** (repo root) ← `control-plane/templates/pre-commit-config.yaml.template`.
   Replace the format/lint/type/test placeholders with your real commands; keep
   `gitleaks` only if installed.
4. **`.roborev.toml`** (repo root) ← `control-plane/templates/roborev.toml.template`.
   Keep `agent`/`review_agent = "claude-code"`; set `review_model` to a model you
   have; rewrite `review_guidelines` for your repo.
5. **`.claude/hooks/post-compact-reground.sh`** — edit the `PORTING` block at its top:
   point `PRINCIPLE_DOCS` / `VOCAB_DOC` / `ROUTING_DOC` at your binding docs (leave any
   empty), confirm `SKILL_REL`/`TDD_REL` match where you installed the skills, and set
   `HANDOFF_GUARD=0` unless your repo's boot ritual reads a "newest handoff".
6. **`skill/claude-controlled-build-run/SKILL.md` + `scripts/cbr.sh`** — apply the deltas in
   `skill/claude-controlled-build-run/PORTING.md` (model dial, package paths, doc names, the
   `cbr.sh` constants `DEFAULT_MODEL`/`WEB_PKG`/worktree prefix/branch patterns). Only
   needed for the fleet/`cbr.sh` flow if you skip parallel dispatch.
7. **`.cbr/provision-hook.sh`** (repo root, OPTIONAL — write it, don't copy it) —
   if your stack needs workspace prep beyond what provision already does (a
   fresh worktree lacks every gitignored artifact), put it here. Every leaf's
   provision runs this hook inside the new worktree with `$1`=primary repo
   root, `$2`=worktree; a failing hook fails the provision loudly (by design —
   never dispatch onto a half-prepared worktree). Must be executable
   (`chmod +x`). No hook needed → skip this step entirely. Examples:

   ```sh
   #!/bin/sh
   # Node/pnpm: reuse the primary checkout's installed deps
   ln -s "$1/node_modules" "$2/node_modules"
   ```

   ```sh
   #!/bin/sh
   # Python/uv: sync the worktree's own venv
   cd "$2" && uv sync --frozen
   ```

## Step 6 — Arm the gates (run in the repo root)

```bash
roborev init --agent claude-code     # writes/uses .roborev.toml + installs post-commit/post-rewrite git hooks
roborev daemon start                 # start the review daemon
roborev daemon status                # confirm it's up

# RoboRev sends PostHog telemetry by default. Disable it by starting the DAEMON with
# TELEMETRY_ENABLED=0 (value MUST be 0 — `=false` is silently ignored). See "Tool notes".
# e.g. instead of `roborev daemon start`:
#   TELEMETRY_ENABLED=0 roborev daemon start
# then make it persistent (launchd agent / shell env). Reviews are unaffected.

# install the pre-commit git hook (pick the one that matches your setup):
pre-commit install                   # if pre-commit is on PATH
# uv run pre-commit install          # if you manage pre-commit through uv

# pre-warm Probity so the FIRST PreToolUse hook doesn't time out on a cold npx fetch:
npx --yes @nizos/probity@1.8.1 --help >/dev/null 2>&1 || echo "could not pre-fetch probity (need network to registry.npmjs.org)"

# In an interactive Claude session, run /hooks once if the new hooks didn't auto-arm.
```

## Step 7 — Verify (static)

```bash
bash controlled-build-run-kit/verify/smoke.sh
```

It checks prerequisites, that Probity/RoboRev/pre-commit/reground/sweep are wired,
and that the skill + `cbr.sh` are in place. Fix every `FAIL` before relying on the control plane.

## Step 8 — Verify (live — only a Claude session can do this)

> On a non-Claude-Code agent harness, this step is also where you confirm the hooks fire at
> all — the gates are Claude Code hooks (see "Tool notes"). A green smoke test (Step 7)
> proves the files are present, NOT that the gate bites; only this step does.

The two checks a shell cannot fake, from inside an interactive Claude session in this repo:
- **prove-NO:** attempt an untested production write inside your Probity-gated tree →
  it must be **BLOCKED**.
- **prove-YES:** run one real toolchain command and make one throwaway `Write` you then
  delete → both must **SUCCEED** (proves the path isn't over-locked).

Then make a tiny real commit and confirm RoboRev reviews it (`roborev show HEAD`).
Per-commit reviews are advisory — a second commit is NOT held; the blocking
review check is the merge-path gate.
If all of that holds, the control plane is armed — start a build with the
`controlled-build-run` skill (read its `SKILL.md`).

---

### What's machine-specific and must NOT be copied between machines
`~/.claude.json` (OAuth + trust + caches), `~/.roborev/` (the review DB + daemon
state — let `roborev init` create fresh), any `.venv` / `node_modules` (rebuild),
generated `.git/hooks/pre-commit` (it embeds an absolute interpreter path —
regenerate with `pre-commit install`), `.claude/settings.local.json` worktree
allowlists (gitignored, written fresh by `cbr.sh provision`), and any API keys /
`.env`. Re-do auth + trust (Step 1) and `roborev init` (Step 6) on each new machine.
