# SETUP — arm the controlled-build-run control plane on this repo (Claude Code)

**You are an agent. You have been pointed at this package, which sits inside a
target repository. Your job: arm the controlled-build-run control plane on THIS
repo, then prove it.** Follow the steps in order. Steps marked **[HUMAN]** need
a person — do them, or pause and ask for them; you cannot do them yourself.

> What you are installing: a plan-driven control plane with **deterministic
> gates** — **Probity** (TDD judge, blocks untested writes), **pre-commit**
> (format/lint/types/tests, blocks the commit), the **merge review wall**
> (blocks a merge until the branch review is clean), the **stop gate** (a
> builder cannot go quiet with the plan open), the **control-plane guard** (the
> gates are not the agent's to edit) — plus **RoboRev** (per-commit LLM review,
> advisory), **drift-proof hooks** (session-start sweep + post-compaction
> re-ground), and the `cbr.sh` rail for solo or fleet builds. The skill prose in
> `skill/claude-controlled-build-run/SKILL.md` is the policy and the *why*;
> `skill/claude-controlled-build-run/SETUP.md` explains each piece in plain
> words; this file is the install procedure.

There is **one** installer for Claude Code: `cbr.sh arm`. It creates what is
absent, reports what it will not touch, and never clobbers. The golden rule for
everything you do by hand afterwards: **MERGE, ADAPT, VERIFY — never
blind-overwrite.**

---

## Step 0 — Prerequisites

```bash
for c in claude roborev git jq node npx python3 pre-commit; do command -v "$c" >/dev/null && echo "ok  $c" || echo "MISSING $c"; done
command -v gitleaks >/dev/null && echo "ok  gitleaks" || echo "-- gitleaks (the shipped pre-commit template wires it; install it or delete that hook)"
claude --version   # fleet dispatch needs a build with `--bg` + `claude agents`
roborev version
```

Install the missing ones (macOS/Homebrew shown; adapt for your OS):
- `roborev`: `brew install roborev` (or see the RoboRev project). Required.
- `jq`: `brew install jq`. Required — the hooks emit their JSON through it and **fail open without it**.
- `node`/`npx`: any recent Node. Required — Probity runs from `node_modules/.bin` or an `npx` fallback.
- `python3`: required — the gate scripts' inline logic and the control-plane guard.
- `pre-commit`: `pipx install pre-commit` (or `uv tool install pre-commit`). Required — it installs the commit-stage git hooks.
- `gitleaks`: `brew install gitleaks`. The template wires it; keep it or remove the hook.

**Hard floor:** if `claude --bg` is unsupported by the installed CLI, parallel
*builder dispatch* won't work — the solo control plane still does.

## Tool notes (the gotchas — pointed at from the steps below)

1. **RoboRev sends usage telemetry by default — disable it with `TELEMETRY_ENABLED=0`.**
   The `roborev` binary has the PostHog analytics SDK compiled in; the **daemon** is
   the sender. The off-switch is an env var on the daemon, and the value **must be
   `0`** — `=false` reads as still-on. No config-file key exists. Set it in the
   environment that launches the daemon (`TELEMETRY_ENABLED=0 roborev daemon start`,
   or a launchd/systemd unit with it in the env). Verify with
   `lsof -nP -iTCP -p <daemon-pid>`: no connection to `us.i.posthog.com`.

2. **The gates are Claude Code hooks, so they only bite on Claude Code.** Probity,
   the ask guard, and the control-plane guard fire because `.claude/settings.json`
   wires them into Claude Code's hook events. Another harness needs its own
   installer (Codex: `skill/codex-controlled-build-run/SETUP.md`). A green
   `doctor` proves the files are present and wired; only the live probe (Step 6)
   proves a gate bites.

3. **Claude Code applies changes to `.claude/settings.json` immediately.** The
   control-plane guard is live from the moment `arm` writes that file, and from
   then on it denies edits to the session hooks, `.claude/settings.json`,
   `.git/`, and the gate scripts. Pin a non-default model with `arm --model`
   (Step 3) rather than editing the file afterwards. An operator who needs
   those files edited later starts the session with `CBR_CONTROL_PLANE_UNLOCK=1`
   in its environment. Do not set that variable yourself.

