# judgment.md — resolving a judgment call: triage, then panel, then ratify

Part of `cbr-core`, the provider-neutral CBR law. This file is policy only —
how the leaf invokes its panel tooling is leaf content.

## Triage first

A question mid-build is not automatically a stop-and-ask. Triage it:

1. **Already settled, or trivial.** The plan, a contract, or the glossary
   already answers it — or it's a local code choice with no vision or scope
   weight. **Decide and move on.** Escalating a ruled question is its own
   drift.
2. **An engineering judgment call.** A real "how should this work" with no
   single right answer — a protocol shape, a payload schema, a data model, a
   tooling or agent-prompt design — but _inside_ the locked scope and
   contracts. **Run a multi-model panel and apply its recommendation**
   (subject to ratify, below).
3. **A vision or scope call.** A contract edit, a new top-level name, an
   out-of-glossary term, a scope change, or a genuinely new conflict the
   plan does not settle. **Goes to the human** — with the panel's
   recommendation attached so the call is informed, not raw.

## The panel recipe (fixed)

Run the leaf's pinned multi-model panel. Give it the agent entry doc, the
boot files (the binding principle docs and roadmap), the contract(s) the
question touches, and the glossary — but **not** the newest handoff (that's
a prior session's priorities, not this question). Frame it as **"How do the
best [matched experts] solve this successfully today? Do it that way."** —
match the expert to the question: game-economy / MMO leads for a
game-mechanic call, top agentic engineers for an agent / tool-call / prompt
call, senior software leads for a code-discipline call. Anchor on _success_,
not role: "how is this solved successfully" beats "your role is X" — the
success-framed prompt gets the better answer (ratified by the human,
2026-06-21).

## Who runs it

The orchestrator runs the panel — it owns the human seam and isn't mid-edit.
(In a solo build there is no orchestrator: the builder runs it itself —
`modes/solo.md`.)
A headless builder — and a solo builder running unattended — must **never
block on an interactive prompt** (a
builder once froze ~16 min waiting on an interactive question, and the
orchestrator cannot answer an app-modal dialog from outside). This is now
**enforced, not just advised**: a pre-tool hook denies the interactive
question tool on any headless builder branch and redirects to the file
channel. The channel:

1. The builder appends the question (+ a proposed default) to its plan's
   open-with-the-human section **and** drops the ask file (`ASK-ORCH.md`) at
   its worktree root (the fast signal): the question, which phase,
   `BLOCKING` or `PROCEEDING-ON-DEFAULT`, and the default it will assume if
   unanswered. Then it keeps building everything else.
2. The orchestrator polls the ask file + each plan's open-with-the-human
   section every watch tick (tightening cadence while any ask is open),
   triages per the buckets above, and answers back via the answer file
   (`ORCH-ANSWER.md`) at the builder root + the plan's decision log (running
   the panel first for a bucket-2 call).
3. The builder consumes the answer at its next resume/reground, or reads the
   answer file before it would block. The ask file is the light "answer me
   and I keep going" seam; the needs-human marker and the control-plane-broken
   marker stay the terminal blockers.

## Ratify

A bucket-2 answer is applied directly — _except_ when it would change a
ratified contract, the test rig, or the locked scope. Those still take
the human's yes/no, panel recommendation attached. The panel informs the
call; it never replaces the human on vision or scope.
