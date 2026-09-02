# Updating a vendored CBR package

A repo armed by CBR carries its own copy of this package. Updating it is a
re-vendor, not a `git pull`:

1. Read this repo's `CHANGELOG.md` for what changed since your `VERSION`.
2. Replace the vendored `controlled-build-run/` folder with the new package.
   On Claude Code the control-plane guard denies an agent's edits to the
   installed hooks and settings, so run the re-vendor and the re-arm from
   an operator session started with `CBR_CONTROL_PLANE_UNLOCK=1` in its
   environment (or do it from a plain shell).
3. Re-run your harness installer (`cbr.sh arm` / `cbr-codex.sh arm`; it
   creates what is absent and reports what it will not touch) and merge by
   hand for anything you adapted: your filled
   configs (`probity.config.ts`, `.pre-commit-config.yaml`, `.roborev.toml`)
   and installed hooks may lag new templates. Diff template against
   installed copy; merge, don't blind-overwrite — in either direction.
4. Re-run the proof: package doctor plus the prove-NO / prove-YES probes.
   An updated repo that fails a probe is not armed, whatever changed.

Stack drift works the same way in miniature: when the repo itself changes
(new language, new test runner), the templates are fine but your filled
configs are stale — re-run detection for the affected config and re-prove.
