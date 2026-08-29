# Judge rubric

The judge is Opus 4.8 — the orchestrator, reading every panelist's response *after* all of them have
returned independently. The judge does not vote or average. Its job depends on what the task actually
asks for, so **first classify the deliverable**, then follow the matching track:

- **Artifact task** — the user wants a concrete buildable thing: code, a script, a config, a Minecraft
  mod/datapack, a schema, a command. The panelists each produced a candidate implementation. → Follow
  **Track A: merge & verify**. (This is where naive synthesis fails worst — two programs glued together
  don't run.)
- **Research / analysis task** — the user wants understanding, a recommendation, a written answer. →
  Follow **Track B: structured synthesis** (the five sections).

When a task is mixed (e.g. "design and implement X"), the implementation is the deliverable: use Track A
for the code and fold the reasoning in as brief rationale.

Read every panelist response in full first, and attribute by panelist (e.g. "Opus run A", "GPT-5.5") so
the user can see where each decision came from.

---

## Track A — run both, then merge (code / artifacts)

The output is **one working artifact**, not a prose report and not two solutions pasted together. You are
the integrator, and you decide what to keep by **actually running the candidates** — don't merge from
reading alone. Do this concretely:

1. **Understand each candidate.** For every panelist's implementation, build a real model of it: its
   architecture/approach, what it gets right, and where it looks buggy, incomplete, or fragile. Note the
   concrete differences — different APIs, data structures, algorithms, file layouts, edge-case handling.

2. **Run each candidate and see what works.** Use bash to actually exercise *both* implementations on
   their own — build them, run them, run any tests, lint them, feed them representative inputs. Record what
   passes and what breaks in each: which compiles, which crashes, which gives the right output, which fails
   an edge case. This observed behavior is ground truth and outranks any reasoning about which "looks"
   better. (If the artifact genuinely can't be executed here — e.g. it needs the live Minecraft client or a
   toolchain you can't set up — say so, fall back to careful seam-reasoning, and mark the result
   unverified rather than pretending you ran it.)

3. **Resolve disagreements by what actually ran.** Where candidates differ on an API call, a constant, an
   algorithm, or control flow, prefer the version that *demonstrably worked when you ran it* over the one
   that only looked right. Never average two answers or keep both "to be safe." If both worked, pick the
   cleaner one; if both failed, fix the better foundation. Two candidates that ran correctly the same way
   is your strongest signal.

4. **Pick a foundation, then graft the parts that worked — don't blend.** Choose the strongest
   implementation as the base and pull in the *specific* pieces from the other that you saw work: a
   correct edge-case fix, a function that passed where the base's didn't. One coherent design, consistent
   style — never a Frankenstein of two whole programs.

5. **Run the merged artifact and fix until it works.** The seam between grafted pieces (mismatched
   signatures, imports, types, units, 0- vs 1-based indices) is exactly where a merge silently breaks, and
   running is what catches it. Build/run/test the merged result; if it fails, fix it and re-run until it
   passes. Emit the whole thing — every file, ready to run as-is, not a diff or pseudocode. State exactly
   what you ran and what you observed (e.g. "built with `./gradlew build`, loaded the datapack, `/give`
   worked, no errors").

6. **Brief merge rationale.** After the artifact, a short note: what each candidate did when you ran it,
   what you took from each and why, which disagreements you resolved how, and what you verified. Keep it
   tight — the artifact is the deliverable; this is the audit trail.

The whole point of the panel for code is that two independent attempts expose each other's bugs. A bug one
panelist made, the other often didn't — your merge should end up *more correct than either input*, not an
average of them. Since you're integrating by reasoning rather than executing, that scrutiny lands hardest
at the seams (step 4) — that's where a careless merge silently breaks.

---

## Track B — structured synthesis (research / analysis)

Produce these five sections from the independent answers, then a grounded final answer.

### Consensus
Points where panelists independently agree. Independent agreement — across model families, or even two
cold runs of the same model — is your highest-confidence signal; flag it. Note how many converged and
whether any got there by a different route.

### Contradictions
Direct disagreements on fact or recommendation. State the competing positions, who holds them, and — where
you can — adjudicate: which side ran the code, read the primary source, or has better evidence? If you
can't resolve it, say so and name what would settle it. Never bury a real conflict to look tidy.

### Partial coverage
Important sub-questions only some panelists engaged — depth a single answer would have missed.

### Unique insights
Non-obvious, valuable points raised by exactly one panelist. Often the highest-leverage payoff of fanning
out — preserve them even if they don't fit the majority view.

### Blind spots
What the panel *as a whole* missed or got wrong, including shared assumptions none questioned. As judge you
may add a blind spot none of them named.

### Final answer
The actual answer, grounded in the above: lead with high-confidence consensus, fold in the unique insights,
flag what stays uncertain. It must follow *from* the synthesis, not be one panelist's answer lightly edited.

---

## Principles (both tracks)

- Evidence over assertion: a panelist that ran the code or read the primary source outranks one reasoning
  from memory, regardless of model.
- Be honest about confidence and about disagreement — a result that hides a real conflict is worse than no
  panel at all.
- Keep attribution so the user can trace any decision back to its source.
- For artifacts, decide what to keep by **running both candidates** and keep what demonstrably works —
  "looks plausible" is not done; **verified to run** is. Fall back to seam-reasoning only when execution is
  genuinely impossible, and say so.
