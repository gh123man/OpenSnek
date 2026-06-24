#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$PACKAGE_DIR/.swift-format"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Missing Swift format config: $CONFIG_FILE" >&2
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "Missing required command: xcrun" >&2
  exit 1
fi

if [[ $# -eq 0 ]]; then
  set -- "$PACKAGE_DIR/Package.swift" "$PACKAGE_DIR/Sources" "$PACKAGE_DIR/Tests" "$PACKAGE_DIR/scripts" "$PACKAGE_DIR/Plugins"
fi

echo "[open-snek] Checking Swift format..."
xcrun swift-format lint --configuration "$CONFIG_FILE" --recursive "$@"
