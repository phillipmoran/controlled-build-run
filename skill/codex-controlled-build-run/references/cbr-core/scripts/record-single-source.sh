#!/usr/bin/env bash
# The single-source record check: each fact class lives in exactly ONE record
# file, and every other record links to it rather than restating it.
#
# The failure it exists for is not untidiness. A fact written twice is a fact
# that will be wrong in one of the two, with nothing to say which — and the
# reader who checks the wrong copy acts on it. This stream watched STATUS.md's
# ask list fall three days behind ASK-ORCH.md while both looked authoritative,
# and an orchestrator reading the stale one would have missed a parked ask
# entirely.
#
# Fails CLOSED on its own infra, like the complexity gate and unlike the
# surfacing hooks: this one BLOCKS a commit, and a gate that cannot read its
# own ownership table does not know what is owned. "I could not tell" may not
# be reported as "fine".
set -uo pipefail

# The strand root is where this RUNS, not where this lives: the checker is a
# core script shared by every port, so a root derived from its own location
# would scan whichever skill folder happens to hold the copy. Git answers first
# (a pre-commit hook can be invoked from anywhere in the tree), with the
# environment scrubbed — a hook's exported GIT_DIR points at the repo that is
# committing, which is not always the tree being scanned.
root="$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_OBJECT_DIRECTORY \
        -u GIT_COMMON_DIR -u GIT_NAMESPACE -u GIT_ALTERNATE_OBJECT_DIRECTORIES \
        -u GIT_CONFIG_COUNT -u GIT_PREFIX \
        git rev-parse --show-toplevel 2>/dev/null)" || true
[ -n "$root" ] || root="$PWD"
dir="$root"
config="$root/record-ownership.json"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir)    dir="$2"; shift 2 ;;
    --config) config="$2"; shift 2 ;;
    *) echo "usage: record-single-source.sh [--dir <root>] [--config <ownership.json>]" >&2; exit 2 ;;
  esac
done

python3 - "$dir" "$config" <<'PY'
import json
import os
import re
import sys

dir_, config = sys.argv[1], sys.argv[2]

def die_infra(msg):
    sys.stderr.write("record-single-source: %s\n" % msg)
    sys.stderr.write(
        "This gate blocks a commit, so it fails closed: an ownership table it\n"
        "cannot read is not permission to proceed.\n"
    )
    sys.exit(2)

try:
    with open(config) as fh:
        spec = json.load(fh)
except FileNotFoundError:
    die_infra("no ownership table at %s" % config)
except (OSError, ValueError) as exc:
    die_infra("the ownership table at %s is unreadable: %s" % (config, exc))

facts = spec.get("facts")
if not isinstance(facts, list) or not facts:
    die_infra("the ownership table declares no facts — it would pass every tree")

# The record surface is every text file at the ROOT of the strand: that is what
# an orchestrator or a reviewer opens. Two boundaries, both
# deliberate and both stated so nobody mistakes them for oversight:
#
#   - Root only. A copy under `docs/` is an ARCHIVE of a finished strand, and
#     an archive restating a fact is not the drift this catches — it is the
#     record of a fact that WAS true. Widening here would fail every commit
#     against a repo that keeps its stream archives.
#   - The set is not configurable. An earlier draft let the table name the
#     records to scan, which is a switch that silently narrows the gate to
#     nothing while every fixture stays green.
try:
    records = sorted(
        f
        for f in os.listdir(dir_)
        if os.path.splitext(f)[1].lower() in (".md", ".markdown", ".txt", ".rst")
    )
except OSError as exc:
    die_infra("cannot list the record set in %s: %s" % (dir_, exc))
records = [r for r in records if os.path.isfile(os.path.join(dir_, r))]

unknown = set(spec) - {"_note", "facts"}
if unknown:
    die_infra(
        "the ownership table carries key(s) this checker does not implement: %s.\n"
        "  A key it ignores is a setting someone will believe is doing something"
        % ", ".join(sorted(unknown))
    )

if not records:
    die_infra(
        "no record files found in %s — a run that examined nothing reports\n"
        "  exactly like a clean one" % dir_
    )

lines = {}
for rec in records:
    try:
        with open(os.path.join(dir_, rec), errors="replace") as fh:
            lines[rec] = fh.read().split("\n")
    except OSError as exc:
        die_infra("cannot read the record %s: %s" % (rec, exc))

