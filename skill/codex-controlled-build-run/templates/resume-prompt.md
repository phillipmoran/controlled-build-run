Resume the existing controlled build from the next unchecked phase in the root
`task_plan.md`. You are already booted and the control plane is already armed. Do not
switch to a newer handoff, redo completed phases, or skip an unchecked phase.
Reconstruct facts from Git, the injected planning files, RoboRev, and the run
registry. If this is the same phase failure repeated beyond the configured
limit, write `NEEDS-HUMAN.md` with the crash evidence instead of looping.
