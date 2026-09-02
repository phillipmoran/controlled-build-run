---
name: cbr-setup
description: >-
  Arm the CBR control plane in this repo. Use when the user says "set up CBR",
  "install CBR", "arm this repo", or the cbr router found the repo unarmed.
  Vendors the package, runs the one installer, fills the configs, proves the
  gates bite.
---

# cbr-setup — arm this repo

Setup follows the package's own law: **merge, adapt, verify — never
blind-overwrite.** The flow is vendor → arm → fill → doctor → prove.

## 1. Vendor the package

If the repo does not already contain the package, copy it in whole from this
plugin's bundle: copy `${CLAUDE_PLUGIN_ROOT}` to `controlled-build-run/` at
the repo root (skip `.git`, `.claude-plugin`, and this `skills/` folder).
Vendoring the whole package — both harness adapters included — is deliberate:
the Codex adapter is then on hand for a Codex session to arm from (it has its
own installer), and teammates without this plugin still get every repo-level
gate.

## 2. Arm (one command)

```
bash controlled-build-run/skill/claude-controlled-build-run/scripts/cbr.sh arm "$(pwd)" --no-probe [--model <orchestrator-model-id>]
```

`arm` creates what is absent and reports what it will not touch: the skill
and its sibling skills, `.claude/settings.json` with the full hooks block,
the six hook scripts, the config skeletons, the gate scripts, both
commit-stage git hooks, the push firewall, and `merge.ff=false`. If
`.claude/settings.json` already exists it lists the missing hook blocks; merge
them by hand from the template it names.

**The control-plane guard is live the moment `arm` writes the settings
file.** From then on it denies your edits to the session hooks, the settings
file, `.git/`, and the gate scripts. That is the point. Pin a model with
`--model` at arm time rather than editing the file afterwards; if something
in those files must change later, tell the operator — they unlock a session
with `CBR_CONTROL_PLANE_UNLOCK=1` in its environment. Never set it yourself.

## 3. Fill the EDIT-ME files (the judgment work)

`controlled-build-run/SETUP-claude-code.md` Step 4 owns the details. Honor
these rules while you do:

- **Detect, then propose.** Read the repo's languages, package layout, test
  runner, and lint/type/format commands first. Fill `probity.config.ts`,
  `.pre-commit-config.yaml`, `.roborev.toml`, `record-ownership.json`, and
  the re-ground hook's PORTING block to match, and show the operator each
  filled file as a diff before you consider it done. Remove every `EDIT ME`
  marker; `doctor` fails while one remains.
- **Ratify.** The operator confirms the proposed commands are right for this
  repo. Ask only about what detection left genuinely ambiguous.
- **Keep the gate hooks verbatim** in `.pre-commit-config.yaml`
  (`merge-review-gate`, `record-single-source`, `gitleaks` if installed);
  replace only the placeholder typecheck/test commands.
- **Do the human steps with the operator:** Claude login, workspace trust,
  `roborev init` and the daemon (with telemetry off — the installer's Tool
  notes say how).

## 4. Prove it

Not armed until proven.

```
bash controlled-build-run/skill/claude-controlled-build-run/scripts/cbr.sh doctor
```

Fix every FAIL; read every WARN. Then the live probes, from inside this
session:

- **prove-NO:** attempt an untested production write — Probity must block it.
- **prove-YES:** one real toolchain command and one throwaway allowed edit —
  both must succeed.
- **guard:** attempt to edit `.claude/hooks/builder-stop-check.sh` — the
  control-plane guard must block it.

Report the PASS/FAIL table to the operator. A repo that fails a probe is not
armed, whatever the configs say.
