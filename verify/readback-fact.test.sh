#!/usr/bin/env bash
# Regression for the readback fact (cbr.sh readback, surfaced in cbr.sh status):
# core law says a dispatched builder restates mission/scope/OUT in progress.md
# before it builds, and the dispatcher checks it. PRESENCE is a mechanical fact
# and may be reported; faithfulness is judgment and must never be gated on — so
# this proves the fact is honest (a bare heading is not a readback) and that it
# never fails the caller.
set -euo pipefail

for v in $(env | sed -n 's/^\(GIT_[A-Z_]*\)=.*/\1/p'); do unset "$v"; done

cbr="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/skills/claude-controlled-build-run/scripts/cbr.sh"
[ -x "$cbr" ] || cbr="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/skill/claude-controlled-build-run/scripts/cbr.sh"
tmp="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
fail() { echo "readback-fact.test FAIL: $1" >&2; exit 1; }

mkdir -p "$tmp/full" "$tmp/heading-only" "$tmp/none" "$tmp/no-file" "$tmp/late"

cat > "$tmp/full/progress.md" <<'EOF'
# progress

## Readback

Mission: make the exporter's output depend only on the exported bytes.
Locked scope: kit/** and skills/** only.
OUT: packages/** (a sibling builder owns it), any push.

## Work
EOF

# A heading with nothing under it is the failure this fact exists to catch: an
# agent that types the ritual word and skips the thinking looks identical to one
# that did the work, unless the check demands substance.
cat > "$tmp/heading-only/progress.md" <<'EOF'
# progress

## Readback

## Work
started
EOF

cat > "$tmp/none/progress.md" <<'EOF'
# progress

## Work
started straight in
EOF

# Case-insensitive, and not required to be the FIRST heading in the file: a
# builder that writes its readback after a probe note has still done the thing.
cat > "$tmp/late/progress.md" <<'EOF'
# progress

## Harness probe
prove-NO denied a guarded write.

### READBACK (plan)
Mission: restated.
Scope: kit/** + skills/**.
OUT: packages/**.
EOF

# The shape this repo's own builders write: the heading begins with the word and
# then explains itself. A word cap rejected exactly this, which is how the cap
# was found to be the wrong rule.
mkdir -p "$tmp/self-describing"
cat > "$tmp/self-describing/progress.md" <<'EOF'
# progress

### Readback (mission, scope, OUT — in my own words)
Mission: make the exporter deterministic.
Scope: kit/** + skills/**.
OUT: packages/**, any push.
EOF

# The law asks for three NAMED things (mission, locked scope, OUT list), so a
# builder writing them as sub-headings is following it to the letter. Anything
# that calls that MISSING slanders a compliant builder.
mkdir -p "$tmp/subheads" "$tmp/mentions" "$tmp/fenced"
cat > "$tmp/subheads/progress.md" <<'EOF'
# progress

## Readback

### Mission
Make the exporter deterministic.

### Locked scope
kit/** and skills/**.

### OUT
packages/**, any push.

## Work
EOF

# A journal that DISCUSSES readbacks is not a readback. This file is the shape
# this very repo produces once the builder writes up the phase — if it passes,
# the fact reports present for a progress.md whose actual readback was deleted.
cat > "$tmp/mentions/progress.md" <<'EOF'
# progress

### P-C — readback + zero-context-plan laws (core law + one leaf mechanism)

Both laws landed in the shared core, mirrored to the leaf, lint green.
The leaf mechanism reports presence only.
EOF

# A readback heading quoted inside a fenced block is documentation about the
# format, not a builder restating its plan.
cat > "$tmp/fenced/progress.md" <<'EOF'
# progress

Template we hand builders:

```
## Readback
Mission: ...
Scope: ...
OUT: ...
```

## Work
EOF

# A readback whose only substance is a quoted template is not a readback — the
# builder pasted the format instead of filling it in. Fenced lines are excluded
# everywhere, including UNDER a valid heading, or the exclusion is a half-rule.
mkdir -p "$tmp/fenced-body"
cat > "$tmp/fenced-body/progress.md" <<'EOF'
# progress

## Readback

```
Mission: ...
Scope: ...
OUT: ...
```

## Work
EOF

# Tilde fences are as valid as backticks in Markdown, and a rule that knows only
# one of them is a rule a builder trips over by accident.
mkdir -p "$tmp/fenced-tilde"
cat > "$tmp/fenced-tilde/progress.md" <<'EOF'
# progress

## Readback

~~~
Mission: ...
Scope: ...
OUT: ...
~~~

## Work
EOF

# CommonMark: a fence closes only on a run of the SAME character at least as
# long as the opener, so a shorter marker inside a longer fence is content. A
# detector that closes on any marker re-opens the block halfway through and
# starts counting the template as substance.
mkdir -p "$tmp/fenced-long"
cat > "$tmp/fenced-long/progress.md" <<'EOF'
# progress

## Readback

````
Here is how a readback looks:
```
Mission: ...
Scope: ...
OUT: ...
```
````

## Work
EOF

# A closing fence carries nothing but the run and optional whitespace; a
# fence-like line with trailing text is content, not a terminator.
mkdir -p "$tmp/fenced-info"
cat > "$tmp/fenced-info/progress.md" <<'EOF'
# progress

## Readback

```markdown
```template
Mission: ...
Scope: ...
OUT: ...
```

## Work
EOF

# The word cap is what separates a readback heading from a journal entry that
# mentions one, so its exact boundary is load-bearing: "## Readback P-D" is two
# words and is what a builder on a phased plan actually types.
mkdir -p "$tmp/short-title"
cat > "$tmp/short-title/progress.md" <<'EOF'
# progress

## Readback P-D
Mission: probe messaging, then write the doctrine.
Scope: kit/** + skills/**.
OUT: packages/**, any push.
EOF

# Hyphens live inside words. A heading counted by splitting on punctuation
# rejects "Readback Phase P-D" as five words, which is the documented cap
# silently meaning something else.
mkdir -p "$tmp/hyphen-title" "$tmp/four-words"
cat > "$tmp/hyphen-title/progress.md" <<'EOF'
# progress

## Readback Phase P-D
Mission: probe messaging, then write the doctrine.
Scope: kit/** + skills/**.
OUT: packages/**, any push.
EOF

cat > "$tmp/four-words/progress.md" <<'EOF'
# progress

## Notes about readback tooling
Mission-shaped prose that is not a readback.
Scope-shaped prose that is not a readback.
More prose still.
EOF

for d in full heading-only none no-file late subheads mentions fenced fenced-body fenced-tilde fenced-long fenced-info short-title hyphen-title four-words self-describing; do
  out="$("$cbr" readback "$tmp/$d" 2>&1)" \
    || fail "readback exited non-zero for '$d' — it reports a fact and must never gate: $out"
done

out="$("$cbr" readback "$tmp/full" 2>&1)"
grep -q "readback=present" <<<"$out" || fail "a real readback was not reported present: $out"

out="$("$cbr" readback "$tmp/late" 2>&1)"
grep -q "readback=present" <<<"$out" \
  || fail "a readback under a later, differently-cased heading was missed: $out"

out="$("$cbr" readback "$tmp/subheads" 2>&1)"
grep -q "readback=present" <<<"$out" \
  || fail "a readback written as sub-headings — the exact shape the law's three named items invite — was called MISSING: $out"

out="$("$cbr" readback "$tmp/mentions" 2>&1)"
grep -q "readback=MISSING" <<<"$out" \
  || fail "a journal that merely MENTIONS readback in a heading passed as one: $out"

out="$("$cbr" readback "$tmp/fenced" 2>&1)"
grep -q "readback=MISSING" <<<"$out" \
  || fail "a readback heading quoted inside a fenced code block passed as a real one: $out"

out="$("$cbr" readback "$tmp/fenced-body" 2>&1)"
grep -q "readback=MISSING" <<<"$out" \
  || fail "a readback whose only substance is a fenced template passed — fenced lines are excluded everywhere or nowhere: $out"

out="$("$cbr" readback "$tmp/fenced-tilde" 2>&1)"
grep -q "readback=MISSING" <<<"$out" \
  || fail "a tilde-fenced template counted as readback substance: $out"

out="$("$cbr" readback "$tmp/fenced-long" 2>&1)"
grep -q "readback=MISSING" <<<"$out" \
  || fail "a shorter fence marker inside a longer fence closed it early, and the template counted as substance: $out"

out="$("$cbr" readback "$tmp/fenced-info" 2>&1)"
grep -q "readback=MISSING" <<<"$out" \
  || fail "a fence-like line carrying trailing text closed the block, and the template counted as substance: $out"

out="$("$cbr" readback "$tmp/short-title" 2>&1)"
grep -q "readback=present" <<<"$out" \
  || fail "a two-word readback heading was rejected — the documented cap is three: $out"

out="$("$cbr" readback "$tmp/self-describing" 2>&1)"
grep -q "readback=present" <<<"$out" \
  || fail "a heading that begins with the word and then explains itself was rejected: $out"

out="$("$cbr" readback "$tmp/hyphen-title" 2>&1)"
grep -q "readback=present" <<<"$out" \
  || fail "a heading beginning with the word, then a phase label, was rejected: $out"

out="$("$cbr" readback "$tmp/four-words" 2>&1)"
grep -q "readback=MISSING" <<<"$out" \
  || fail "a heading that only MENTIONS readback passed as one: $out"

out="$("$cbr" readback "$tmp/heading-only" 2>&1)"
grep -q "readback=MISSING" <<<"$out" \
  || fail "an empty 'Readback' heading counted as a readback — the word is not the work: $out"

out="$("$cbr" readback "$tmp/none" 2>&1)"
grep -q "readback=MISSING" <<<"$out" || fail "a progress.md with no readback was not flagged: $out"

# No progress.md at all is a DIFFERENT fact from a progress.md without a
# readback: one is a builder that has not written anything yet, the other is a
# builder that started building without restating its plan.
out="$("$cbr" readback "$tmp/no-file" 2>&1)"
grep -q "readback=no-progress-file" <<<"$out" \
  || fail "a worktree with no progress.md must be reported distinctly, not as MISSING: $out"

# Invalid usage is NOT a readback state: an unresolvable slug or path is a
# caller error and must be loud. The "never gates" promise covers the three
# states, not typos — and the docs say exactly that.
if "$cbr" readback "$tmp/does-not-exist" >/dev/null 2>&1; then
  fail "an unresolvable target exited 0 — a typo'd slug would silently read as a pass"
fi

# `status` is where a dispatcher actually reads this fact, and the cases where it
# matters MOST are the ones with no live session: a builder that finished, and a
# builder that died. An early return that drops the fact there is the whole bug.
mkdir -p "$tmp/stub"
cat > "$tmp/stub/claude" <<'STUB'
#!/usr/bin/env bash
# `status` shells out for the supervisor registry; an empty list is the
# session-absent case under test.
[ "${1:-}" = agents ] && { echo '[]'; exit 0; }
exit 0
STUB
chmod +x "$tmp/stub/claude"

mkdir -p "$tmp/host/repo"
git -C "$tmp/host/repo" init -q -b main
git -C "$tmp/host/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
mkdir -p "$tmp/host/cockpit-gone"
cp "$tmp/none/progress.md" "$tmp/host/cockpit-gone/progress.md"

status_summary() {
  ( cd "$tmp/host/repo" && PATH="$tmp/stub:$PATH" "$cbr" status gone 2>&1 ) | grep '^SUMMARY' || true
}

# died: no session, no DONE.marker (status exits 1 here — that is its verdict, not ours)
sum="$(status_summary)"
grep -q "readback=" <<<"$sum" \
  || fail "status dropped the readback fact for a DIED builder — the case a dispatcher most needs it: $sum"
grep -q "readback=MISSING" <<<"$sum" \
  || fail "status reported the wrong readback state for a builder whose progress.md has none: $sum"

# complete: no session, DONE.marker present — the final-verification read
touch "$tmp/host/cockpit-gone/DONE.marker"
cp "$tmp/full/progress.md" "$tmp/host/cockpit-gone/progress.md"
sum="$(status_summary)"
grep -q "readback=present" <<<"$sum" \
  || fail "status dropped or mis-stated the readback fact for a COMPLETE builder: $sum"

echo "readback-fact.test OK: present / MISSING (incl. heading-without-substance) / no-progress-file all reported; unresolvable target still errors; status carries the fact in BOTH session-absent SUMMARYs"
