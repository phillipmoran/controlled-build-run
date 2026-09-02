# Roadmap

Near-term, in rough order. None of this is shipped yet — the README only
claims what exists.

- **Coverage audit** — a doctor check that compares the extensions a repo
  carries against the gates actually wired, and reports the gap. Advisory
  in `cbr-doctor` when built: it can be wrong about intent, so it surfaces,
  never blocks.
- **More harness adapters** — Claude Code and Codex ship today. Adapters
  for other runtimes are wanted; see the "Request a harness adapter" issue
  template, or build one from the porting docs (~30 files).
- **Marketplace listing** — submit the plugin to community and official
  Claude Code marketplaces once the repo is public.
- **Fold planning-with-files into CBR's own templates** — CBR now owns the
  plan format (`task_plan.skeleton.md`), the stop gate, and the re-ground;
  what remains of the vendored skill is the idea plus a Stop hook that
  needs an awkward user-level install. Retire it cleanly, keep the credit.
- **Update path hardening** — today updating a vendored package is a
  re-vendor + re-run of setup (see UPDATING.md); a proper migration flow
  that diffs operator-adapted configs against new templates is wanted.
- **Codex guard parity** — the control-plane guard ships on the Claude
  Code leaf only, because Codex has no PreToolUse-shaped hook to hang it
  on. Find the nearest equivalent, or document the gap per harness.
- **Guard hardening** — the guard is a bar, not a vault: it pattern-matches
  the direct disarm idioms. Known gaps worth closing as they are found
  (indirection through scripts the agent writes, editing the gate configs
  to no-ops, which stay unguarded by design). Each closed gap gets a fixture.
