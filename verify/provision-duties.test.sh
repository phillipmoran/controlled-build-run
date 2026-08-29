#!/usr/bin/env bash
# Regression for the three duties provision owes a NEWBORN strand
# (skills/cbr-core/strand.md "Set up the strand") and for BOTH leaves being
# wired to the one shared implementation of them:
#
#   1. reset stale records — a worktree born from a base that carries another
#      strand's STATUS.md / DONE.marker starts life wearing a dead build's
#      sign; a watcher that glances at it believes a build that never ran.
#   2. record + assert the base pin — the strand's declared base is written
#      down at birth so launch can mechanically prove the branch still grows
#      from it, instead of discovering a silent wrong-base fork mid-build.
#   3. the project prep hook — stack-specific workspace prep (dependency
#      links, venvs) lives in the PROJECT's own `.cbr/provision-hook.sh`,
#      not in the neutral core; the core only owns the socket: run it when
#      present, skip when absent, fail the provision loudly when it fails.
#
# Two halves, deliberately (same shape as closeout-archive.test.sh):
#   BEHAVIOUR — each duty exercised against scratch repos.
#   WIRING — each leaf's provision/launch is asserted to call the shared
#   functions; a passing behaviour half means nothing if a leaf still skips
#   the duty.
#
# Hermetic: everything happens in scratch repos; the real repo is untouched.
set -euo pipefail

for v in $(env | sed -n 's/^\(GIT_[A-Z_]*\)=.*/\1/p'); do unset "$v"; done

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
kit="$(cd "$here/.." && pwd)"

lib="$root/skills/cbr-core/scripts/strand-lib.sh"
claude_leaf="$root/skills/claude-controlled-build-run/scripts/cbr.sh"
codex_leaf="$root/skills/codex-controlled-build-run/scripts/cbr-codex.sh"
[ -f "$lib" ]         || lib="$kit/skill/claude-controlled-build-run/references/core/scripts/strand-lib.sh"
[ -f "$claude_leaf" ] || claude_leaf="$kit/skill/claude-controlled-build-run/scripts/cbr.sh"
[ -f "$codex_leaf" ]  || codex_leaf="$kit/skill/codex-controlled-build-run/scripts/cbr-codex.sh"

tmp="$(cd "$(mktemp -d)" && pwd -P)"
cleanup() { local rc=$?; rm -rf "$tmp"; exit "$rc"; }
trap cleanup EXIT
fail() { echo "provision-duties.test FAIL: $1" >&2; exit 1; }

# shellcheck disable=SC1090
. "$lib"

# ---------------------------------------------------------------------------
# FIXTURE — a base branch carrying a dead strand's leftovers, and a fresh
# strand worktree grown from it (exactly what git worktree add produces).
# ---------------------------------------------------------------------------
repo="$tmp/repo"
mkdir -p "$repo"
git -C "$repo" init -q -b main
g="git -C $repo -c user.email=t@t -c user.name=t"
printf '# STATUS — stream: dead-strand\nphase: COMPLETE\n' > "$repo/STATUS.md"
printf 'stream/dead-strand — COMPLETE\n' > "$repo/DONE.marker"
printf 'question from a dead build\n' > "$repo/ASK-ORCH.md"
printf '# limits — dead strand\n' > "$repo/KNOWN-LIMITATIONS.md"
printf 'real source\n' > "$repo/app.txt"
$g add -A && $g commit -qm 'base with dead-strand leftovers'

wt="$tmp/wt"
git -C "$repo" worktree add -q "$wt" -b stream/fresh main

# ---------------------------------------------------------------------------
# DUTY 1 — reset stale records: leftovers vanish, real files survive.
# ---------------------------------------------------------------------------
out="$(cbr_provision_reset_stale_records "$wt")" \
  || fail "reset-stale-records failed on a normal worktree: $out"
for f in STATUS.md DONE.marker ASK-ORCH.md KNOWN-LIMITATIONS.md; do
  [ -e "$wt/$f" ] && fail "stale $f inherited from the base must be gone after reset"
