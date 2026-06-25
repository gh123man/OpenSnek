#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$REPO_ROOT"

"$SCRIPT_DIR/check_swift_format.sh"

echo "[open-snek] Running SwiftLint..."
swift package --package-path OpenSnek plugin --allow-writing-to-package-directory swiftlint

echo "[open-snek] Running Swift package tests..."
OPEN_SNEK_HW="${OPEN_SNEK_HW:-0}" swift test --package-path OpenSnek
