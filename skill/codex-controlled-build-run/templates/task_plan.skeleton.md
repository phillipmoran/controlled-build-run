# task_plan.md — <WORKSTREAM>

**Branch:** stream/<slug>  
**Run type:** workstream  
**Worktree:** <absolute worktree path>

## Goal and observable exit

<What exists for a user or caller when this strand is complete?>

## Scope locked at dispatch

- In: <owned behavior and files>
- Out: <explicit exclusions>
- Contract authority: <binding files/sections>

## Probity-exempt zones

<!-- Every exemption names a substitute proof. No row means no exemptions. -->

| Zone | Why TDD cannot directly guard it | Substitute proof |
| ---- | -------------------------------- | ---------------- |
| none | —                                | —                |

## Build phases

<!-- Each phase is decision-dense and implementation-sparse: observable result,
watched red, locked choices, owned files, and verification command. -->

- [ ] P0 — Control-plane operability: doctor plus live prove-NO/prove-YES.
- [ ] P1 — <observable result>; red: <test>; locks: <decisions>;
      owns: <files>; verify: `<command>`.

## Verification commands

- `<focused test>`
- `<full deterministic gate>`
- `<real entry-path smoke when applicable>`

## Phase checkpoint ledger

| Phase | end_sha | reviewed | result  | evidence |
| ----- | ------- | -------- | ------- | -------- |
| P0    | pending | pending  | pending | pending  |
| P1    | pending | pending  | pending | pending  |

## Open with human

<!-- A headless builder writes the fork, recommendation, and safe default here,
then continues independent work. It never waits on interactive input. -->

None.

## In-flight decision log

| Date | Decision | Evidence/rationale |
| ---- | -------- | ------------------ |
