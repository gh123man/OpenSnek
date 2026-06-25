#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOKS_DIR="$REPO_ROOT/.githooks"

if [[ ! -d "$HOOKS_DIR" ]]; then
  echo "Missing hooks directory: $HOOKS_DIR" >&2
  exit 1
fi

chmod +x "$HOOKS_DIR/pre-push"
git -C "$REPO_ROOT" config core.hooksPath .githooks

echo "[open-snek] Installed repo git hooks from .githooks"
