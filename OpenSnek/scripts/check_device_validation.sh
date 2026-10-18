#!/usr/bin/env bash
# Export code-owned metadata without opening hardware, then validate tracked evidence claims.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"
CATALOG="$(mktemp "${TMPDIR:-/tmp}/open-snek-catalog.XXXXXX")"
trap 'rm -f "$CATALOG"' EXIT
"$SCRIPT_DIR/checked_command.sh" swift build --disable-keychain --package-path OpenSnek --product OpenSnekProbe
swift run --skip-build --package-path OpenSnek OpenSnekProbe support-catalog > "$CATALOG"
python3 "$SCRIPT_DIR/check_device_validation.py" --catalog "$CATALOG" --manifest "$REPO_ROOT/docs/development/device-validation.json" --root "$REPO_ROOT"
