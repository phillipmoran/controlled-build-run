# STATUS.md — <branch> (<stream or solo>)

state=<building|blocked|done>
phase=<current phase id>
branch=<branch>
worktree=<absolute path>
blocked_on=<none|what>
open_asks=see <ask file> (newest at top); none blocking this build
last_phase_complete=<phase id>
updated=<YYYY-MM-DD>

## What this file is, and what it deliberately is not

The OUTSIDE observer's surface: the four or five facts an orchestrator, a
orchestrator, or a dashboard needs at a glance to tell an active strand from a
stalled one. It is the only file that carries them in this form, so they live
here and nowhere else.

Everything else lives in exactly one OTHER file, and this one links rather than
restates — the single-source rule (`build-loop.md`), and the reason this file
is short:

- **Decisions, scope, phases, the endgame chain** → `task_plan.md`
- **The running narrative, the readback, per-phase evidence** → `progress.md`
- **Durable findings, ledgers, reconciliation tables** → `findings.md`
- **Open questions and the defaults being proceeded on** → the ask file
- **Answers** → the answer file
- **Human-only decisions, parked and not blocking** → `NEEDS-OPERATOR.md`
- **Completion latch** → `DONE-<branch>.marker` (per-branch name; absent until the handoff)

A phase table copied to here would be a second place for the plan's checkboxes
to be wrong, which is the failure the single-source rule names. The same
reasoning is why `open_asks` names the FILE and not the asks: a list here
drifts behind the ask file within a day, and whoever reads this one to decide
what needs answering would miss a parked question entirely. `blocked_on` is
the field that says whether any of them stops the build; the asks themselves
are read where they are written.
