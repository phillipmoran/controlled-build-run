#!/usr/bin/env bash
# The four ratio tripwires fire on sick logs and stay silent on healthy ones.
#
#   prove-YES — each wire trips EXACTLY ONCE on a synthetic log built to
#     violate exactly its ratio: (1) >3 review-fix rounds on one stream's
#     open PR, (2) process commits >50% of the last 20, (3) >30min silence
#     with open review work, (4) zero product commits across active hours.
#   prove-NO — a healthy log (fresh activity, product-heavy commits, short
#     fix chains, cleared obligations) trips none.
set -euo pipefail

# the suite runs inside pre-commit hooks whose GIT_* env (index, dir) would
# poison the fixture repo's own git calls
while read -r v; do unset "$v"; done < <(env | sed -nE 's/^(GIT_[A-Z_]*|GITHEAD_[0-9a-f]*)=.*/\1/p')

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
wire="$root/skills/cbr-core/scripts/tripwires.sh"
[ -f "$wire" ] || wire="$(cd "$here/.." && pwd)/skill/claude-controlled-build-run/references/core/scripts/tripwires.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail() { echo "tripwires.test FAIL: $1" >&2; exit 1; }
[ -f "$wire" ] || fail "missing input: $wire"

now_ms=$(( $(date +%s) * 1000 ))
ev() { # ev <minutes-ago> <event_type> <payload-json>
  printf '{"event_type":"%s","event_time":%s,"payload":%s}\n' \
    "$2" "$(( now_ms - $1 * 60000 ))" "$3"
}
commit_ev() { # commit_ev <minutes-ago> <message>
  ev "$1" commit.created "{\"sha\":\"deadbee$1\",\"message\":\"$2\"}"
}

run_wires() { # run_wires <log> -> stdout: TRIP lines; rc 1 when any tripped
  CBR_TRIPWIRE_NOTIFY=echo "$wire" --log "$1" --now "$now_ms"
}

# --- healthy log: recent activity, product commits, no fix chain ------------
healthy="$tmp/healthy.jsonl"
{
  ev 200 session.boot '{}'
  for i in 9 8 7 6 5; do
    commit_ev $((i * 10)) "feat(core): product work $i"
    ev $((i * 10)) agent.working '{}'
  done
  commit_ev 20 "fix(kit): review 9001 — one honest round"
  ev 3 agent.working '{}'
  ev 2 review.obligation '{"open_count":0}'
} > "$healthy"
out="$(run_wires "$healthy")" || fail "a healthy log tripped a wire: $out"
[ -z "$out" ] || fail "a healthy log produced output: $out"

# --- wire 1: >3 review-fix rounds since the stream's last merge -------------
w1="$tmp/rounds.jsonl"
{
  ev 300 session.boot '{}'
  ev 3 agent.working '{}'
  ev 2 review.obligation '{"open_count":0}'
  commit_ev 90 "feat(core): the feature itself"
  for i in 1 2 3; do
    commit_ev $((80 - i * 10)) "fix(core): review 900$i — round $i"
  done
  # plural subjects are sanctioned grammar and must count toward the cap
  commit_ev 40 "fix(core): reviews 9004/9005 — batched round 4"
} > "$w1"
rc=0; out="$(run_wires "$w1")" || rc=$?
[ "$rc" -ne 0 ] || fail "4 review-fix rounds did not trip the rounds wire"
[ "$(grep -c '^TRIP rounds' <<<"$out")" -eq 1 ] || fail "rounds wire did not trip exactly once: $out"
grep -q '^TRIP rounds' <<<"$out" || fail "wrong wire tripped for the fix chain: $out"

# --- wire 2: process commits >50% of the last 20 ----------------------------
w2="$tmp/process.jsonl"
{
  ev 300 session.boot '{}'
  ev 3 agent.working '{}'
  ev 2 review.obligation '{"open_count":0}'
  for i in $(seq 1 14); do
    commit_ev $((i + 30)) "docs(records): rotation $i"
  done
  for i in $(seq 1 6); do
    commit_ev $((i + 10)) "feat(app): product $i"
  done
} > "$w2"
rc=0; out="$(run_wires "$w2")" || rc=$?
[ "$rc" -ne 0 ] || fail "14/20 process commits did not trip the ratio wire"
[ "$(grep -c '^TRIP process-share' <<<"$out")" -eq 1 ] || fail "process-share wire did not trip exactly once: $out"

