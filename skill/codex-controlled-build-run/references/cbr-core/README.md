# cbr-core — the provider-neutral CBR law

This folder holds the harness-agnostic core of the Controlled Build Run
process: the laws, the check table, the strand discipline, the build loop, the
review lifecycle, and the run modes — with every provider mechanism removed to
the per-harness leaf/adapter files. Core files are copied verbatim into each
leaf and hash-gated there; nothing in this folder may name a specific
provider's tools, flags, or file paths (enforced by the neutrality lint in
`scripts/`, wired into pre-commit).

Contents land per the `cbr/core-extract` plan:

- `policy.md` — laws, the check table, fail-open/fail-closed doctrine
- `strand.md` — one plan ↔ one worktree ↔ one session; plan altitude
- `build-loop.md` — the watched-fail TDD cycle and review lifecycle
- `reviews.md` — checkpoint taxonomy, plan-review gate, golden samples
- `judgment.md` — triage → panel → ratify (policy only)
- `modes/` — solo, fleet, captain
- `acceptance/` — neutral acceptance rows, scenarios, mutation list
- `COVERAGE.md` — every source section mapped to its destination
- `scripts/` — the shared, provider-neutral MECHANISMS the law describes,
  called by every leaf so one behaviour cannot exist in two drifting copies.
  Currently `strand-lib.sh` (the strand death ritual: archive the strand's
  records out of its final commit, drop its completion marker from the base,
  reground the base plan, identify a marker's owning branch, prove a folder is
  in use). Everything here is git, the filesystem, and the process table —
  session registries, launch commands, and transcript formats stay in the leaf
  that owns them, and the neutrality lint enforces that line.
