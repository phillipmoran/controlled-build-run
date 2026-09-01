# Porting and installation

The source package is repository-local at `skills/codex-controlled-build-run/`. A Codex-discoverable team installation belongs at `.agents/skills/codex-controlled-build-run/`; `cbr-codex.sh arm` copies the package there only when absent.

## Repository decisions to make first

1. Binding docs to reinject whole after compaction.
2. Production globs that Probity guards.
3. Guarded production globs in `.cbr-codex.json`; exempt zones and substitute
   proof for each stay explicit in the stream plan.
4. Live pre-commit commands for format, lint, types, tests, secrets, and other deterministic facts.
5. RoboRev reviewer model and repository-specific review rules.
6. Worktree prefix and builder/integration branch patterns.
7. Dependency setup command for a fresh worktree.
8. Builder model/reasoning and effective compaction threshold.
9. Live product smoke command and observable success evidence.
10. Archive paths and release branch.

The target must install both `@nizos/probity@1.10.0` and
`@openai/codex-sdk` locally. The hook fallback can start the pinned Probity CLI,
but the fail-closed Codex judge still resolves its SDK from the repository.
Keep the template's neutral temporary judge directory and
`project_root_markers = []`; removing either lets target-repository hooks run
inside the judge itself. Install the content-policy helper with the Probity
config as well; it scans full non-patch writes but only additions in a patch,
so paths, context, and removed legacy text cannot cause false positives.

## Files installed by `arm`

- `.agents/skills/codex-controlled-build-run/` — skill package, create-if-absent.
- `.codex/hooks.json` — lifecycle wiring, create-if-absent.
- `.codex/hooks/*.sh` — hook commands, create-if-absent.
- `probity.config.ts` — skeleton, create-if-absent.
- `probity-content-policy.mjs` and `probity-content-policy.d.mts` — content-rule
  runtime helper and TypeScript contract, create-if-absent.
- `probity-verdict-parser.mjs` and `probity-verdict-parser.d.mts` — fail-closed
  judge-output parser and TypeScript contract, create-if-absent.
- `probity-integration.mjs` and `probity-integration.d.mts` — private runtime
  attestation proving the active exported config uses the current integration
  path, create-if-absent.
- `.roborev.toml` — skeleton, create-if-absent.
- `.cbr-codex/scripts/plan-coherence.sh` — branch/plan/staged-work gate.
- `.pre-commit-config.yaml` — fail-closed skeleton, create-if-absent.
- `.cbr-codex.json` — portable repository knobs, create-if-absent.
- `.gitignore` entries for the run/watch registry, hook-vet hash, and
  worktree-local `.cbr-codex/provision.json`; tracked gate scripts remain visible.
- stream pre-push firewall in the worktree-safe Git hooks path when no foreign hook conflicts.
- a minimal `AGENTS.md` pointer only when neither `AGENTS.md` nor another repository agent entry exists.

`arm` never overwrites an existing file. If `.codex/hooks.json` exists but
misses required events, or an existing `probity.config.ts` lacks the current
judge-isolation, content-policy, or verdict-parser integrations, it reports a
manual merge and exits nonzero. This prevents both destructive overwrites and
false-green upgrades. The six Probity runtime/type helper files are versioned
engine files, not project knobs: `arm` and `doctor` require byte identity with
the executing skill package.

## `.cbr-codex.json`

Configure:

```json
{
  "worktreeParent": "..",
  "worktreePrefix": "repo-",
  "activePlanPath": "task_plan.md",
  "builderBranchPattern": "^stream/",
  "integrationBranchPattern": "^integration/",
  "setupCommands": ["pnpm install --offline --frozen-lockfile"],
  "toolchainProbe": "pnpm exec tsc --version",
  "models": {
    "builder": "gpt-5.6-sol",
    "builderReasoning": "high",
    "reviewerAgent": "claude-code",
    "reviewer": "claude-sonnet-5"
  },
  "modelContextTokens": 350000,
  "autoCompactTokenLimit": 297500,
  "stallSeconds": 900,
  "reviewFailGraceSeconds": 600,
  "releaseBranches": ["main", "master"],
  "productPaths": ["packages", "adapters", "src", "e2e", "public", "scripts"]
}
```

Commands run in the new worktree. Keep them deterministic and non-interactive. An empty `setupCommands` list is valid only when the worktree needs no generated/ignored dependencies; `toolchainProbe` must still prove buildability.

`activePlanPath` defaults to the strand-root `task_plan.md` and must remain so
for dispatched builders. A repository maintaining the control plane itself may point
it at a dedicated planning trio only when an unrelated root plan is already
durable state; launch/dispatchability still enforce root-level stream plans.

## Hook adaptation

Declare the SHORT house-rules set in `.cbr-codex.json` under
`reinjectionDocs` — the constitution-level invariants and the routing map,
nothing more. The hook injects those whole, then the active plan, findings,
and the progress tail, and lists everything else — principles, the skill,
shared common law, exactly one role-specific process payload — as re-read
POINTERS under a stated byte budget (the law is stable on disk; the in-flight
state is what a compaction loses). An orchestrator gets fleet-law pointers
and Codex fleet mechanics; a workstream gets the build loop and Codex
workstream mechanics, plus solo law only when its branch is not a
fleet-builder branch. Immediate continuation must not perform a file-reading
orientation ritual.

The package's `references/cbr-core/` directory is a generated, byte-exact
snapshot of the canonical shared core. Refresh it mechanically when the
canonical core changes, then run `scripts/tests/conformance.py` before exporting
or installing the leaf. Do not hand-weave core paragraphs into provider files.
The check is portable and never assumes the target contains the upstream repo's
Git history.

## Models

Keep model decisions in one project dial:

- builder model/reasoning in `.cbr-codex.json`;
- RoboRev model in `.roborev.toml`;
- Probity judge in `probity.config.ts` when using an AI judge;
- orchestrator/subagent defaults in project `.codex/config.toml` only if the repository wants durable defaults.

The launch command always passes builder values explicitly and surfaces them before execution. A wrong-model run must be stopped; audit and remove any unreviewed work from that window before relaunch.

## Compaction

The source policy's effective threshold is 297,500 tokens. Add this to `.codex/config.toml` only if supported by the chosen model:

```toml
model_auto_compact_token_limit = 297500
```

The re-ground hook is still mandatory. Delayed compaction reduces drift opportunities; it does not eliminate them.

## Trust and automation

Interactive use: start the Codex terminal TUI in the repository. At the `Hooks need review` screen choose `Review hooks`, inspect the exact commands and sources, then use the on-screen trust action. Codex Desktop chat does not expose a `/hooks` command.

Detached automation: the launch rail may pass `--dangerously-bypass-hook-trust` because `arm`/`doctor` vets a repository-owned fixed hook set first. This flag bypasses the trust prompt, not hook execution. Do not use it for arbitrary/unreviewed repository hooks.

Use `workspace-write`, not `danger-full-access`. Set `approval_policy="never"`
through the supported Codex config override so non-interactive runs receive
failures instead of hanging on prompts. The Git push firewall remains mandatory
because approval configuration is not a release boundary.

## Acceptance order

1. Static skill validation and shared-core/leaf conformance.
2. Shell syntax and JSON validation.
3. Mutation checks for the structural and provider-separation scars.
4. Fixture tests for hook block/allow, role-aware re-ground sections, Stop behavior, and clean-gate status semantics.
5. `doctor` against the live repository.
6. Operability probe: production write blocked, scratch write allowed, toolchain works.
7. Disposable worktree launch/resume/status/watch smoke.
8. One full live build before relying on unattended fleet mode.
