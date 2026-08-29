# Shared-core and Codex-leaf conformance

`skills/cbr-core/` is the reviewed source of provider-neutral law. This leaf
carries a byte-exact generated snapshot at `references/cbr-core/` so an installed
or exported Codex skill remains self-contained.

Run `scripts/tests/conformance.py` in an installed/exported leaf. In the
canonical the reference host source repository, run
`scripts/tests/conformance.py --canonical-source-repo skills/cbr-core` so the
declared pre-conversion commit/path/hash is also checked against Git history.
The history check is explicit because a portable target may reproduce every
source path and repository marker without carrying the reference host's Git objects.

Both modes enforce:

- identical shared-core file sets and bytes;
- coverage-map dispositions that tile every nonblank source-law line, with no
  pending row and no missing mapped file;
- a Codex-source destination inventory that tiles the former long router and
  requires a surviving witness for every provider-mechanical concern;
- the strong-law sentence set required by shared acceptance P2;
- no provider primitive in core and no other-provider primitive in the Codex
  leaf;
- explicit Codex hook, patch, persistence, sandbox, approval, compaction, and
  registry mechanisms in the leaf;
- a short `SKILL.md` router that names every common/mode/acceptance component;
- exact equality between shared `leaf-row` IDs and the Codex mechanical
  acceptance rows.

The semantic coverage map replaces line-count similarity. Do not restore a
percentage-length or source-text similarity threshold.
