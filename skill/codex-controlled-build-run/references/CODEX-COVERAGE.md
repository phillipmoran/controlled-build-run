# Codex source coverage — provider mechanics preserved

This map accounts for every section of the pre-core Codex source router. It is
the provider-side companion to `cbr-core/COVERAGE.md`: the shared map proves the
neutral law, while this map proves that Codex-specific mechanisms were not lost
when the long router became a short router plus leaf files.

Source identity:

- commit: `216fc688e5ddedbc38b931da55a7bbca565bd9fd`
- path: `skills/codex-controlled-build-run/SKILL.md`
- lines: `1061`
- sha256: `7911bf7d3c8ed3096bf98dddca30e52075e6de9fd089da9fba5f7264ced90766`

Dispositions use `core:<path>` for the embedded neutral-law snapshot and
`leaf:<path>` for surviving Codex mechanics. Mixed sections deliberately name
both. No section may be pending or unmapped.

## Complete section disposition

| Source lines | Disposition | Content preserved |
|---|---|---|
| 1–29 | leaf:SKILL.md + leaf:SETUP.md + leaf:references/porting.md | Registry metadata, Codex port identity, repository knobs, watcher and blocker conventions. |
| 30–41 | core:policy.md + leaf:SKILL.md | Harness purpose, automatic discipline, and the verify-then-run order. |
| 42–76 | core:policy.md + core:reviews.md + leaf:references/harness.md + leaf:references/build-loop.md | Check matrix, deterministic-vs-judgment law, and the two Codex/Git hook systems. |
| 77–121 | core:policy.md + leaf:references/harness.md + leaf:scripts/cbr-codex.sh + leaf:templates/codex-hooks.json | Verify-or-wire phase, pinned Probity host, RoboRev lifecycle, pre-commit wiring, and fail-open/fail-closed split. |
| 122–144 | core:policy.md + leaf:SKILL.md + leaf:references/porting.md + leaf:templates/cbr-codex.json | Codex compaction threshold, model clamp, and doctor enforcement. |
| 145–170 | core:policy.md + leaf:templates/hooks/post-compact-reground.sh + leaf:references/harness.md | Whole reinjection, active-plan binding, already-booted guard, and live Codex event mechanics. |
| 171–222 | core:strand.md + leaf:references/harness.md + leaf:scripts/cbr-codex.sh | One-plan/branch/folder/session isolation, provisioning, live prove-NO/prove-YES, sandbox, and approval policy. |
| 223–248 | core:strand.md | Decision-dense plan altitude and required observable/test/ownership/verification fields. |
| 249–432 | core:build-loop.md + core:reviews.md + core:judgment.md + leaf:references/build-loop.md + leaf:references/panel-review.md | Watched-fail loop, frequent commits, RoboRev close discipline, golden samples, checkpoint taxonomy, and closeout. |
| 433–489 | core:judgment.md + leaf:references/panel-review.md | Decision triage, independent panel mechanics, file-channel escalation, and ratification boundary. |
| 490–554 | core:build-loop.md + leaf:references/build-loop.md + leaf:references/harness.md + leaf:templates/probe-prompt.md | Probity scars, patch/write aliases, live probes, exemption proof, and worktree-root limits. |
| 555–591 | core:policy.md + leaf:SKILL.md + leaf:references/porting.md + leaf:templates/cbr-codex.json | Codex model/reasoning dial, cross-family review, explicit launch values, and threshold projection. |
| 592–752 | core:modes/fleet.md + core:reviews.md + leaf:references/fleet.md + leaf:scripts/cbr-codex.sh + leaf:scripts/cbr_graph.py | Fleet graph, plan review, ownership serialization, provisioning, merge/smoke/retirement, and decision log. |
| 753–968 | core:modes/fleet.md + leaf:references/fleet.md + leaf:scripts/cbr-codex.sh + leaf:scripts/captain-watch-codex.sh + leaf:templates/dispatch-prompt.md + leaf:templates/resume-prompt.md | Persisted Codex roots, trust, sandbox, approvals, push firewall, run registry, watching, recovery, and escalation channel. |
| 969–1054 | core:modes/captain.md + leaf:references/fleet.md + leaf:scripts/cbr-codex.sh + leaf:scripts/captain-watch-codex.sh | Captain root, status-file doctrine, N:1 watching, liveness evidence, and human gates. |
| 1055–1061 | core:policy.md + leaf:SKILL.md | Honest-gap conclusion: files and automatic enforcement replace memory. |

## Provider-mechanical destination inventory

Each row carries a distinctive witness from the old Codex source. The
conformance check requires that witness in the named surviving destination; a
deleted or silently omitted mechanism therefore turns the test red.

| ID | Old-source concern | Destination | Required witness |
|---|---|---|---|
| C01 | Codex project-hook surface | leaf:references/harness.md | `.codex/hooks.json` |
| C02 | Correct Probity host adapter | leaf:templates/codex-hooks.json | `--agent codex` |
| C03 | Pinned Probity fallback | leaf:templates/codex-hooks.json | `@nizos/probity@1.10.0` |
| C04 | Effective compaction threshold | leaf:SKILL.md | `model_auto_compact_token_limit` |
| C05 | Whole additional context | leaf:templates/codex-hooks.json | `additionalContextLimit` |
| C06 | Persisted detached builder | leaf:SKILL.md | `codex exec --json` |
| C07 | Headless approval behavior | leaf:SKILL.md | `approval_policy="never"` |
| C08 | Worktree sandbox boundary | leaf:SKILL.md | `--sandbox workspace-write` |
| C09 | Durable run registry | leaf:scripts/cbr-codex.sh | `.cbr-codex/runs/` |
| C10 | Push firewall override | leaf:references/acceptance.md | `CBR_ALLOW_PUSH=1` |
| C11 | Not-yet-watched latch | leaf:references/acceptance.md | `.needs-arm` |
| C12 | Human blocker file | leaf:templates/hooks/builder-stop-check.sh | `NEEDS-HUMAN.md` |
| C13 | Branch-scoped review query | leaf:templates/roborev-clean-gate.sh | `--branch "$branch"` |
| C14 | Exact-SHA review backstop | leaf:templates/roborev-clean-gate.sh | `roborev show "$head_sha"` |
| C15 | Patch write-path probe | leaf:templates/probe-prompt.md | `apply_patch` |
| C16 | Explicit builder model | leaf:scripts/cbr-codex.sh | `-m "$model"` |
| C17 | Hook trust record | leaf:scripts/cbr-codex.sh | `hook-trust.sha256` |
| C18 | Orchestrator payload branch | leaf:templates/hooks/post-compact-reground.sh | `orchestrator)` |
| C19 | Workstream payload branch | leaf:templates/hooks/post-compact-reground.sh | `workstream)` |
| C20 | Captain status artifact | leaf:scripts/cbr-codex.sh | `STATUS.md` |
| C21 | Builder question channel | leaf:templates/dispatch-prompt.md | `ASK-ORCH.md` |
| C22 | No post-compact reboot | leaf:templates/hooks/post-compact-reground.sh | `ALREADY booted` |
| C23 | Recorded builder thread | leaf:scripts/cbr-codex.sh | `thread.started` |
