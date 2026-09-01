# Shared-core and Codex-leaf conformance

`skills/cbr-core/` is the reviewed source of provider-neutral law. An
installed or exported Codex leaf carries a byte-exact generated snapshot at
`references/cbr-core/` (materialized at kit export) so it remains
self-contained; the canonical repository carries no checked-in snapshot and
the leaf reads `skills/cbr-core` directly.

Run `scripts/tests/conformance.py`. It resolves the canonical core from an
explicit argument, else a `skills/cbr-core` ancestor, else the embedded
snapshot. What it enforces:

- when BOTH an embedded snapshot and an independent canonical core are
  present: identical file sets and bytes between them. (An installed leaf
  with no reachable canonical core has only its snapshot — internal checks
  below still run, but byte-exactness is only provable against a canonical
  source; pass one explicitly to prove it.)
- the strong-law sentence set required by shared acceptance P2;
- no provider primitive in core and no other-provider primitive in the
  Codex leaf;
- explicit Codex hook, patch, persistence, sandbox, approval, compaction,
  and registry mechanisms in the leaf;
- a short `SKILL.md` router that names every required component.

The coverage-map, source-inventory, Git-history, and leaf-row-equality
checks were retired 2026-08-31 with the archived extraction ledgers
(docs/archive/cbr-acceptance/ in the source repo). Do not restore a
percentage-length or source-text similarity threshold.
