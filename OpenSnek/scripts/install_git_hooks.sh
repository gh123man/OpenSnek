#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PACKAGE_DIR/.." && pwd)"

git -C "$REPO_ROOT" config core.hooksPath .githooks
echo "Configured local git hooks path: .githooks"
echo "The pre-commit hook will regenerate OpenSnek.xcodeproj when staged changes require it."
