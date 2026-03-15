#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PACKAGE_DIR/.." && pwd)"
PROJECT_DIR="$PACKAGE_DIR/OpenSnek.xcodeproj"

"$SCRIPT_DIR/generate_xcodeproj.sh"

if ! git -C "$REPO_ROOT" diff --quiet -- "$PROJECT_DIR"; then
  echo "OpenSnek.xcodeproj is out of sync with project.yml. Re-run OpenSnek/scripts/generate_xcodeproj.sh and commit the result." >&2
  git -C "$REPO_ROOT" diff -- "$PROJECT_DIR"
  exit 1
fi

echo "OpenSnek.xcodeproj is in sync with project.yml."