## Step 1 — [HUMAN] Auth + repo trust

1. **[HUMAN]** Make sure the Claude Code login is fresh: run `/login` in an
   interactive Claude session. One login powers the `claude` CLI, Probity's judge
   when it runs on Claude, and RoboRev's reviewer when it runs on Claude; one
   expired token 401s all of them at once.
2. **[HUMAN]** Open this repo once in an interactive Claude session and accept the
   workspace-trust prompt. Trust is keyed by repo. A `claude --bg` builder
   **stalls forever** on an unanswered trust prompt, so trust must be accepted
   BEFORE any `--bg` dispatch. Verify: `~/.claude.json` →
   `projects["<repo path>"].hasTrustDialogAccepted == true`.

## Step 2 — Learn this repo's shape (you do this)

Before filling any template you must know the target. Determine and note:
- Languages + package/source layout (what Probity should guard, what the gates run on).
- The real **format / lint / typecheck / test** commands.
- The repo's **binding docs** — its short "how we build" documents, or note it has none.
- Which model ids this account can actually use (orchestrator, builders, reviewer).

## Step 3 — Arm (one command)

```bash
KIT="<path to this package>"   # e.g. "$(pwd)/controlled-build-run" when the plugin vendored it
bash "$KIT/skill/claude-controlled-build-run/scripts/cbr.sh" arm "$(pwd)" --no-probe [--model <orchestrator-model-id>]
```

What `arm` installs (create-if-absent; an existing file is reported and left
alone):
- `skills/claude-controlled-build-run/` — the skill, its law, `cbr.sh`, and the templates.
- `skills/test-driven-development/`, `skills/cyclomatic-complexity/`,
  `.claude/skills/planning-with-files/` — the sibling skills the re-ground hook points at.
- `.claude/settings.json` (from `templates/claude-settings.json`) — the full hooks
  block: Probity, the ask guard, the control-plane guard, the RoboRev wake, the
  session sweep, the compaction re-ground, the stop gate, and the model pin
  (`--model` sets it on the fresh file). If the file already exists, `arm` lists
  the missing blocks and you **merge them by hand** from the template.
- `.claude/hooks/*.sh` — the six hook scripts.
- `probity.config.ts`, `.roborev.toml`, `.pre-commit-config.yaml`,
  `record-ownership.json` — skeletons with `EDIT ME` markers (Step 4).
- `scripts/merge-review-gate.sh`, `scripts/record-single-source.sh` — the gate scripts.
- The `pre-commit` **and** `pre-merge-commit` git hooks, the `pre-push` firewall,
  `merge.ff=false` (a fast-forward merge fires no hook, so every merge must be a
  merge commit), `.gitignore` entries, and an `AGENTS.md` pointer if the repo has none.

`--no-probe` skips the automatic `claude --bg` probe; you run the probe yourself
in Step 6, where you can read its verdict. `arm` is idempotent — re-run it
after fixing anything it reported.

## Step 4 — Fill in the EDIT-ME files (the judgment work)

`doctor` fails while any `EDIT ME` marker remains. Show the operator each filled
file as a diff before you consider it done.

1. **`probity.config.ts`** — set the `files` globs to your production tree
   (the skeleton's globs are TypeScript-only; on any other stack an unedited
   skeleton guards nothing). Keep TDD enforcement on. Worked reference:
   `examples/reference-probity.config.ts`.
2. **`.pre-commit-config.yaml`** — replace the placeholder typecheck/test hooks
   with your real commands; keep the `merge-review-gate`, `record-single-source`,
   and (if installed) `gitleaks` hooks verbatim. Heads-up: this package carries
   its own test files — exclude the vendored folder (and `.agents/**`,
   `.claude/skills/**`) from your test runner's discovery, or a broad run
   collects them as project tests.
