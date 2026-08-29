#!/usr/bin/env bash
# run_gemini.sh — run one Gemini 3.1 Pro panelist on a prompt, with web search + bash.
#
# Usage:
#   run_gemini.sh <prompt_file> <output_file>
#
# Gemini's CLI is NOT installed on this machine yet. This script degrades gracefully:
# if `gemini` is missing it exits non-zero with a clear message so the orchestrator can
# drop Gemini from the panel and continue (downgrading the slug to opus4.8-gpt5.5).
#
# To enable: install the Gemini CLI and confirm `gemini --version` works, then adjust the
# invocation below to match its non-interactive interface (flag names vary by version).

set -uo pipefail

prompt_file="${1:?usage: run_gemini.sh <prompt_file> <output_file>}"
output_file="${2:?usage: run_gemini.sh <prompt_file> <output_file>}"

if ! command -v gemini >/dev/null 2>&1; then
  echo "[run_gemini.sh] gemini CLI not installed — skip this panelist." >&2
  exit 127
fi

# Non-interactive Gemini run. Adjust flags to your installed gemini version if needed.
# Many builds accept the prompt on stdin and stream to stdout; we capture stdout as the answer.
gemini --model gemini-3.1-pro --yolo --prompt "$(cat "$prompt_file")" > "$output_file" 2> >(tail -20 >&2)

status=$?
if [ $status -ne 0 ] || [ ! -s "$output_file" ]; then
  echo "[run_gemini.sh] gemini exited $status or produced no output." >&2
  exit 1
fi
echo "[run_gemini.sh] ok -> $output_file"