# --- wire 3: silence >30min while review work is open -----------------------
w3="$tmp/silence.jsonl"
{
  ev 300 session.boot '{}'
  commit_ev 200 "feat(core): before the quiet"
  ev 45 agent.working '{}'
  ev 44 review.obligation '{"open_count":2}'
} > "$w3"
rc=0; out="$(run_wires "$w3")" || rc=$?
[ "$rc" -ne 0 ] || fail "45min of silence with open reviews did not trip the silence wire"
[ "$(grep -c '^TRIP silence' <<<"$out")" -eq 1 ] || fail "silence wire did not trip exactly once: $out"

# silence with NO open work is rest, not a stall
w3b="$tmp/rest.jsonl"
{
  ev 300 session.boot '{}'
  commit_ev 200 "feat(core): done for the day"
  ev 45 agent.working '{}'
  ev 44 review.obligation '{"open_count":0}'
} > "$w3b"
out="$(run_wires "$w3b")" || fail "quiet rest (no open work) tripped: $out"

# --- wire 4: active hours with zero product commits -------------------------
w4="$tmp/spin.jsonl"
{
  ev 300 session.boot '{}'
  # activity spread across >3 distinct hours, all commits process-typed
  for m in 250 190 130 70 10; do
    ev "$m" agent.working '{}'
    commit_ev "$m" "docs(records): busywork at $m"
  done
  ev 3 agent.working '{}'
  ev 2 review.obligation '{"open_count":0}'
} > "$w4"
rc=0; out="$(run_wires "$w4")" || rc=$?
[ "$rc" -ne 0 ] || fail "hours of process-only activity did not trip the product wire"
[ "$(grep -c '^TRIP no-product' <<<"$out")" -eq 1 ] || fail "no-product wire did not trip exactly once: $out"

# --- a merge boundary resets the window: the same fix chain, then a merge ----
w1m="$tmp/rounds-merged.jsonl"
{
  cat "$w1"
  ev 5 stream.merged '{"branch":"feature/x","sha":"cafe1234"}'
} > "$w1m"
out="$(run_wires "$w1m")" || fail "a stream.merged boundary did not settle the fix chain: $out"

# --- default log resolution: primary-worktree slug, dots mapped to dashes ---
repo="$tmp/repo.v2"
git init -q "$repo"
git -C "$repo" commit -q --allow-empty -m seed
git -C "$repo" worktree add -q "$tmp/linked-wt" -b probe >/dev/null 2>&1
home="$tmp/home"
mkdir -p "$home/.cbr/events"
# slug from git's own view of the primary path (mktemp's /var vs /private/var)
slug="$(git -C "$tmp/linked-wt" worktree list --porcelain | sed -n '1s/^worktree //p' | tr '/.' '--')"
cp "$w3" "$home/.cbr/events/$slug.jsonl"
rc=0
out="$(cd "$tmp/linked-wt" && HOME="$home" CBR_TRIPWIRE_NOTIFY=echo \
  bash "$wire" --now "$now_ms")" || rc=$?
[ "$rc" -ne 0 ] || fail "a linked worktree did not resolve the primary's dotted-path log"
grep -q '^TRIP silence' <<<"$out" || fail "resolved log produced wrong wires: $out"

# --- notification: a trip reaches the human channel -------------------------
log="$tmp/notify.log"
CBR_TRIPWIRE_NOTIFY="$tmp/notify.sh" "$wire" --log "$w3" --now "$now_ms" >/dev/null 2>&1 || true
cat > "$tmp/notify.sh" <<'SH'
#!/bin/sh
echo "$*" >> "${NOTIFY_LOG:?}"
SH
chmod +x "$tmp/notify.sh"
NOTIFY_LOG="$log" CBR_TRIPWIRE_NOTIFY="$tmp/notify.sh" "$wire" --log "$w3" --now "$now_ms" >/dev/null 2>&1 || true
[ -s "$log" ] || fail "a tripped wire never reached the notify channel"
grep -q 'silence' "$log" || fail "the notification does not name the tripped wire: $(cat "$log")"

echo "tripwires.test PASS (healthy silent; rounds, process-share, silence, no-product each trip once; rest is not a stall; notify fires)"
