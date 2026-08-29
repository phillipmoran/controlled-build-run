Run `$codex-controlled-build-run` from this worktree and execute the root
`task_plan.md` to completion. The plan and its cited contracts are the only
authority; do not silently widen scope or redesign locked decisions. Touch
nothing outside this worktree. First run `cbr-codex.sh doctor` and the live
Probity prove-NO/prove-PATCH/prove-YES operability probe; stop with
`HARNESS-BROKEN.marker` if either is not proven. Use watched-fail TDD for every guarded behavior,
commit small with the plan checkbox in the same commit, close every RoboRev
review, and stamp every phase checkpoint.

This is a non-interactive persistent Codex builder. Never request UI input.
Write questions with your recommendation and safe default to `ASK-ORCH.md` and
continue independent work. Recover only from Git, the planning trio, and the
recorded Codex thread. Do not rerun harness boot after compaction. Finish by
committing `DONE.marker` containing the final commit, verification evidence,
and review state. If safe progress is impossible, write `NEEDS-HUMAN.md` or
`HARNESS-BROKEN.marker` with exact evidence and stop.
