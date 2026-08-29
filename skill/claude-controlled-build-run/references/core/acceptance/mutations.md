# acceptance/mutations.md — the mutation probe

Part of `cbr-core`. The premise "passes the checklist ⟹ safe" holds only if
the checklist is COMPLETE. Line count cannot prove that; the mutation probe
can:

1. **Every invariant gets a positive test AND a negative mutation** —
   re-introduce the scar and assert at least one **distinct** test goes red.
   A scar you can re-introduce with the suite staying green is a proven
   checklist gap — file it.
2. **Iterate the CHECKLIST first, then the skill.** Closing gaps is cheap
   (markdown); slimming the skill against an incomplete contract converges
   on a false contract. Stop when every scar has both a positive test and a
   red-on-mutation — then one full live run is the final acceptance.

## Mutation examples (each must turn a distinct test red)

Provider-mechanical mutations are described by role; each leaf's acceptance
names the literal flag/event/command being mutated.

- Swap the sanctioned prompt-removal launch flag for the half-mode that
  hangs on compound shell → F4b red.
- Add the ephemeral-session flag to a builder launch → F4a red.
- Launch the builder as the dispatcher's own shell child instead of
  supervisor-parented → F4b / scenario 4 red.
- Use the unrestricted sandbox / skip-hooks mode → F4b red.
- Change the TDD guard's host-agent setting to the OTHER harness → the
  leaf's B1 row red.
- Let the guard's version float instead of pinning → B1 red.
- Wire re-ground to the event that fires but cannot inject → C1 red.
- Drop one binding doc from the re-ground payload → C1 red (the anchored
  live-count grep).
- Paste a pointed-at contextual doc whole into the re-ground payload →
  C1 red.
- Drop the injection payload field so re-ground emits nothing → C1 red.
- Hardcode the plan path in re-ground (sibling leak) → A4 red.
- Remove branch scoping from the review clean-gate → A4 red.
- Delete the per-sha review lookup (crashes vanish from the list) → D3b red.
- Treat a daemon null as malformed instead of zero-open → D3b red.
- Remove the done-marker hash latch (stale marker false-fires) → G3 red.
- Arm the watcher without clearing the durable not-yet-watched marker →
  G4 red.
- Deny the checkpoint subagent's first command and let it return an
  empty/silent review → D7 red.
- Dispatch an unlocked stream without provision → F4 / scenario 1 red.
- Apply a larger model's absolute compaction threshold to a smaller-context
  model → C3 red.
- Make the archive-rename commit while its edits are unstaged (the stash
  trap) → I3 red.
- Add an auto-merge/auto-relaunch code path to a harness script → K1 red.
