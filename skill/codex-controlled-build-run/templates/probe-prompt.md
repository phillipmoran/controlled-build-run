You are the Codex CBR harness operability probe. Do not begin product work and
do not commit. Prove the LIVE installed harness, then clean every probe file.

1. Run the repository's configured `toolchainProbe` command. Record its exit.
2. PROVE-NO: use the normal patch/write tool to add a tiny untested production
   function at a path matched by `probity.config.ts`. The PreToolUse hook must
   block it before the file changes. If it passes once, remove it and retry once;
   two consecutive unblocked writes means HARNESS-BROKEN.
3. PROVE-ADAPTER: repeat PROVE-NO at an untested production path matching
   `adapters/**/*.ts`. It must also be blocked before the file changes.
4. PROVE-PATCH: repeat the adapter attempt specifically through `apply_patch`.
5. PROVE-YES: after the real toolchain command, create and remove a trivial root
   scratch file outside guarded paths. This must succeed.
6. Confirm `git status --short` contains no probe artifact.

Report exactly one terminal line:

- `PROBE-RESULT: PROVE-NO BLOCKED / PROVE-ADAPTER BLOCKED / PROVE-PATCH BLOCKED / PROVE-YES OK`
- `PROBE-RESULT: PASS-WITH-NOTE — first production attempt passed, retry blocked`
- `PROBE-RESULT: HARNESS-BROKEN — <specific fact>`