done
[ -f "$wt/app.txt" ] || fail "reset must touch ONLY record files — app.txt was removed"
grep -q 'removed=4' <<<"$out" || fail "reset must report what it removed, got: $out"

# Idempotent: a second run finds nothing and still succeeds.
out="$(cbr_provision_reset_stale_records "$wt")" \
  || fail "reset-stale-records must succeed when there is nothing to remove"
grep -q 'removed=0' <<<"$out" || fail "second reset must report removed=0, got: $out"

# A stale record that is a DIRECTORY is not silently rm -rf'd — loud failure.
mkdir -p "$wt/STATUS.md"
cbr_provision_reset_stale_records "$wt" >/dev/null 2>&1 \
  && fail "a directory squatting on a record name must fail the reset, not be deleted blind"
rmdir "$wt/STATUS.md"

# ---------------------------------------------------------------------------
# DUTY 2 — base pin: recorded at birth, asserted before dispatch.
# ---------------------------------------------------------------------------
cbr_record_strand_base "$repo" stream/fresh main >/dev/null \
  || fail "recording the base pin failed"
cbr_assert_strand_base "$repo" stream/fresh >/dev/null \
  || fail "a branch sitting exactly on its recorded base must pass the assert"

# Strand grows: still fine — the base is an ancestor.
printf 'work\n' > "$wt/work.txt"
git -C "$wt" -c user.email=t@t -c user.name=t add -A
git -C "$wt" -c user.email=t@t -c user.name=t commit -qm 'strand work'
cbr_assert_strand_base "$repo" stream/fresh >/dev/null \
  || fail "a strand that grew from its recorded base must pass the assert"

# The wrong-base case: a branch whose recorded base is NOT in its history —
# the silent fast-forward failure, caught mechanically.
$g checkout -q --detach main
printf 'diverged\n' > "$repo/div.txt"
$g add -A && $g commit -qm 'base moved on'
div="$($g rev-parse HEAD)"
$g checkout -q main
git -C "$repo" config "branch.stream/fresh.cbrBase" "$div"
rc=0; cbr_assert_strand_base "$repo" stream/fresh >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] || fail "a recorded base absent from the branch's history must fail the assert with rc=1 (got $rc)"

# No pin recorded (a strand born before this law): UNKNOWN (rc=2), never a
# hard failure — the caller warns, it does not brick old strands.
git -C "$repo" config --unset "branch.stream/fresh.cbrBase"
rc=0; cbr_assert_strand_base "$repo" stream/fresh >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || fail "a strand with no recorded base must return 2 (unknown), not pass or hard-fail (got $rc)"

# ---------------------------------------------------------------------------
# DUTY 3 — the prep-hook socket: absent=skip, present=runs in the worktree,
# failing=fails the provision, non-executable=loud misconfiguration.
# ---------------------------------------------------------------------------
out="$(cbr_run_provision_hook "$repo" "$wt")" \
  || fail "an absent hook must be a clean skip, not a failure"
grep -q 'hook=absent' <<<"$out" || fail "absent hook must report hook=absent, got: $out"

mkdir -p "$repo/.cbr"
cat > "$repo/.cbr/provision-hook.sh" <<'EOF'
#!/bin/sh
# args: $1 = primary repo root, $2 = worktree; cwd = worktree
printf '%s\n%s\n' "$1" "$2" > hook-ran.txt
EOF
chmod +x "$repo/.cbr/provision-hook.sh"
out="$(cbr_run_provision_hook "$repo" "$wt")" \
  || fail "a passing hook must not fail the provision: $out"
[ -f "$wt/hook-ran.txt" ] || fail "the hook must run WITH THE WORKTREE AS CWD — hook-ran.txt missing"
grep -qx "$repo" "$wt/hook-ran.txt" || fail "the hook must receive the primary repo root as \$1"
grep -qx "$wt" "$wt/hook-ran.txt" || fail "the hook must receive the worktree as \$2"

