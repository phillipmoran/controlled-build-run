#!/usr/bin/env bash
# Regression for the closeout-pending check (cbr.sh closeout-pending, which
# cbr.sh doctor runs as a WARN-only step): a worktree whose branch is fully
# merged into main is a reap candidate, but a worktree with uncommitted files or
# a live process rooted in it is NOT — flagging either would send a human to
# `closeout` on work that is still someone's.
# Hermetic: builds a scratch repo with four worktrees; the real repo is untouched.
set -euo pipefail

# pre-commit exports GIT_DIR/GIT_INDEX_FILE/GIT_WORK_TREE to hook processes;
# inherited, the fixture's git calls would operate on the HOST repo's index.
for v in $(env | sed -n 's/^\(GIT_[A-Z_]*\)=.*/\1/p'); do unset "$v"; done

# Test the CANONICAL script when we are in the source repo (kit/ is a build
# artifact of it); fall back to the kit's own copy so a port can run this too.
cbr="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/skills/claude-controlled-build-run/scripts/cbr.sh"
[ -x "$cbr" ] || cbr="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/skill/claude-controlled-build-run/scripts/cbr.sh"
# Canonicalise: on macOS mktemp hands back /var/... while git and `pwd -P` report
# /private/var/..., so an assertion built from $tmp would only ever match by
# substring — and an exact-line assertion would never match at all.
tmp="$(cd "$(mktemp -d)" && pwd -P)"
sleeper=""; nested_sleeper=""
cleanup() {
  [ -n "$sleeper" ] && kill "$sleeper" 2>/dev/null
  [ -n "$nested_sleeper" ] && kill "$nested_sleeper" 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT
fail() { echo "doctor-closeout.test FAIL: $1" >&2; exit 1; }

git="git -C $tmp/repo -c user.email=t@t -c user.name=t"
mkdir -p "$tmp/repo"
git -C "$tmp/repo" init -q -b main
echo base > "$tmp/repo/f.txt"
$git add -A && $git commit -qm base

# merged+clean: the only true reap candidate
$git branch stream/merged-clean
git -C "$tmp/repo" worktree add -q "$tmp/merged-clean" stream/merged-clean

# merged+dirty: merged, but carries uncommitted work a human must eyeball first
$git branch stream/merged-dirty
git -C "$tmp/repo" worktree add -q "$tmp/merged-dirty" stream/merged-dirty
echo scratch > "$tmp/merged-dirty/uncommitted.txt"

# merged+live: merged and clean, but a process is rooted in it right now
$git branch stream/merged-live
git -C "$tmp/repo" worktree add -q "$tmp/merged-live" stream/merged-live
# stdio to /dev/null: a background child that inherits this script's stdout keeps
# the caller's pipe open until it dies — a pre-commit hook would stall on it.
( cd "$tmp/merged-live" && exec sleep 60 ) >/dev/null 2>&1 &
sleeper=$!
sleep 1   # let the kernel register the child's cwd before lsof reads it

# merged+live in a SUBDIRECTORY: a shell sitting in src/ is just as much "in use"
# as one at the root, and a worktree presented as reapable while someone works in
# a subdir is the dangerous false negative.
$git branch stream/merged-nested
git -C "$tmp/repo" worktree add -q "$tmp/merged-nested" stream/merged-nested
mkdir -p "$tmp/merged-nested/sub/deeper"
( cd "$tmp/merged-nested/sub/deeper" && exec sleep 60 ) >/dev/null 2>&1 &
nested_sleeper=$!

# merged+clean AND named by the convention closeout resolves (../cockpit-<slug>),
# so this one — and only this one — may be offered the `cbr.sh closeout` command.
$git branch stream/conventional
git -C "$tmp/repo" worktree add -q "$tmp/cockpit-conv" stream/conventional

# merged+clean at a path carrying a space and shell metacharacters — legal on
# every filesystem we run on, and the case where an unquoted suggestion either
# breaks or runs something the human did not intend.
# Trailing space too: `read` with the default IFS would silently trim it and send
# every later cd/git call to a path that does not exist.
odd="$tmp/weird & name \$x "
$git branch stream/odd-path
git -C "$tmp/repo" worktree add -q "$odd" stream/odd-path

# unmerged: real work not in main yet — reaping it would destroy the work
$git branch stream/unmerged
git -C "$tmp/repo" worktree add -q "$tmp/unmerged" stream/unmerged
git -C "$tmp/unmerged" -c user.email=t@t -c user.name=t commit -qm ahead --allow-empty

# Run it from a WORKTREE, not from the primary checkout: that is where a builder
# actually runs it, and the primary must never be a reap candidate even though
# `main` is trivially an ancestor of itself.
# Assertions use a here-string, never `printf ... | grep -q`: under `pipefail`
# grep -q exits on the first match and the writer dies of SIGPIPE, failing the
# pipeline on a MATCH — a coin-flip that already misfired once here.
out="$("$cbr" closeout-pending "$tmp/merged-clean" 2>&1)" \
  || fail "closeout-pending exited non-zero (it is WARN-only and must not gate): $out"
grep -q "CLOSEOUT PENDING  $tmp/repo  branch=" <<<"$out" \
  && fail "the primary checkout was flagged as a reap candidate when invoked from a worktree: $out"

out="$("$cbr" closeout-pending "$tmp/repo" 2>&1)" \
  || fail "closeout-pending exited non-zero (it is WARN-only and must not gate): $out"

grep -q "CLOSEOUT PENDING.*merged-clean" <<<"$out" \
  || fail "merged+clean worktree not flagged as closeout pending: $out"
# The reap command must address THIS worktree. `cbr.sh closeout <slug>` resolves
# the slug to the sibling path ../cockpit-<slug> and nothing else, so offering it
# for a worktree that does not live there would point a human at a different
# folder — or at one that does not exist.
grep -q "$tmp/merged-clean.*reap: git .*worktree remove.*$tmp/merged-clean" <<<"$out" \
  || fail "off-convention worktree must get a path-explicit reap command, not a slug: $out"
grep -q "$tmp/merged-clean.*cbr.sh closeout" <<<"$out" \
  && fail "off-convention worktree was offered 'cbr.sh closeout <slug>', which resolves elsewhere: $out"
grep -q "$tmp/cockpit-conv.*reap: cbr.sh closeout conv " <<<"$out" \
  || fail "convention-named worktree did not get the cbr.sh closeout command with its slug: $out"

grep -q "CLOSEOUT PENDING.*merged-dirty" <<<"$out" \
  && fail "worktree with uncommitted files was flagged — a human must eyeball it first: $out"
grep -q "CLOSEOUT PENDING.*merged-live" <<<"$out" \
  && fail "worktree with a live process rooted in it was flagged: $out"
grep -q "CLOSEOUT PENDING.*merged-nested" <<<"$out" \
  && fail "worktree with a live process in a SUBDIRECTORY was flagged — it is just as in-use: $out"
grep -q "CLOSEOUT PENDING.*unmerged" <<<"$out" \
  && fail "unmerged worktree was flagged — reaping it would destroy unmerged work: $out"

# What the human copies must parse back into EXACTLY the path we reported. Stub
# `git` to echo its arguments, eval the printed command, and demand the odd path
# comes back as one intact argument — an unquoted suggestion either splits it or
# executes the metacharacters.
oddline="$(grep -F "CLOSEOUT PENDING  $odd  branch=" <<<"$out")" \
  || fail "worktree at a path with a space and metacharacters was not reported: $out"
oddcmd="${oddline#*reap: }"
parsed="$(eval "git() { printf '%s\n' \"\$@\"; }; $oddcmd")" \
  || fail "the printed reap command does not even parse: $oddcmd"
grep -qxF -- "$odd" <<<"$parsed" \
  || fail "reap command does not pass the odd path as one intact argument: cmd=[$oddcmd] parsed=[$parsed]"

# The skipped ones must still be VISIBLE with their reason: a silent skip reads
# as "nothing pending" and is how a merged worktree hides forever.
grep -q "merged-dirty.*uncommitted" <<<"$out" \
  || fail "dirty worktree skipped silently (no reason printed): $out"
grep -q "merged-live.*live" <<<"$out" \
  || fail "live worktree skipped silently (no reason printed): $out"
grep -q "merged-nested.*live" <<<"$out" \
  || fail "subdirectory-live worktree skipped silently (no reason printed): $out"

# Never the primary checkout itself, whatever its state or who asks.
grep -q "CLOSEOUT PENDING  $tmp/repo  branch=" <<<"$out" \
  && fail "the primary checkout was flagged as a reap candidate: $out"

echo "doctor-closeout.test OK: merged+clean flagged with a reap command that addresses IT; dirty, live (root and subdir), unmerged and primary all correctly skipped (with reasons)"
