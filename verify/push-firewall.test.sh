#!/usr/bin/env bash
# Regression: the push firewall must hold against every route to main, not just
# the branch a builder happens to be standing on — in BOTH leaves, and on repos
# armed before the hook grew its second layer.
#
# The failure this pins was proven live (2026-08-27). The original hook keyed
# ONLY off the current branch: a builder on stream/* could push nothing — but
# a detached HEAD (symbolic-ref returns nothing), a throwaway side branch, or
# a session in the primary checkout (current branch = main) all sailed past a
# guard whose entire purpose is "only the human pushes main", on a repo where
# a push to main auto-deploys prod. The cure is a second layer that inspects
# the PUSHED REFS from pre-push stdin: any push targeting refs/heads/main is
# denied without CBR_ALLOW_PUSH=1, from any branch, any worktree.
#
# Review 4123 added two more halves, both pinned here:
#   BOTH LEAVES — the Codex leaf ships its own write_push_firewall; a fix that
#   lands only in the Claude leaf leaves every Codex-armed repo open. The full
#   route matrix runs against each leaf's body.
#   UPGRADE PATH — arm/provision recognize their own hook by the CBR_ALLOW_PUSH
#   marker; an old layer-1-only install carries the marker, so "already
#   installed" would keep the vulnerable body forever. ensure_push_firewall
#   must rewrite an obsolete own-hook (marker present, no pushed-ref layer)
#   while still refusing to clobber a foreign hook.
set -euo pipefail

for v in $(env | sed -n 's/^\(GIT_[A-Z_]*\)=.*/\1/p'); do unset "$v"; done
unset CBR_ALLOW_PUSH 2>/dev/null || true

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
kit="$(cd "$here/.." && pwd)"

claude_cbr="$root/skills/claude-controlled-build-run/scripts/cbr.sh"
[ -f "$claude_cbr" ] || claude_cbr="$kit/skill/claude-controlled-build-run/scripts/cbr.sh"
codex_cbr="$root/skills/codex-controlled-build-run/scripts/cbr-codex.sh"
[ -f "$codex_cbr" ] || codex_cbr="$kit/skill/codex-controlled-build-run/scripts/cbr-codex.sh"

tmp="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

fails=0
say()  { printf '%s\n' "$*"; }
pass() { say "  PASS  $*"; }
fail() { say "  FAIL  $*"; fails=$((fails+1)); }

# The hook body ships inside each leaf's write_push_firewall(); extracting and
# eval-ing that function tests the exact bytes arm/provision installs — a
# hand-copied fixture here would drift from the shipped hook silently.
extract_fn() {  # $1 = script, $2 = function name
  sed -n "/^$2()/,/^}\$/p" "$1"
}

fresh_repo() {  # $1 = dir; creates repo + local bare origin with a ref delta
  git init -q --bare "$1/origin.git"
  git init -q "$1/repo"
  git -C "$1/repo" config user.email t@t
  git -C "$1/repo" config user.name t
  git -C "$1/repo" remote add origin "$1/origin.git"
  git -C "$1/repo" commit -q --allow-empty -m base
  git -C "$1/repo" branch -M main
  git -C "$1/repo" push -q origin main
  git -C "$1/repo" commit -q --allow-empty -m next  # every later push has a real ref delta
}

expect_block() {  # $1 label, rest = git push args (cwd = repo)
  local label="$1"; shift
  if out=$(git push "$@" 2>&1); then
    fail "$label — push SUCCEEDED, expected BLOCKED"
  elif printf '%s' "$out" | grep -q "pre-push BLOCKED"; then
    pass "$label blocked"
  else
    fail "$label — push failed but not by the firewall: $out"
  fi
}
expect_allow() {  # $1 label, rest = git push args (cwd = repo)
  local label="$1"; shift
  if git push "$@" >/dev/null 2>&1; then
    pass "$label allowed"
  else
    fail "$label — push BLOCKED, expected allowed"
  fi
}

