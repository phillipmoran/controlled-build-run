#!/usr/bin/env bash
# Regression for the WARN-only tool-staleness probe (CBR-IMPROVEMENTS
# 2026-08-27: roborev sat 6 versions behind with nobody noticing).
# cbr_tool_staleness_report (cbr-core strand-lib) surfaces "tool behind" facts
# and NOTHING ELSE: it stays silent when tools are current, stays silent and
# exits 0 when the tools or the network are absent (fail open — a doctor probe
# must never block over its own infra), and both leaves' doctors wire it in.
# Hermetic: stub roborev/npm binaries on a scratch PATH; no network.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
lib="$root/skills/cbr-core/scripts/strand-lib.sh"
# kit fallback so a port can run this too
[ -f "$lib" ] || lib="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/skill/claude-controlled-build-run/references/core/scripts/strand-lib.sh"
[ -f "$lib" ] || { echo "tool-staleness.test FAIL: strand-lib.sh not found" >&2; exit 1; }

tmp="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
fail() { echo "tool-staleness.test FAIL: $1" >&2; exit 1; }

# shellcheck source=/dev/null
. "$lib"
command -v cbr_tool_staleness_report >/dev/null 2>&1 \
  || fail "cbr_tool_staleness_report not defined in strand-lib"

sys_path="/usr/bin:/bin"
mkdir -p "$tmp/bin" "$tmp/empty"

# --- stale tools: both lines surface, exit 0 ---
cat > "$tmp/bin/roborev" <<'EOF'
#!/bin/sh
[ "$1" = "update" ] || exit 1
echo "  Current version: v0.1.0"
echo "  Latest version:  v0.9.0"
EOF
cat > "$tmp/bin/npm" <<'EOF'
#!/bin/sh
echo "9.9.9"
EOF
chmod +x "$tmp/bin/roborev" "$tmp/bin/npm"

out="$(PATH="$tmp/bin:$sys_path" cbr_tool_staleness_report "1.9.0")" \
  || fail "probe exited non-zero on stale tools"
printf '%s\n' "$out" | grep -q "roborev.*0\.1\.0.*0\.9\.0" \
  || fail "no roborev staleness line in: $out"
printf '%s\n' "$out" | grep -q "probity.*1\.9\.0.*9\.9\.9" \
  || fail "no probity staleness line in: $out"

# --- current tools: total silence ---
cat > "$tmp/bin/roborev" <<'EOF'
#!/bin/sh
echo "  Current version: v0.9.0"
echo "  Latest version:  v0.9.0"
EOF
cat > "$tmp/bin/npm" <<'EOF'
#!/bin/sh
echo "1.9.0"
EOF
chmod +x "$tmp/bin/roborev" "$tmp/bin/npm"
out="$(PATH="$tmp/bin:$sys_path" cbr_tool_staleness_report "1.9.0")" \
  || fail "probe exited non-zero on current tools"
[ -z "$out" ] || fail "probe spoke when tools are current: $out"

# --- LOCALLY NEWER tools (dev build / deliberately newer pin): silence —
# "behind" is directional, not mere inequality ---
cat > "$tmp/bin/roborev" <<'EOF'
#!/bin/sh
echo "  Current version: v9.9.9"
echo "  Latest version:  v0.9.0"
EOF
cat > "$tmp/bin/npm" <<'EOF'
#!/bin/sh
echo "1.9.0"
EOF
chmod +x "$tmp/bin/roborev" "$tmp/bin/npm"
out="$(PATH="$tmp/bin:$sys_path" cbr_tool_staleness_report "9.9.9")" \
  || fail "probe exited non-zero on newer local tools"
[ -z "$out" ] || fail "probe called a NEWER local version stale: $out"

# --- equivalent forms (1.2 vs 1.2.0): silence — omitted components are zero ---
cat > "$tmp/bin/roborev" <<'EOF'
#!/bin/sh
echo "  Current version: v1.2"
echo "  Latest version:  v1.2.0"
EOF
cat > "$tmp/bin/npm" <<'EOF'
#!/bin/sh
echo "1.2.0"
EOF
chmod +x "$tmp/bin/roborev" "$tmp/bin/npm"
out="$(PATH="$tmp/bin:$sys_path" cbr_tool_staleness_report "1.2")" \
  || fail "probe exited non-zero on equivalent version forms"
[ -z "$out" ] || fail "probe called equivalent forms (1.2 vs 1.2.0) stale: $out"

# --- difference past the fourth component still detected ---
cat > "$tmp/bin/roborev" <<'EOF'
#!/bin/sh
echo "  Current version: v1.2.3.4.1"
echo "  Latest version:  v1.2.3.4.2"
EOF
chmod +x "$tmp/bin/roborev"
out="$(PATH="$tmp/bin:$sys_path" cbr_tool_staleness_report "1.2.0")" \
  || fail "probe exited non-zero on fifth-component difference"
printf '%s\n' "$out" | grep -q "roborev.*1\.2\.3\.4\.1.*1\.2\.3\.4\.2" \
  || fail "fifth-component difference not detected: $out"

# --- tools absent (or offline): silence, exit 0 — fail open ---
out="$(PATH="$tmp/empty:$sys_path" cbr_tool_staleness_report "1.9.0")" \
  || fail "probe failed closed with tools absent"
[ -z "$out" ] || fail "probe spoke with tools absent: $out"

# --- no pin known: probity check skipped silently, roborev still probes ---
out="$(PATH="$tmp/empty:$sys_path" cbr_tool_staleness_report "")" \
  || fail "probe failed closed with empty pin"
[ -z "$out" ] || fail "probe spoke with empty pin and no tools: $out"

# --- both leaves' doctors wire the probe ---
# Resolve each leaf like lib above: host layout first, package layout fallback.
pkg="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
claude_leaf="$root/skills/claude-controlled-build-run/scripts/cbr.sh"
[ -f "$claude_leaf" ] || claude_leaf="$pkg/skill/claude-controlled-build-run/scripts/cbr.sh"
codex_leaf="$root/skills/codex-controlled-build-run/scripts/cbr-codex.sh"
[ -f "$codex_leaf" ] || codex_leaf="$pkg/skill/codex-controlled-build-run/scripts/cbr-codex.sh"
grep -q "cbr_tool_staleness_report" "$claude_leaf" \
  || fail "Claude leaf doctor does not call cbr_tool_staleness_report"
grep -q "cbr_tool_staleness_report" "$codex_leaf" \
  || fail "Codex leaf doctor does not call cbr_tool_staleness_report"

echo "tool-staleness.test PASS"
