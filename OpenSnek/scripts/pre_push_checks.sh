#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$REPO_ROOT"
export OPEN_SNEK_HW="${OPEN_SNEK_HW:-0}"
MODE="${1:---fresh}"
if [[ $# -gt 1 || ( "$MODE" != "--fresh" && "$MODE" != "--reuse" ) ]]; then
  echo "Usage: pre_push_checks.sh [--fresh|--reuse]" >&2
  exit 2
fi
if [[ "$MODE" == "--reuse" ]] && python3 "$SCRIPT_DIR/validation_receipt.py" verify; then
  echo "[open-snek] Reusing recent full-check success for identical source, toolchain and environment."
  exit 0
fi
# A known failed fresh run must not leave an older success eligible for reuse.
python3 "$SCRIPT_DIR/validation_receipt.py" invalidate
BEFORE="$(python3 "$SCRIPT_DIR/validation_receipt.py" fingerprint)"
"$SCRIPT_DIR/check_swift_format.sh"

echo "[open-snek] Running SwiftLint..."
swift package --disable-keychain --package-path OpenSnek plugin --allow-writing-to-package-directory swiftlint

echo "[open-snek] Running Swift package tests..."
python3 -m unittest discover -s "$SCRIPT_DIR/tests"
# Bound compiler contention so the 200 ms diagnostic gate is useful on cold builds.
OPEN_SNEK_HW="${OPEN_SNEK_HW:-0}" "$SCRIPT_DIR/checked_command.sh" swift test --jobs 2 --disable-keychain --package-path OpenSnek
"$SCRIPT_DIR/check_device_validation.sh"
python3 "$SCRIPT_DIR/validation_receipt.py" record --before "$BEFORE"
