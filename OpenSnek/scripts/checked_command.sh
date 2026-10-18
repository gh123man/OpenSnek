#!/usr/bin/env bash
# Preserve the command's exit code and enforce diagnostic policy even on successful builds.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ $# -eq 0 ]]; then
  echo "Usage: checked_command.sh COMMAND [ARG ...]" >&2
  exit 2
fi
LOG="$(mktemp "${TMPDIR:-/tmp}/open-snek-command.XXXXXX")"
echo "[open-snek] Full command log: $LOG"
set +e
"$@" 2>&1 | tee "$LOG"
STATUSES=("${PIPESTATUS[@]}")
set -e
if [[ "${STATUSES[1]}" != 0 ]]; then
  echo "[open-snek] Could not capture the complete command log." >&2
  exit 1
fi
python3 "$SCRIPT_DIR/check_swift_diagnostics.py" "$LOG" || exit 1
exit "${STATUSES[0]}"