printf '#!/bin/sh\nexit 3\n' > "$repo/.cbr/provision-hook.sh"
cbr_run_provision_hook "$repo" "$wt" >/dev/null 2>&1 \
  && fail "a failing hook must fail the provision — a half-prepared worktree is the trap this exists to remove"

chmod -x "$repo/.cbr/provision-hook.sh"
cbr_run_provision_hook "$repo" "$wt" >/dev/null 2>&1 \
  && fail "a present but non-executable hook is a misconfiguration and must fail loudly, not skip"

# ---------------------------------------------------------------------------
# WIRING — the leaves are RUN, not grepped: each provision is invoked against
# a scratch skeleton and the duties' observable effects are asserted, and each
# launch is proven to REFUSE a branch whose pin is no longer ancestral. The
# scratch repos lack this repo's real toolchain, so the leaf's repo-specific
# checks fail and provision exits non-zero — that is expected and irrelevant:
# what is asserted is that the duties RAN and their effects landed. Launch is
# only exercised on the reject path (a passing launch would dispatch a real
# session; the reject dies before any dispatch machinery).
# ---------------------------------------------------------------------------

# a divergent commit factory: a commit NOT in the given branch's history
make_divergent() { # repo
  git -C "$1" -c user.email=t@t -c user.name=t log >/dev/null 2>&1 || return 1
  ( cd "$1" \
    && git checkout -q --detach main \
    && printf 'x\n' >> divergence.txt \
    && git -c user.email=t@t -c user.name=t add divergence.txt \
    && git -c user.email=t@t -c user.name=t commit -qm divergent \
    && git rev-parse HEAD \
    && git checkout -q main )
}

seed_leaf_repo() { # dir  — a base branch with stale records and a passing hook
  local d="$1"
  mkdir -p "$d"
  git -C "$d" init -q -b main
  printf '# STATUS — stream: dead\nphase: COMPLETE\n' > "$d/STATUS.md"
  printf 'stream/dead — COMPLETE\n' > "$d/DONE.marker"
  printf 'real source\n' > "$d/app.txt"
  mkdir -p "$d/.cbr"
  printf '#!/bin/sh\ntouch hook-ran.txt\n' > "$d/.cbr/provision-hook.sh"
  chmod +x "$d/.cbr/provision-hook.sh"
  git -C "$d" -c user.email=t@t -c user.name=t add -A
  git -C "$d" -c user.email=t@t -c user.name=t commit -qm 'base with stale records'
}

assert_provision_effects() { # leafname repo worktree branch
  local name="$1" r="$2" w="$3" b="$4" pin
  [ -d "$w" ] || fail "$name provision did not create the worktree $w"
  [ -e "$w/STATUS.md" ] && fail "$name provision left the base's stale STATUS.md in the worktree"
  [ -e "$w/DONE.marker" ] && fail "$name provision left the base's stale DONE.marker in the worktree"
  [ -f "$w/hook-ran.txt" ] || fail "$name provision did not run .cbr/provision-hook.sh in the worktree"
  pin="$(git -C "$r" config --get "branch.$b.cbrBase" 2>/dev/null)" || pin=""
  [ "$pin" = "$(git -C "$r" rev-parse main)" ] \
    || fail "$name provision recorded pin '$pin', expected the base (main) sha"
}

printf 'dispatch prompt\n' > "$tmp/prompt.txt"

# ---- Claude leaf ----------------------------------------------------------
lr="$tmp/leafrepo"
seed_leaf_repo "$lr"
mkdir -p "$lr/skills/claude-controlled-build-run/scripts" \
         "$lr/skills/claude-controlled-build-run/references/core/scripts"
cp "$claude_leaf" "$lr/skills/claude-controlled-build-run/scripts/cbr.sh"
cp "$lib" "$lr/skills/claude-controlled-build-run/references/core/scripts/strand-lib.sh"
out_c="$( cd "$lr" && bash skills/claude-controlled-build-run/scripts/cbr.sh provision s1 stream/s1 --base main 2>&1 )" || true
assert_provision_effects "cbr.sh" "$lr" "$tmp/cockpit-s1" stream/s1

