# policy.md — the laws, the checks, and where each fires

Part of `cbr-core`, the provider-neutral CBR law. A harness leaf supplies the
mechanisms (tool names, flags, file paths); this file supplies the law those
mechanisms exist to enforce.

## What a controlled build gives you

A build that runs off a **written plan**, with **automatic checks** and
**drift-proof hooks**, so even a long or unattended run stays honest. The plan
holds the decisions; the checks catch mistakes; the hooks re-ground you when
your memory gets squished. None of it depends on you *remembering* to be
disciplined — the harness does that.

Two jobs, in order: **(1) verify/wire the harness**, then **(2) run the loop**.

## The shape — the checks and where each fires

| Check | Fires | What it does | Can it block? |
|-------|-------|--------------|---------------|
| **Probity** | before every write/edit | enforces TDD (no prod code before a watched-fail test) + naming rules | yes — blocks the write |
| **no-interactive-ask** | before an interactive question on a headless builder | denies it + redirects to the file-based ask channel (a headless builder freezes on an interactive prompt) | yes — blocks the tool |
| **pre-commit** (format + lint + types + tests) | on every commit | deterministic facts: format, lint, types, tests | yes — blocks the commit |
| **complexity ceiling** | on every commit (in pre-commit) | deterministic fact: a changed function branches past the bar the host lint layer sets | yes — blocks the commit, with a deterministic exemption exit |
| **RoboRev** | after each commit | LLM review of the diff; surfaces findings | no — advises only |
| **review-clean gate** (in pre-commit) | on every commit | deterministic fact: this branch has an open / queued / running review | yes — blocks the commit until every review is responded + closed |
| **checkpoint review** | at each phase boundary | cross-artifact consistency check of the phase's diff (contract vs code vs roadmap) | no — advises; load-bearing fixed before the next phase |
| **surfacing hooks** | session start + after compaction | list open FAILs; re-inject the rules + plan | no |

Each layer catches a different *class* of error: deterministic checks catch
mechanical slips, RoboRev catches bugs in a single diff, and the checkpoint
review catches contradictions *across documents* that no single-diff check can
see.

The principle behind "can it block": **deterministic facts may gate; fallible
judgment may only surface.** A type error is a fact, so it blocks. An LLM
reviewer can be wrong, so it advises and you decide — never let it force
action.

Two hook *systems* are involved, and the harness uses both:

- **Agent-harness hooks** — fire around *the agent's* actions: a pre-write
  hook runs Probity (plus the interactive-ask guard on headless builders), a
  post-commit surface wakes the agent on a review FAIL, and a session-start
  hook sweeps open FAILs (always) **plus** re-grounds the agent when the
  session started from a compaction. The leaf documents which of its hook
  events can actually inject context — wire the re-ground into one that can,
  not into a log-only event.
- **Git hooks** — fire around *repo* events: pre-commit runs the
  deterministic checks; post-commit and post-rewrite trigger the RoboRev
  review.

## Fail open on your own infra; fail closed on what you observed

Every hook script must **fail open on its own infra**: if the hook's *own*
tool is missing or unreachable, exit silently rather than blocking work —
guardrails catch mistakes, they don't halt the line. This is **not** licence
to wave past a failure the hook *observes*: a review that crashed is an
observed fact (the commit went unreviewed), so the deterministic review-clean
gate fails **closed** on it and blocks until it is re-run. The line to hold:
"my own tool broke" → fail open; "the thing I was checking failed" → fail
closed.

**One deliberate exception: the pre-write enforcement guard itself fails
closed on its own infra.** If Probity's judge, config, or load path breaks,
the write is blocked (a violation), never waved through — a blocked builder
surfaces loudly and gets fixed, while a silently unguarded run is
undetectable and lets untested production code into the tree. Fail-open is
for *surfacing* hooks, whose failure costs you a notification; the
*enforcement* gate's failure costs you the guarantee, so it fails closed.

## The complexity ceiling and its two moves

A function that branches past the bar is a deterministic fact, so it gates —
but a gate with only one way out is a gate that gets fought. The rule that
makes it livable: a builder over the bar has exactly **two moves, each ending
the block in one step** — (a) refactor under the bar, or (b) exempt the
function with the host lint layer's suppression comment, carrying a one-line
reason. Law: **one refactor attempt, then decide.** Never fragment a coherent
function just to beat the number; a metric gamed into three meaningless helpers
costs more than the branching it hid.

The exemption is what keeps the fact honest. Some functions are irreducibly
branchy — a protocol state machine, an exhaustive dispatch — and a ceiling with
no exit either blocks them forever or teaches builders to write dishonest
code. So the *count* gates and the *reason* does not: the per-commit reviewer
reads the exemption comments in the diff and judges whether each was earned,
and that judgment surfaces, never blocks (the same split as everywhere else in
this file — deterministic facts may gate; fallible judgment may only surface).

The bar's number and the tool that measures it are host content: a project sets
them in its own lint layer, and this law names only the check class.

## Test tiers — the per-commit gate stays seconds

