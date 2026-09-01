---
name: cbr-setup
description: >-
  Arm the CBR control plane in this repo. Use when the user says "set up CBR",
  "install CBR", "arm this repo", or the cbr router found the repo unarmed.
  Detects the stack, adapts the configs, proves the gates bite.
---

# cbr-setup — arm this repo

Setup follows the package's own law: **merge, adapt, verify — never
blind-overwrite.** The flow is detect → propose → ratify → prove.

## 1. Vendor the package

If the repo does not already contain the package, copy it in whole from this
plugin's bundle: copy `${CLAUDE_PLUGIN_ROOT}` to `controlled-build-run/` at
the repo root (skip `.git`, `.claude-plugin`, and this `skills/` folder).
Vendoring the whole package — both harness adapters included — is deliberate:
the Codex adapter is then on hand for a Codex session to arm from (it has its
own installer), and teammates without this plugin still get every repo-level
gate.

## 2. Run the real installer

Follow `controlled-build-run/SETUP-claude-code.md` (the Claude Code
installer; the root `SETUP.md` is only the harness router) end to end. That
document owns the details. Honor these rules while you do:

- **Detect, then propose.** Read the repo's languages, package layout, test
  runner, and lint/type/format commands first. Fill the config templates
  (`probity.config.ts`, `.pre-commit-config.yaml`, `.roborev.toml`, the
  re-ground doc list) to match, and show the operator the filled configs as
  a diff before installing them.
- **Ratify.** The operator confirms the proposed commands are right for this
  repo. Ask only about what detection left genuinely ambiguous.
- **Write repo-level hooks, not just plugin hooks.** Install the settings
  hooks block into the repo's `.claude/settings.json` and the git hooks into
  `.git/hooks` per the installer, so the guard does not depend on any one
  person's plugin.

## 3. Prove it

Not armed until proven. Run the package doctor and both live probes:

- **prove-NO:** attempt an untested production write — Probity must block it.
- **prove-YES:** one real toolchain command and one throwaway allowed edit —
  both must succeed.

Report the PASS/FAIL table to the operator. A repo that fails a probe is not
armed, whatever the configs say.
