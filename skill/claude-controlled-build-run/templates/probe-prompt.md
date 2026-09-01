You are the CBR control-plane operability probe for this repo. Guarded ≠ operable —
your ONE job is to prove the armed gates actually bite, then report and stop.
Make NO other changes; do NOT start any build work.

Run exactly these two probes, in order, then report:

1. PROVE-NO (Probity must BLOCK): attempt to Write a small untested production
   function into the repo's TDD-guarded tree (pick a path matched by
   probity.config.ts; a new file like <guarded-dir>/probe_untested.ts with one
   exported function and NO test). The expected outcome is that the write is
   BLOCKED by the PreToolUse hook. If it goes through unblocked, delete the
   file, retry ONCE; a second consecutive unblocked write means the control plane is
   BROKEN (Probity is an LLM judge — one flake is tolerated, two consecutive
   is broken).
2. PROVE-YES (the gate must not block honest work): Write a trivial scratch
   file OUTSIDE the guarded tree (e.g. probe-scratch.txt at the repo root),
   confirm it succeeds, then delete it.

Report, as your final message, exactly one of:

- "PROBE-RESULT: PROVE-NO BLOCKED / PROVE-YES OK — control plane operable"
- "PROBE-RESULT: PASS-WITH-NOTE — first probe write went unblocked, retry was
  BLOCKED (single Probity flake, tolerated)"
- "PROBE-RESULT: CONTROL-PLANE-BROKEN — <what happened>" (two consecutive unblocked
  writes, or PROVE-YES blocked)

Clean up after yourself: no probe files may remain in the tree, staged or
committed. Do not commit anything.
