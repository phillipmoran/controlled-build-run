#!/usr/bin/env bash
# Regression for the node_modules brick self-check (cbr.sh brick, which doctor
# runs): the two states that have each cost a half-day outage are (1) a dangling
# package link — Probity fails CLOSED on config load and every gated tool
# blocks — and (2) links that resolve into ANOTHER checkout's store (a pnpm
# install run inside a symlink-provisioned worktree rewrites the primary's
# links), which works until that worktree is reaped and then kills the whole
# toolchain. The check must name each state, print the repair, and NEVER
# suggest `pnpm install` — that command is how state (2) happens.
# Hermetic: fake pnpm-shaped stores under mktemp; the real repo is untouched.
set -euo pipefail

for v in $(env | sed -n 's/^\(GIT_[A-Z_]*\)=.*/\1/p'); do unset "$v"; done

cbr="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/skills/claude-controlled-build-run/scripts/cbr.sh"
[ -x "$cbr" ] || cbr="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/skill/claude-controlled-build-run/scripts/cbr.sh"
tmp="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
fail() { echo "doctor-brick.test FAIL: $1" >&2; exit 1; }

# A minimal pnpm-shaped store: real package dirs under .pnpm, top-level links
# pointing into them — the exact layout the detector must read as healthy.
mk_store() { # $1 = repo root
  mkdir -p "$1/node_modules/.pnpm/pkg@1.0.0/node_modules/pkg" \
           "$1/node_modules/.pnpm/@scope+dep@1.0.0/node_modules/@scope/dep" \
           "$1/node_modules/@scope"
  ln -s ".pnpm/pkg@1.0.0/node_modules/pkg" "$1/node_modules/pkg"
  ln -s "../.pnpm/@scope+dep@1.0.0/node_modules/@scope/dep" "$1/node_modules/@scope/dep"
}

# 1) healthy primary: no brick lines, zero counts
mkdir -p "$tmp/healthy"; mk_store "$tmp/healthy"
# A workspace package link (node_modules/@x/pkg → sibling source dir) resolves
# inside the repo but outside node_modules — sanctioned, never foreign.
mkdir -p "$tmp/healthy/packages/ws" "$tmp/healthy/node_modules/@cbr"
ln -s "../../packages/ws" "$tmp/healthy/node_modules/@cbr/ws"
out="$("$cbr" brick "$tmp/healthy" 2>&1)" || fail "brick check gated a healthy store (facts only, must exit 0): $out"
grep -q "BRICK" <<<"$out" && fail "healthy store (with a workspace link) flagged as bricked: $out"
grep -q "SUMMARY .*dangling=0 foreign=0" <<<"$out" || fail "healthy store missing zero-count summary: $out"

# 2) dangling link: the fail-closed brick, with repair and the pnpm-install ban
mkdir -p "$tmp/dangling"; mk_store "$tmp/dangling"
rm -rf "$tmp/dangling/node_modules/.pnpm/pkg@1.0.0"
out="$("$cbr" brick "$tmp/dangling" 2>&1)" || true
grep -q "BRICK.*pkg" <<<"$out" || fail "dangling link not flagged: $out"
grep -qi "fails* CLOSED" <<<"$out" || fail "dangling report must say why it bricks (Probity fails closed): $out"
grep -qi "NEVER.*pnpm install" <<<"$out" || fail "repair must ban pnpm install by name: $out"
grep -q "SUMMARY .*dangling=1" <<<"$out" || fail "dangling count wrong: $out"

# 3) foreign link: primary's link rewritten to point into a worktree's store —
#    resolves fine today, dies when that worktree is reaped
mkdir -p "$tmp/foreign"; mk_store "$tmp/foreign"
mkdir -p "$tmp/wt"; mk_store "$tmp/wt"
rm "$tmp/foreign/node_modules/pkg"
ln -s "$tmp/wt/node_modules/.pnpm/pkg@1.0.0/node_modules/pkg" "$tmp/foreign/node_modules/pkg"
out="$("$cbr" brick "$tmp/foreign" 2>&1)" || true
grep -q "BRICK.*pkg" <<<"$out" || fail "foreign link not flagged: $out"
grep -qi "reap" <<<"$out" || fail "foreign report must warn about reaping the checkout it points into: $out"
grep -qi "NEVER.*pnpm install" <<<"$out" || fail "foreign repair must ban pnpm install by name: $out"
grep -q "SUMMARY .*foreign=1" <<<"$out" || fail "foreign count wrong: $out"

# 4) symlink-provisioned worktree: node_modules ITSELF links to the primary's.
#    Every entry resolves outside the worktree but inside the linked store —
#    that is the sanctioned provisioning, not a brick.
mkdir -p "$tmp/worktree"
ln -s "$tmp/healthy/node_modules" "$tmp/worktree/node_modules"
out="$("$cbr" brick "$tmp/worktree" 2>&1)" || fail "brick check gated a symlink-provisioned worktree: $out"
grep -q "BRICK" <<<"$out" && fail "symlink-provisioned worktree flagged as bricked: $out"
grep -q "SUMMARY .*dangling=0 foreign=0" <<<"$out" || fail "provisioned worktree missing zero-count summary: $out"

