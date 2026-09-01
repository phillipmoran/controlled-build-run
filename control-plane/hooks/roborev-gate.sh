#!/usr/bin/env bash
# RoboRev review gate (asyncRewake). After a git commit, wait for that
# commit's review; wake Claude (exit 2) ONLY on a real FAIL verdict. Silent
# on pass, infra hiccups, non-commits, and already-gated commits. Fails open.
# The wait is bounded by this hook's `timeout` field in settings.json — no
# reliance on an external `timeout` binary, which macOS does not ship.
# The rewakeMessage speaks the ADVISORY per-commit cadence, and may: this
# hook waits only on HEAD's own per-commit job, so a --branch review (whose
# FAIL is the PR boundary itself — actionable now) can never fire it.
set -uo pipefail

payload="$(cat)"
case "$payload" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

command -v roborev >/dev/null 2>&1 || exit 0
git_dir="$(git rev-parse --git-dir 2>/dev/null)" || exit 0
head_sha="$(git rev-parse HEAD 2>/dev/null)" || exit 0

# Idempotency: never gate the same HEAD twice.
state="$git_dir/roborev-gate-last-sha"
[ "$(cat "$state" 2>/dev/null || true)" = "$head_sha" ] && exit 0

# Block until this commit's review completes. 0=PASS; nonzero=FAIL/no-job/error.
# State is recorded only AFTER the wait returns, so a timeout-killed run leaves
# no footprint and a later invocation can still surface the late finding.
if roborev wait -q "$head_sha" >/dev/null 2>&1; then
  printf '%s' "$head_sha" > "$state"
  exit 0
fi

# Nonzero verdict means FAIL or no-review — a clean PASS already exited 0 above
# via `roborev wait` (verified: wait returns 0 for PASS, 1 for FAIL). Surface
# ONLY a real FAIL. Scope the infra checks to the FIRST line: a genuine
# "Error:" / "no review found" notice occupies line 1, whereas a real FAIL's
# finding prose may itself contain those words and must NOT be swallowed. We do
# NOT grep the body for "no issues found" — a PASS never reaches here, so that
# clause only risked suppressing a FAIL whose prose used the phrase (RoboRev
# job 99). The merge-path review gate stays the hard backstop regardless.
review="$(roborev show "$head_sha" 2>/dev/null)"
first_line="$(printf '%s\n' "$review" | head -1)"
if [ -z "$review" ] \
  || printf '%s\n' "$first_line" | grep -qiE '^error:|^no review found'; then
  printf '%s' "$head_sha" > "$state"
  exit 0
fi

printf '%s' "$head_sha" > "$state"
printf '%s\n' "$review"
exit 2