The per-commit test hook exists to run dozens of times a day, so its budget
is seconds, not minutes. Tests come in tiers: **small** tests ride every
commit; **slow suites** (live smokes, end-to-end regressions) run at the
**gate tier** — armed *mechanically* at merge commits and on changes to
their own subject, never by a person remembering a flag. A tier move must
stay visible: a gate-tier test reports as an explicit skip in the ordinary
run, so an unarmed tier can never be mistaken for a passing one.

**A slow test is a defect in the test, never a reason to lose the test:
move it to the correct tier, do not delete it, do not let it quietly price
every commit.** Enforcement is deterministic where the host wires it — a
test-time budget check reading the runner's own timing report against a
human-owned budget config (WARN-first; the blocking flip is a ratification,
like any gate) — and binds by review until then. The budget numbers, the
runner, and the report format are host content; this law names only the
tiers and the rule.

## Name shared things neutrally

A name is a claim about scope. Anything shared across harnesses — a config
dial, a script, a gate, a doc — gets a **neutral name**; a harness's or
vendor's name belongs in a name **only when the thing is truly specific to
that harness**, and then the name should say so honestly. A shared artifact
wearing one harness's name misleads every future reader into thinking it
belongs to that harness alone — the confusion costs more than the rename.
When you find one already misnamed, don't rename it mid-strand: flag it as a
follow-up candidate at closeout.

## Compact late, on your own terms

Compaction is the single most dangerous moment of a long build: working
memory gets squished and only the re-ground hook stands between you and
drift. So every CBR session — orchestrator and builders alike — configures
its context compaction to fire as LATE as the model allows (fewer compactions
per build means fewer chances to drift), with a threshold that fires it with
headroom, on your terms, never as an emergency at the window edge. The
concrete window and threshold values are leaf content (they are set in the
harness's settings and checked by the leaf's doctor command); the law here is
the dial's direction. This does NOT replace the re-ground hook below — it
just makes it fire less often.

## The re-ground hook is the most important one to get right

When your context is compacted, your memory of *what you were doing* is what's
most at risk. The post-compaction re-ground hook re-injects, whole:

- the project's **binding principle docs** (constitution/engineering-level),
- the **top-level routing doc** (the repo's agent entry map),
- **the CBR process text itself** when a build plan exists — so the *process*
  (the TDD loop, the phase checkpoints, the review close-discipline) survives
  the compaction too, not just the rules. A pointer would rely on the drifted
  agent choosing to re-read it; the whole point of the principles being pasted
  is that they aren't, so the process text is pasted on the same logic.
- **the active plan** (`task_plan.md`) — so a post-compaction you re-reads
  the plan and continues from the current phase instead of drifting.

The note also tells the agent it has **already booted and already set up the
harness**, so it continues from the plan and does **not** re-run the boot
ritual, switch to a prior handoff, or re-verify/re-wire the hooks. Larger,
contextual documents (glossary, contracts) are *pointed at*, not pasted.
Verify the hook points at **this run's plan file** (`task_plan.md` at the
worktree root — the path the planning skill always uses).

## Verify before you wire (CHECK BEFORE YOU CLOBBER)

Most harness pieces already exist in an established repo. For each piece:
check if it's present first. If it is, confirm it matches the spec and move
on — do not blindly overwrite a working hook. Only install what is missing or
wrong. The six pieces, generically:

1. **The planning skill** is available (the plan lives in `task_plan.md`).
2. **Probity** — its config at the repo root + the pre-write hook that runs it.
3. **RoboRev** — its config at the root + the git post-commit/post-rewrite
   hooks + the post-commit surface that wakes the agent on a FAIL.
4. **Session sweep** — the session-start hook that lists open FAIL reviews at
   boot.
5. **Pre-commit checks** — the deterministic gate config present (format
   check alongside lint/types/tests, **and the review-clean gate**), and the
   git hook actually installed. This is the piece most often
   present-but-not-armed — check the installed hook file itself. The git hook
   is generic and shared across worktrees; what makes the review-clean wall
   *fire* is the branch carrying both tracked files, so a branch cut from a
   main that predates the gate runs without it (cut builder branches from a
   base that already contains the gate — which base is the mode's call; see
   the gate-inheritance law in `modes/`).
6. **Post-compaction re-ground** — wired into a hook event that can actually
   inject context (see above). **This is the lifeline of a long run.**

## The model dial — the principle

Each layer of the process (orchestrator, builders, per-commit reviewer,
review subagents, the TDD guard's judge) runs on an explicitly chosen model
tier, pinned in ONE place per layer — the leaf's dial — so a tiering change
is one edit, not a hunt. The savings come from the tier split — judgment on
the frontier tier, build volume one tier down, review another tier down —
never from cutting effort or skipping review. Correctness still outranks
token cost. Two riders that are law, not leaf detail: review runs on a
DIFFERENT model family than the one that wrote (a cross-family reviewer
doesn't share the author's blind spots, and doesn't compete for the same
usage window); and every dispatched session states its model and effort
explicitly at launch — inheritance is how builders silently boot on the
wrong tier. The concrete pins, model names, and effort values are leaf
content.

## The honest gap this process closes

Without it, the plan and the checks are two separate things stitched together
by hand: the agent has to *remember* to run the checks, *remember* to commit
often, and *remember* that the plan should survive compaction. The harness
does that work — verify it once, then the hooks fire on their own and the
plan re-grounds you automatically.
