---
name: cyclomatic-complexity
description: Refactor code to reduce cyclomatic complexity so it stays readable, maintainable, and aligned with the long-term vision of the codebase, not just optimized for AI comprehension. Use whenever the user asks to refactor, simplify, clean up, or review code quality; mentions complexity, maintainability, readability, spaghetti code, deeply nested logic, or god functions; or asks to check AI-generated code before merging. Also use proactively after writing any nontrivial function with heavy branching.
---

<!--
  VENDORED. Upstream: github.com/saurabhkumar8112/cyclomatic-complexity-skill
  branch master, commit 567886f485063c5f5f94503d5712ef75cbcbbd94,
  path skills/cyclomatic-complexity/SKILL.md. License: Apache-2.0.
  Fetched and reviewed 2026-08-27.

  Patched for CBR (this repo's copy is now canonical; the upstream file is
  pinned by the sha above, not tracked here):
    (a) the upstream threshold line "15+" prescribed splitting with no
        alternative; it is replaced by the two-move rule below, which gives an
        exemption exit so the deterministic gate always has a one-step way out.
    (b) a CBR header was added, describing where the gate fires and how this
        skill reaches a builder. The paragraph on what an exemption's reason
        clause must contain is CBR text and lives there with it, never inside
        an upstream section.
  The threshold bullet's boundary was also corrected from the upstream "15+" to
  "16+": the bar here is <= 15, so a function at exactly 15 passes.
  Everything else — the measurement rules, the refactor tactics, the hard
  rules, the workflow, the output format — is upstream text, kept intact.
-->

# Cyclomatic Complexity

Purpose: AI-written code often works but branches like a jungle. This skill: measure complexity, refactor hotspots, keep code human-maintainable.

## How this works in a controlled build run

The bar is **cyclomatic complexity ≤ 15 per function**, and it is a
deterministic gate: the host's lint layer measures it and **pre-commit blocks
the commit** when a function is over. It is not advice you may weigh — it is a
fact that stops the commit, exactly like a type error.

This skill is injected into a builder's context **at build start, and
re-injected mid-build after every compaction**, the same way the TDD skill is.
That is deliberate: the gate fires at commit time, which is the worst moment to
first learn the rule, so the rule travels with you instead.

The gate has a deterministic exit (the two-move rule below), so it can always
be satisfied in one step. What is **not** deterministic is whether an exemption
was *earned* — the per-commit reviewer reads the exemption comments in the diff
and judges them. That judgment **surfaces and never blocks**.

The reason clause is not decoration. It is the whole content of move (b): a
comment that says nothing ("complexity") tells the next reader only that
somebody was in a hurry, while one that says *why the branching is essential*
("state machine — each case is a distinct protocol transition") is the argument
the reviewer is there to judge.

## Measure first

CC = decision points + 1. Decision points: `if`, `else if`, `case`, loops, `catch`, ternary, `&&`, `||` in conditions.

Project linter config wins. If eslintrc, radon config, sonar config, or similar sets a complexity threshold, use that. No config: use defaults below.

Thresholds:
- 1-5: fine, leave alone
- 6-10: watch, refactor if touching anyway
- 11-15: refactor now
- 16+: over the bar — the two-move rule applies

### The two-move rule

A builder over the bar has exactly two moves, each ending the block in one
step: (a) refactor under 15, or (b) exempt with
`// eslint-disable-next-line complexity -- <one-line reason>`. Law: **one
refactor attempt, then decide.** Never fragment a coherent function just to
beat the number. The reviewer judges exemption comments in the diff — advisory
only.

Prefer real tools over eyeballing when environment allows:
- Python: `radon cc -s -a <path>`
- JS/TS: eslint `complexity` rule
- Go: `gocyclo`
- Polyglot: `lizard <path>`

No tool available: count manually, per function, show the count.

Two tools will disagree on the same function — `lizard` and the eslint
`complexity` rule count differently, and both are defensible. The tool that
GATES is authoritative: whichever one blocks the commit is the number you have
to get under. Where they differ, record both. A disagreement is information
about the shape of the function, not a tie to break by preference.

## Refactor tactics, in order of preference

1. **Guard clauses.** Invert conditions, return early, kill nesting.
2. **Extract function.** Each extracted piece gets a name that says what, not how. Names are documentation.
3. **Lookup table / map** instead of if-else or switch chains.
4. **Named predicates.** `if (isEligibleForRefund(order))` beats a 4-clause boolean soup.
5. **Polymorphism / strategy** for switch-on-type. Only when the switch appears in 2+ places.
6. **Flatten loops.** Extract loop body, use continue instead of nested if.

## Hard rules

- Preserve behavior. Run tests before and after. No tests: say so, suggest adding, refactor conservatively.
- Don't game the metric. A dense one-liner hiding 6 branches is worse than the honest if-chain it replaced. Complexity should move into well-named units, not disappear into cleverness.
- Don't break public APIs or exported signatures without asking.
- Small functions with clear names > few functions with comments explaining sections.
- One responsibility per function. If the name needs "and", split.

## Workflow

1. Measure all touched functions, rank by CC descending.
2. Report hotspots with numbers before touching anything.
3. Refactor worst first, one function at a time.
4. Re-measure. Show before/after table: function, CC before, CC after.
5. Verify: tests pass, behavior unchanged, diff reviewable.

## Output format

End every refactor with:

```
## Complexity report
| Function | Before | After |
|----------|--------|-------|
| parseOrder | 14 | 4 |

Extracted: validateHeader, resolveDiscount
Behavior verified: <how>
```

Keep prose minimal. Numbers and diffs do the talking.
