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
- **Update path hardening** — today updating a vendored package is a
  re-vendor + re-run of setup (see UPDATING.md); a proper migration flow
  that diffs operator-adapted configs against new templates is wanted.