div="$(make_divergent "$lr")" || fail "could not make a divergent commit in the claude scratch repo"
git -C "$lr" config "branch.stream/s1.cbrBase" "$div"
rc=0
out_c="$( cd "$lr" && bash skills/claude-controlled-build-run/scripts/cbr.sh launch s1 --prompt-file "$tmp/prompt.txt" 2>&1 )" || rc=$?
[ "$rc" -ne 0 ] || fail "cbr.sh launch accepted a branch that does not contain its recorded base"
grep -q 'recorded base' <<<"$out_c" \
  || fail "cbr.sh launch must refuse FOR THE PIN REASON, got: $out_c"

# failing hook fails the provision run
printf '#!/bin/sh\nexit 3\n' > "$lr/.cbr/provision-hook.sh"
out_c="$( cd "$lr" && bash skills/claude-controlled-build-run/scripts/cbr.sh provision s2 stream/s2 --base main 2>&1 )" && \
  fail "cbr.sh provision must exit non-zero when the project hook fails"
grep -q 'provision hook failed' <<<"$out_c" \
  || fail "cbr.sh provision must report the hook failure, got: $out_c"

# ---- Codex leaf -----------------------------------------------------------
cr="$tmp/codexrepo"
seed_leaf_repo "$cr"
codex_dir="$cr/skills/codex-controlled-build-run"
mkdir -p "$codex_dir/scripts" "$codex_dir/references/cbr-core/scripts" "$codex_dir/templates"
cp "$codex_leaf" "$codex_dir/scripts/cbr-codex.sh"
cp "$lib" "$codex_dir/references/cbr-core/scripts/strand-lib.sh"
cp "$(dirname "$codex_leaf")/../templates/task_plan.skeleton.md" "$codex_dir/templates/" \
  || fail "codex task_plan.skeleton.md template not found next to the leaf"
printf '{"worktreeParent":"..","worktreePrefix":"codex-wt-","setupCommands":[],"toolchainProbe":"true"}\n' \
  > "$cr/.cbr-codex.json"
out_x="$( cd "$cr" && bash skills/codex-controlled-build-run/scripts/cbr-codex.sh provision c1 stream/c1 --base main 2>&1 )" || true
assert_provision_effects "cbr-codex.sh" "$cr" "$tmp/codex-wt-c1" stream/c1

# launch reject on a broken pin (provision.json is forced to PASS so the pin
# check — which comes right after it — is what actually refuses)
printf '{"result":"PASS","branch":"stream/c1","base":"main"}\n' > "$tmp/codex-wt-c1/.cbr-codex/provision.json"
div="$(make_divergent "$cr")" || fail "could not make a divergent commit in the codex scratch repo"
git -C "$cr" config "branch.stream/c1.cbrBase" "$div"
rc=0
out_x="$( cd "$cr" && bash skills/codex-controlled-build-run/scripts/cbr-codex.sh launch c1 --prompt-file "$tmp/prompt.txt" 2>&1 )" || rc=$?
[ "$rc" -ne 0 ] || fail "cbr-codex.sh launch accepted a branch that does not contain its recorded base"
grep -q 'recorded base' <<<"$out_x" \
  || fail "cbr-codex.sh launch must refuse FOR THE PIN REASON, got: $out_x"

# failing hook fails the provision run
printf '#!/bin/sh\nexit 3\n' > "$cr/.cbr/provision-hook.sh"
out_x="$( cd "$cr" && bash skills/codex-controlled-build-run/scripts/cbr-codex.sh provision c2 stream/c2 --base main 2>&1 )" && \
  fail "cbr-codex.sh provision must exit non-zero when the project hook fails"
grep -q 'provision hook' <<<"$out_x" \
  || fail "cbr-codex.sh provision must report the hook failure, got: $out_x"

echo "provision-duties.test PASS (stale records reset, base pin recorded+asserted, prep-hook socket, both leaves run end-to-end incl. launch pin-reject)"