# 3b) foreign link into a NESTED worktree: the live codex layout registers
#     worktrees under the primary's own directory (.claude/worktrees), so a
#     link rewritten into one sits under the anchor and would read healthy —
#     while reaping that worktree still kills the toolchain. Targets under
#     another registered worktree of the same repo are foreign wherever the
#     worktree lives.
mkdir -p "$tmp/gitrepo"
(
  cd "$tmp/gitrepo"
  git init -q -b main; echo x > f
  git -c user.email=t@t -c user.name=t add -A
  git -c user.email=t@t -c user.name=t commit -qm base
  mkdir -p .claude/worktrees
  git worktree add -q .claude/worktrees/wt1 -b stream/wt1
)
mk_store "$tmp/gitrepo"
mk_store "$tmp/gitrepo/.claude/worktrees/wt1"
rm "$tmp/gitrepo/node_modules/pkg"
ln -s "$tmp/gitrepo/.claude/worktrees/wt1/node_modules/.pnpm/pkg@1.0.0/node_modules/pkg" "$tmp/gitrepo/node_modules/pkg"
out="$("$cbr" brick "$tmp/gitrepo" 2>&1)" || true
grep -q "BRICK-IN-WAITING.*node_modules/pkg" <<<"$out" \
  || fail "link into a NESTED registered worktree read as healthy — the live layout's brick-in-waiting missed: $out"
grep -q "SUMMARY .*foreign=1" <<<"$out" || fail "nested-worktree foreign count wrong: $out"

# 3c) the nested worktree's OWN store must stay healthy when brick runs
#     from inside it: the primary is that worktree's ANCESTOR, and carving
#     an ancestor out of the anchor branded every local target foreign.
#     (wt1's own store was built by the 3b fixture above.)
out="$("$cbr" brick "$tmp/gitrepo/.claude/worktrees/wt1" 2>&1)" \
  || fail "brick gated a nested worktree's own healthy store: $out"
grep -q "BRICK" <<<"$out" && fail "nested worktree's local store flagged foreign — the ancestor primary was carved out of its anchor: $out"

# 3d) a per-package store that is ITSELF a dangling symlink is a brick, not
#     a skip: [ -d ] is false for it, and skipping returns the passing zero.
mkdir -p "$tmp/pkgdangle/packages/pkg-a"; mk_store "$tmp/pkgdangle"
ln -s "$tmp/never/node_modules" "$tmp/pkgdangle/packages/pkg-a/node_modules"
out="$("$cbr" brick "$tmp/pkgdangle" 2>&1)" || true
grep -q "BRICK.*packages/pkg-a" <<<"$out" || fail "dangling per-package store symlink not flagged: $out"
grep -q "SUMMARY .*dangling=1" <<<"$out" || fail "dangling per-package store must count as dangling: $out"

# 4b) node_modules ITSELF is a dangling symlink — the reaped-primary state:
#     the provisioning link outlived its target. This is a brick, not an
#     unprovisioned folder, and must never read as a passing "absent".
mkdir -p "$tmp/reaped"
ln -s "$tmp/never-existed/node_modules" "$tmp/reaped/node_modules"
out="$("$cbr" brick "$tmp/reaped" 2>&1)" || true
grep -q "BRICK" <<<"$out" || fail "dangling root node_modules link not flagged as a brick: $out"
grep -q "SUMMARY .*dangling=1" <<<"$out" || fail "dangling root link must count as dangling, not absent: $out"
grep -q "store=absent" <<<"$out" && fail "dangling root link reported as store=absent — the summary the doctors treat as passing: $out"

# 5) no node_modules at all: a fact worth naming (unprovisioned worktree bricks
#    itself the moment the config imports anything), never a crash
mkdir -p "$tmp/bare"
out="$("$cbr" brick "$tmp/bare" 2>&1)" || fail "brick check crashed on a repo with no node_modules: $out"
grep -qi "no node_modules" <<<"$out" || fail "missing node_modules not named: $out"

# Per-package stores (packages/*/node_modules, adapters/*/node_modules) get
# the same classification: provisioning links them too, and a dangling link
# there bricks that package's toolchain just as hard.
mkdir -p "$tmp/nested/packages/pkg-a/node_modules" "$tmp/nested/adapters/ad-b/node_modules"
mk_store "$tmp/nested"
ln -s "$tmp/gone-forever" "$tmp/nested/packages/pkg-a/node_modules/deadlink"
ln -s "$tmp/wt/node_modules/.pnpm/pkg@1.0.0/node_modules/pkg" "$tmp/nested/adapters/ad-b/node_modules/pkg"
out="$("$cbr" brick "$tmp/nested" 2>&1)" || true
grep -q "BRICK.*packages/pkg-a.*deadlink" <<<"$out" || fail "dangling per-package link not flagged: $out"
grep -q "BRICK-IN-WAITING.*adapters/ad-b" <<<"$out" || fail "foreign per-package link not flagged: $out"
grep -q "SUMMARY .*dangling=1 foreign=1" <<<"$out" || fail "nested counts wrong: $out"

# Both leaves must grade with the SAME shared mechanism (strand-lib) — two
# implementations of a brick verdict would disagree exactly when it matters.
cbx="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/skills/codex-controlled-build-run/scripts/cbr-codex.sh"
[ -x "$cbx" ] || cbx="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/skill/codex-controlled-build-run/scripts/cbr-codex.sh"
out="$("$cbx" brick "$tmp/dangling" 2>&1)" || true
grep -q "BRICK.*pkg" <<<"$out" || fail "codex leaf did not flag the dangling link: $out"
out="$("$cbx" brick "$tmp/healthy" 2>&1)" || fail "codex leaf gated a healthy store: $out"
grep -q "BRICK" <<<"$out" && fail "codex leaf flagged a healthy store: $out"

echo "doctor-brick.test OK: dangling and foreign links flagged with repairs (pnpm install banned by name); healthy primary, symlink-provisioned worktree, and bare repo all pass clean"