route_matrix() {  # cwd = repo with the hook under test installed
  say "  ACCIDENT GUARD"
  git checkout -q -b stream/x
  expect_block "stream branch, any push"        origin stream/x
  git checkout -q main

  say "  WANDERING ROUTES"
  git checkout -q --detach
  expect_block "detached HEAD -> main"          origin HEAD:main
  git checkout -q main
  git checkout -q -b side
  expect_block "side branch -> main"            origin side:main
  git checkout -q main
  expect_block "non-stream branch -> main"      origin main:main

  say "  HUMAN PATHS"
  git checkout -q -b work
  expect_allow "non-stream branch, non-main target" origin work:work
  git checkout -q main
  if CBR_ALLOW_PUSH=1 git push origin main >/dev/null 2>&1; then
    pass "CBR_ALLOW_PUSH=1 override pushes main"
  else
    fail "CBR_ALLOW_PUSH=1 override — push BLOCKED, the human path is bricked"
  fi
  git branch -q -D stream/x side work
}

# The obsolete bodies real repos were armed with before 2026-08-27, embedded
# VERBATIM — they are frozen historical artifacts, and the upgrade path only
# recognizes exact shipped bytes (review 4134), so the fixtures must be the
# genuine articles, not synthetic stand-ins.
write_obsolete_claude_v1() {
  cat > "$1" <<'HOOK'
#!/bin/sh
# cbr push firewall: a stream/* builder worktree must never push (only the human pushes; a push to
# main auto-deploys prod). Holds under --dangerously-skip-permissions — a hook is not a permission.
branch=$(git symbolic-ref --short HEAD 2>/dev/null)
case "$branch" in
  stream/*)
    if [ "$CBR_ALLOW_PUSH" != "1" ]; then
      echo "pre-push BLOCKED: '$branch' is a builder stream branch — builders never push." >&2
      echo "Intentional human push? re-run with: CBR_ALLOW_PUSH=1 git push" >&2
      exit 1
    fi ;;
esac
exit 0
HOOK
  chmod +x "$1"
}
write_obsolete_codex_v1() {
  cat > "$1" <<'HOOK'
#!/usr/bin/env bash
branch="$(git branch --show-current 2>/dev/null || true)"
case "$branch" in
  stream/*)
    if [ "${CBR_ALLOW_PUSH:-0}" != "1" ]; then
      echo "CBR push firewall: stream builders never push; orchestrator/human owns release" >&2
      exit 1
    fi
    ;;
esac
exit 0
HOOK
  chmod +x "$1"
}

for leaf in claude codex; do
  case "$leaf" in
    claude) src="$claude_cbr" ;;
    codex)  src="$codex_cbr" ;;
  esac

  unset -f write_push_firewall ensure_push_firewall _fw_sha256 2>/dev/null || true
  fn="$(extract_fn "$src" write_push_firewall)"
  [ -n "$fn" ] || { say "FATAL: write_push_firewall() not found in $src"; exit 1; }
  eval "$fn"
  # one-line helper ensure depends on; extract_fn's multi-line range can't see it
  sha_fn="$(grep '^_fw_sha256()' "$src" || true)"
  [ -n "$sha_fn" ] && eval "$sha_fn"
  ens="$(extract_fn "$src" ensure_push_firewall)"
  if [ -z "$ens" ]; then
    fail "$leaf: ensure_push_firewall() not found in $src — no upgrade path ships"
    ens=""
  else
    eval "$ens"
  fi

  say "LEAF: $leaf — fresh install holds every route"
  mkdir "$tmp/$leaf"
  fresh_repo "$tmp/$leaf"
  cd "$tmp/$leaf/repo"
  write_push_firewall .git/hooks/pre-push
  route_matrix

  [ -n "$ens" ] || continue

  say "LEAF: $leaf — ensure upgrades every KNOWN shipped obsolete body in place"
  git commit -q --allow-empty -m delta   # the matrix's override push synced main; the hook only fires on a real ref delta
  for v1 in claude codex; do
    "write_obsolete_${v1}_v1" .git/hooks/pre-push
    if ensure_push_firewall .git/hooks/pre-push; then
      expect_block "post-upgrade from $v1-v1 body: non-stream branch -> main" origin main:main
    else
      fail "ensure_push_firewall refused the shipped $v1-v1 obsolete body"
    fi
    git commit -q --allow-empty -m "delta-$v1"
  done

  say "LEAF: $leaf — ensure refuses an UNRECOGNIZED hook that mentions the marker"
  # A custom or hand-composed hook may carry unrelated enforcement alongside a
  # CBR_ALLOW_PUSH mention; rewriting it would silently delete that enforcement
  # (review 4134). It must be reported, distinctly from a markerless foreign
  # hook, and left byte-identical.
  printf '#!/bin/sh\n# custom: composes CBR_ALLOW_PUSH firewall with LFS checks\n./lfs-guard || exit 1\nexit 0\n' > .git/hooks/pre-push
  chmod +x .git/hooks/pre-push
  before="$(cat .git/hooks/pre-push)"
  rc=0; ensure_push_firewall .git/hooks/pre-push 2>/dev/null || rc=$?
  case "$rc" in
    0) fail "unrecognized marker-mentioning hook was accepted (rc 0) — clobbered or blessed" ;;
    2) pass "unrecognized marker-mentioning hook refused with its own code" ;;
    *) fail "unrecognized marker-mentioning hook returned rc $rc — indistinguishable from a markerless foreign hook" ;;
  esac
  [ "$before" = "$(cat .git/hooks/pre-push)" ] \
    && pass "unrecognized hook bytes untouched" \
    || fail "unrecognized hook was overwritten — unrelated enforcement deleted"

  say "LEAF: $leaf — ensure never clobbers a foreign hook"
  printf '#!/bin/sh\nexit 0\n' > .git/hooks/pre-push  # no CBR marker: not ours
  chmod +x .git/hooks/pre-push
  before="$(cat .git/hooks/pre-push)"
  rc=0; ensure_push_firewall .git/hooks/pre-push 2>/dev/null || rc=$?
  [ "$rc" = 1 ] \
    && pass "foreign hook refused (rc 1)" \
    || fail "foreign hook expected rc 1, got rc $rc"
  [ "$before" = "$(cat .git/hooks/pre-push)" ] \
    && pass "foreign hook bytes untouched" \
    || fail "foreign hook was overwritten"

  say "LEAF: $leaf — ensure leaves a current hook alone"
  write_push_firewall .git/hooks/pre-push
  before="$(cat .git/hooks/pre-push)"
  ensure_push_firewall .git/hooks/pre-push || fail "ensure failed on a current own-hook"
  [ "$before" = "$(cat .git/hooks/pre-push)" ] \
    && pass "current hook untouched" \
    || fail "current hook was rewritten (not idempotent)"

  say "LEAF: $leaf — ensure fails closed when the execute bit cannot be restored"
  # ensure is eval'd into this shell, so a chmod FUNCTION shadows the binary
  # inside it: simulates a filesystem where the bit cannot be armed. Success
  # here would mean arm reports a firewall git will silently skip.
  write_push_firewall .git/hooks/pre-push
  command chmod -x .git/hooks/pre-push
  chmod() { return 0; }
  rc=0; ensure_push_firewall .git/hooks/pre-push || rc=$?
  unset -f chmod
  [ "$rc" = 3 ] \
    && pass "unrestorable execute bit reported (rc 3)" \
    || fail "expected rc 3 on unrestorable execute bit, got rc $rc"
  command chmod +x .git/hooks/pre-push

  say "LEAF: $leaf — ensure re-arms a current hook whose execute bit was stripped"
  # git silently skips a non-executable hook: byte-perfect bytes enforce
  # nothing (review 4138). The bytes are provably ours, so restoring the bit
  # is always safe — and required, or 'current' means 'disabled'.
  git commit -q --allow-empty -m delta3
  chmod -x .git/hooks/pre-push
  if ensure_push_firewall .git/hooks/pre-push; then
    expect_block "post-rearm: non-stream branch -> main" origin main:main
  else
    fail "ensure refused its own current-but-disabled hook"
  fi
done

# ---------------------------------------------------------------------------
# BEHAVIOURAL RECOGNITION — a composed hook that still enforces both layers
# ---------------------------------------------------------------------------
# `ensure` decides ownership by exact bytes, and must: it may never clobber a
# hook a human composed. But a DOCTOR that reports by exact bytes calls that
# same composed hook "stale or edited — a push to main may pass", which is a
# false alarm about the one guard nobody may learn to ignore. Recognition is a
# different question from ownership, and it is answered by RUNNING the hook.
lib="$root/skills/cbr-core/scripts/strand-lib.sh"
[ -f "$lib" ] || lib="$kit/skill/claude-controlled-build-run/references/core/scripts/strand-lib.sh"
# shellcheck source=/dev/null
. "$lib"
command -v cbr_push_firewall_behaves >/dev/null 2>&1 \
  || { fail "no cbr_push_firewall_behaves in the shared library — the doctor can only recognize the firewall by its bytes"; }

if command -v cbr_push_firewall_behaves >/dev/null 2>&1; then
  probe="$tmp/fwprobe"; mkdir -p "$probe"
  eval "$(extract_fn "$claude_cbr" write_push_firewall)"

  write_push_firewall "$probe/plain"
  cbr_push_firewall_behaves "$probe/plain" \
    && pass "the shipped body is recognized by behaviour" \
    || fail "the shipped body failed its own behavioural probe (rc $?)"

  # A human merged the CBR firewall with a local check. Different bytes, same
  # two denials — the case the byte check reports as dangerous.
  { echo '#!/bin/sh'; echo '# local: reject pushes on fridays'; \
    sed '1d' "$probe/plain"; } > "$probe/composed"
  chmod +x "$probe/composed"
  cmp -s "$probe/plain" "$probe/composed" \
    && fail "fixture broke: the composed hook is byte-identical, so it proves nothing"
  cbr_push_firewall_behaves "$probe/composed" \
    && pass "a composed hook with both layers intact is recognized" \
    || fail "a composed hook that denies both routes was not recognized (rc $?)"

  # ...and recognition must still be a GATE: a body that kept the marker but
  # lost the pushed-ref layer is exactly the pre-2026-08-27 hole. Written out
  # by hand rather than sed-cut from the shipped body: a cut that swallows the
  # `esac` produces a hook that does not PARSE, which the probe refuses for a
  # reason that has nothing to do with the missing layer — green through the
  # exact regression the fixture exists to catch.
  cat > "$probe/layer1only" <<'L1'
#!/bin/sh
branch=$(git symbolic-ref --short HEAD 2>/dev/null)
case "$branch" in
  stream/*)
    if [ "$CBR_ALLOW_PUSH" != "1" ]; then
      echo "pre-push BLOCKED: builder stream branch" >&2
      exit 1
    fi ;;
esac
exit 0
L1
  chmod +x "$probe/layer1only"

  # A hook that reads ONE line of stdin. git sends one line PER REF, so
  # `git push origin side:side main:main` puts side first and main second, and
  # a single `read` never sees main at all. Byte-wise it looks like a complete
  # firewall; behaviourally main is open.
  cat > "$probe/singleread" <<'SR'
#!/bin/sh
branch=$(git symbolic-ref --short HEAD 2>/dev/null)
case "$branch" in
  stream/*)
    if [ "$CBR_ALLOW_PUSH" != "1" ]; then exit 1; fi ;;
esac
read -r _local _lsha remote _rsha
case "$remote" in
  refs/heads/main)
    if [ "$CBR_ALLOW_PUSH" != "1" ]; then exit 1; fi ;;
esac
exit 0
SR
  chmod +x "$probe/singleread"

  # A hook that gives up when HEAD is detached — the bypass the shipped body's
  # own comment names as proven live on 2026-08-27.
  sed 's|^branch=.*|branch=$(git symbolic-ref --short HEAD 2>/dev/null); [ -z "$branch" ] \&\& exit 0|' \
    "$probe/plain" > "$probe/detached"
  chmod +x "$probe/detached"

  for holey in layer1only singleread detached; do
    sh -n "$probe/$holey" \
      || fail "fixture $holey does not parse — it would be refused for the wrong reason and the assertion below would be worthless"
    rc=0; cbr_push_firewall_behaves "$probe/$holey" || rc=$?
    [ "$rc" -eq 2 ] \
      && pass "a hook with a hole in the pushed-ref layer ($holey) is refused as layer-2-missing" \
      || fail "$holey was judged rc $rc, not 2 — a push to main from a side branch sails through a hook the doctor calls healthy"
  done

  # An ordinary push must still be allowed, or the probe would bless a hook
  # that denies everything and call the firewall healthy.
  printf '#!/bin/sh\nexit 1\n' > "$probe/denyall"; chmod +x "$probe/denyall"
  cbr_push_firewall_behaves "$probe/denyall" \
    && fail "a hook that denies every push was called a working firewall" \
    || pass "a deny-everything hook is refused by behaviour"

  # git silently skips a non-executable hook, so bytes that would enforce and
  # a file git never runs are the same thing.
  cp "$probe/plain" "$probe/noexec"; chmod -x "$probe/noexec"
  cbr_push_firewall_behaves "$probe/noexec" \
    && fail "a non-executable hook passed — git never runs it" \
    || pass "a non-executable hook is refused by behaviour"

  # A hook that enforces BOTH layers with no CBR_ALLOW_PUSH escape at all.
  # Recognition was gated on that literal, so this hook — behaviourally a
  # stricter firewall than the shipped one — was reported as "push firewall
  # missing" and never probed. The token answers ownership, never enforcement.
  cat > "$probe/notoken" <<'NT'
#!/bin/sh
branch=$(git symbolic-ref --short HEAD 2>/dev/null)
case "$branch" in
  stream/*) echo "builder branches do not push" >&2; exit 1 ;;
esac
while read -r _local _lsha remote _rsha; do
  case "$remote" in
    refs/heads/main) echo "main is human-push-only" >&2; exit 1 ;;
  esac
done
exit 0
NT
  chmod +x "$probe/notoken"
  grep -q CBR_ALLOW_PUSH "$probe/notoken" \
    && fail "fixture broke: the token-free hook mentions CBR_ALLOW_PUSH, so it proves nothing"
  cbr_push_firewall_behaves "$probe/notoken" \
    && pass "a hook that denies both routes with no CBR_ALLOW_PUSH escape is recognized by behaviour" \
    || fail "a behaviourally correct hook was refused because it does not spell the shipped body's override token (rc $?)"

  # One verdict function, consumed by both doctors: the decision each of them
  # reports is the same decision, or the leaves disagree about whether main is
  # guarded and only one of them is right.
  command -v cbr_push_firewall_verdict >/dev/null 2>&1 \
    || fail "no cbr_push_firewall_verdict in the shared library — each doctor is deciding this for itself"
  check_verdict() { # <fixture> <expected>
    local got; got="$(cbr_push_firewall_verdict "$probe/$1" "$probe/plain")"
    [ "$got" = "$2" ] && pass "verdict($1) = $2" || fail "verdict($1) = $got, want $2"
  }
  check_verdict plain      current
  check_verdict notoken    behaves
  check_verdict composed   behaves
  check_verdict layer1only layer-2-missing
  check_verdict singleread layer-2-missing
  check_verdict detached   layer-2-missing
  check_verdict denyall    wall
  check_verdict noexec     current-not-executable
  got="$(cbr_push_firewall_verdict "$probe/does-not-exist" "$probe/plain")"
  [ "$got" = missing ] && pass "verdict(absent) = missing" || fail "verdict(absent) = $got, want missing"

  # The probe builds a throwaway repo, and this repo's standing scar is a
  # fixture that inherited the outer hook's GIT_* env and reached into the
  # primary checkout (the core.bare flip, 2026-08-29). A verdict that changes
  # when GIT_DIR is exported is a verdict about the wrong repository.
  # It happened: on 2026-08-29 this probe, before the env scrub, ran under a
  # pre-commit hook that exports GIT_DIR/GIT_WORK_TREE and created + checked
  # out `fwprobe/side` IN THE LIVE WORKTREE. Every commit after it would have
  # landed on that branch; only the plan-coherence gate noticed. So the probe's
  # effect on the ambient repository is asserted, not just its verdict.
  victim="$tmp/victim"; mkdir -p "$victim"
  ( cd "$victim" && git init -q -b stream/victim . \
      && git config user.email v@example.invalid && git config user.name v \
      && git commit -q --allow-empty -m base ) >/dev/null 2>&1 \
    || fail "could not build the ambient-repo fixture"
  before_branch="$(git -C "$victim" branch --show-current)"
  before_head="$(git -C "$victim" rev-parse HEAD)"
  before_refs="$(git -C "$victim" for-each-ref --format='%(refname)')"
  GIT_DIR="$victim/.git" GIT_WORK_TREE="$victim" cbr_push_firewall_behaves "$probe/plain" >/dev/null 2>&1 || true
  [ "$(git -C "$victim" branch --show-current)" = "$before_branch" ] \
    && [ "$(git -C "$victim" rev-parse HEAD)" = "$before_head" ] \
    && [ "$(git -C "$victim" for-each-ref --format='%(refname)')" = "$before_refs" ] \
    && pass "the probe leaves the caller's repository on the branch it found it on" \
    || fail "the probe checked out a branch in the AMBIENT repository — every commit after it lands somewhere nobody chose"

  for fx in plain detached singleread denyall; do
    rc=0;  cbr_push_firewall_behaves "$probe/$fx" || rc=$?
    rc2=0; GIT_DIR="$root/.git" GIT_WORK_TREE="$root" GIT_INDEX_FILE="$root/.git/index" \
             cbr_push_firewall_behaves "$probe/$fx" || rc2=$?
    [ "$rc" -eq "$rc2" ] \
      && pass "the probe's verdict for $fx does not depend on the caller's GIT_* environment" \
      || fail "the probe answered $rc bare and $rc2 under GIT_DIR for $fx — it is probing the ambient repository, not its own scratch one"
  done
fi

# BOTH doctors must USE it: a recognizer nothing calls leaves the false alarm
# exactly where it was, and a repair that lands on one leaf is how the agent-harness leaves
# drift apart.
for doc in "$claude_cbr" "$codex_cbr"; do
  grep -q 'cbr_push_firewall_verdict' "$doc" \
    && pass "$(basename "$doc") reports the shared firewall verdict" \
    || fail "$(basename "$doc") decides the firewall's health for itself — two implementations, and the one that drifts is the one nobody runs"
  grep -qE 'grep -q ?"?CBR_ALLOW_PUSH"? "\$(pre_push|pp)"' "$doc" \
    && fail "$(basename "$doc") still gates recognition on the shipped body's override token: a hook that denies every route to main without it reads as NO firewall at all"
done

cd "$tmp"
[ "$fails" -eq 0 ] && say "OK: push firewall holds on every route, both leaves, upgrades included" || say "FAILURES: $fails"
exit "$((fails > 0))"