violations = []
stale = []
examined = 0
for fact in facts:
    name = fact.get("name")
    owner = fact.get("owner")
    pattern = fact.get("pattern")
    if not (name and owner and pattern):
        die_infra("a fact entry is missing name/owner/pattern: %r" % (fact,))
    # Switching off the stale-pattern guard is the one move that can retire a
    # class without anyone noticing, so it is spelled as a REASON rather than a
    # boolean: the reason is checkable against the tree, a bare `true` is not.
    extra = set(fact) - {"name", "owner", "pattern", "stalenessCheck", "examples", "why"}
    if extra:
        die_infra(
            "the fact %r carries key(s) this checker does not implement: %s.\n"
            "  A key it ignores is a setting someone will believe is armed"
            % (name, ", ".join(sorted(extra)))
        )
    reason = fact.get("stalenessCheck")
    if reason is not None and reason not in ("sometimes-empty", "never-in-owner"):
        die_infra(
            "the fact %r declares stalenessCheck %r, which this checker does not\n"
            "  implement. The two it honours are \"sometimes-empty\" (a record that is\n"
            "  legitimately empty at times) and \"never-in-owner\" (a forbidden\n"
            "  restatement shape, which is not a record and never appears in one)"
            % (name, reason)
        )
    try:
        rx = re.compile(pattern)
    except re.error as exc:
        die_infra("the pattern for %s does not compile: %s" % (name, exc))

    # Switching the guard off buys an OBLIGATION, not an exemption: whichever
    # reason is declared, the checker proves it here rather than taking the
    # word for it. Without this, "stalenessCheck" is a renamed boolean and a
    # typo'd pattern retires its class exactly as silently as before — in a
    # port's own table, where no fixture of ours is looking.
    #
    # Examples are checked WHEREVER they appear, not only where they are
    # required: a key honoured in one branch and dropped in another is the same
    # unimplemented setting as one the checker never heard of, and a port that
    # pins a stale-checked fact's pattern with examples would be believing a
    # guarantee nothing enforces.
    # PRESENCE is the declaration, so an empty list and an explicit null are
    # refused rather than read as "no examples": both look like a pin and hold
    # nothing, which is the silent-inert setting one spelling further down.
    examples = fact.get("examples")
    if "examples" in fact:
        if not isinstance(examples, list) or not examples:
            die_infra(
                "the fact %r declares \"examples\" as %r. An example list is a pin on\n"
                "  the pattern; empty, null, or not a list, it pins nothing while reading\n"
                "  like a guarantee. Give it the lines the pattern must match, or drop\n"
                "  the key" % (name, examples)
            )
        unmatched = [e for e in examples if not (isinstance(e, str) and rx.search(e))]
        if unmatched:
            die_infra(
                "the fact %r declares example(s) its own pattern does not match:\n%s\n"
                "  An example is the pattern's pin. If the pattern no longer matches the\n"
                "  shape the table says it is for, one of the two is wrong — and where the\n"
                "  stale guard is off, this is the typo it would have caught"
                % (name, "".join("    %r\n" % e for e in unmatched))
            )
    if reason is not None and not examples:
        die_infra(
            "the fact %r turns off the stale-pattern guard but declares no\n"
            "  \"examples\": lines its pattern must match. The guard exists because a\n"
            "  typo'd pattern retires a whole class in silence; turning it off without\n"
            "  putting something in its place is the silence, renamed" % name
        )

    owner_present = owner in lines
    if owner_present:
        examined += 1
        own_hits = sum(1 for ln in lines[owner] if rx.search(ln))
        if own_hits == 0 and reason is None:
            stale.append((name, owner, pattern))
        if own_hits and reason == "never-in-owner":
            die_infra(
                "the fact %r is declared \"never-in-owner\" — a forbidden restatement\n"
                "  shape, not a record — but its pattern matches %d line(s) in %s.\n"
                "  Either the shape became a record the file legitimately carries, or\n"
                "  the pattern is wrong; both need a human, and neither may be assumed"
                % (name, own_hits, owner)
            )
    # An absent owner is NOT a licence to write the fact elsewhere. That is the
    # arrangement where duplication is most likely — the record has not been
    # started, so the fact lands wherever there is room — so the scan below
    # still runs and any hit outside the owner is a violation.
    for rec in records:
        if rec == owner:
            continue
        for n, ln in enumerate(lines[rec], 1):
            if rx.search(ln):
                violations.append((rec, n, name, owner, ln.strip()))

if stale:
    for name, owner, pattern in stale:
        sys.stderr.write(
            "record-single-source: %s owns \"%s\" and carries none of it.\n"
            "  The pattern %s matches nothing there, so the class is retired and\n"
            "  every copy of it elsewhere would now pass unnoticed. Either the\n"
            "  owner changed shape or the table went stale; both need a human.\n"
            "  (If that is expected, declare why: \"stalenessCheck\":\n"
            "  \"sometimes-empty\" for a record that is legitimately empty at times,\n"
            "  \"never-in-owner\" for a forbidden restatement shape that is not a record.)\n"
            % (owner, name, pattern)
        )
    sys.exit(2)

if violations:
    sys.stderr.write(
        "record-single-source: %d fact(s) written outside the file that owns them.\n"
        % len(violations)
    )
    for rec, n, name, owner, text in violations:
        sys.stderr.write(
            "  %s:%d  \"%s\" belongs to %s%s\n      %s\n"
            % (rec, n, name, owner, "" if owner in lines else " (which does not exist yet)", text)
        )
    sys.stderr.write(
        "\nOne fact, one home. The other record LINKS to the owner — it does not\n"
        "restate it, because the copy that drifts is always the one nobody\n"
        "re-reads, and a reader has no way to tell which of the two is current.\n"
    )
    sys.exit(1)

print(
    "record-single-source: clean — %d record file(s), %d owned fact class(es), "
    "no fact written twice" % (len(records), examined)
)
PY