3. **`.roborev.toml`** — rewrite `review_guidelines` for this repo. The skeleton
   pins a reviewer from a **different model family than the builders** (the
   cross-family rule in `policy.md`); keep that property when you change models.
   Then `roborev init` in the repo root (writes/uses this file and installs the
   post-commit/post-rewrite git hooks) and start the daemon — see Tool notes 1.
4. **`.claude/hooks/post-compact-reground.sh`** — edit the `PORTING` block at
   the top: `HOUSE_DOCS` (short binding docs, injected whole),
   `PRINCIPLE_POINTERS` (longer docs, listed as re-read pointers),
   `SKILL_REL`/`TDD_REL`/`COMPLEXITY_REL` (already correct for an `arm`
   install), `HANDOFF_GUARD=0` unless your boot ritual reads a "newest
   handoff". The hook injects only docs that exist. (This is the one hook
   the control-plane guard leaves editable.)
5. **`record-ownership.json`** — name this repo's record files, or leave the
   starter if the shipped conventions fit.
6. **Fleet only:** `skill/claude-controlled-build-run/PORTING.md` lists the
   `cbr.sh` constants to re-point (builder model, worktree prefix, package
   paths). Skip for solo builds.
7. **Optional:** `.cbr/provision-hook.sh` (repo root, executable) for
   workspace prep a fresh worktree needs beyond what provision does
   (`ln -s "$1/node_modules" "$2/node_modules"`, `cd "$2" && uv sync`). A failing
   hook fails the provision loudly, by design.

Optional sibling skills, if you want them (never required by the loop):

```bash
cp -R "$KIT/sibling-skills/fusion"       .claude/skills/   # design-panel; needs `codex`/`gemini` CLIs
cp "$KIT/sibling-skills/fusion/commands/"*.md .claude/commands/
cp -R "$KIT/sibling-skills/stage-review" skills/           # phase-review cadence
cp -R "$KIT/sibling-skills/closeout"     .claude/skills/   # solo closeout ritual
```

`planning-with-files` caveat: its Stop hook resolves
`${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/planning-with-files}/scripts/...`.
Installed as a project skill it fails open (a "did you finish?" nudge); mirror
its `scripts/` to that path if you want the nudge too.

## Step 5 — Verify (static)

```bash
bash skills/claude-controlled-build-run/scripts/cbr.sh doctor
```

It grades every piece `arm` installed — hook wiring and executability, hook
bodies against their templates, `merge.ff`, both commit-stage git hooks, the
push firewall, the `EDIT ME` markers, the sibling skills, the RoboRev daemon and
an agent round-trip (catches an expired login), the compaction triple, and the
vendored package's manifest. Fix every `FAIL` before relying on the control
plane; read every `WARN`.

## Step 6 — Verify (live — only a Claude session can do this)

From inside an interactive Claude session in this repo:
- **prove-NO:** attempt an untested production write inside your Probity-gated
  tree → it must be **BLOCKED**.
- **prove-YES:** run one real toolchain command and make one throwaway `Write`
  you then delete → both must **SUCCEED** (proves the path isn't over-locked).
- **guard:** attempt to edit `.claude/hooks/builder-stop-check.sh` → it must be
  **BLOCKED** by the control-plane guard.

Then make a tiny real commit and confirm RoboRev reviews it (`roborev show HEAD`).
Per-commit reviews are advisory; the blocking review check is the merge wall.
If all of that holds, the control plane is armed — start a build with the
`controlled-build-run` skill (read its `SKILL.md`).

---

### What's machine-specific and must NOT be copied between machines
`~/.claude.json` (OAuth + trust + caches), `~/.roborev/` (the review DB + daemon
state — let `roborev init` create fresh), any `.venv` / `node_modules` (rebuild),
the generated git hooks under `.git/hooks/` (re-run `arm`), `.claude/settings.local.json`
worktree allowlists (gitignored, written fresh by `cbr.sh provision`), and any
API keys / `.env`. Re-do auth + trust (Step 1) and `roborev init` on each new machine.
