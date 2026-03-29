#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'USAGE'
Incrementally build and launch OpenSnek from the repo root.

Usage:
  ./run.sh [--clean] [--no-build]

Options:
  --clean       Do a clean rebuild before launch
  --no-build    Launch the existing app bundle without rebuilding
  -h, --help    Show this help
USAGE
}

terminate_existing_opensnek() {
  if ! pgrep -x OpenSnek >/dev/null 2>&1; then
    return
  fi

  echo "[open-snek] Requesting OpenSnek quit"
  osascript -e 'tell application id "io.opensnek.OpenSnek" to quit' >/dev/null 2>&1 || true

  for _ in {1..20}; do
    if ! pgrep -x OpenSnek >/dev/null 2>&1; then
      return
    fi
    sleep 0.1
  done

  echo "[open-snek] Stopping existing OpenSnek processes"
  pkill -x OpenSnek >/dev/null 2>&1 || true

  for _ in {1..20}; do
    if ! pgrep -x OpenSnek >/dev/null 2>&1; then
      return
    fi
    sleep 0.1
  done

  echo "[open-snek] Forcing OpenSnek shutdown"
  pkill -9 -x OpenSnek >/dev/null 2>&1 || true
}

BUILD_ARGS=()
SKIP_BUILD=false
CLEAN_BUILD=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean)
      CLEAN_BUILD=true
      shift
      ;;
    --no-build)
      SKIP_BUILD=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "$SKIP_BUILD" == true ]]; then
  if [[ "$CLEAN_BUILD" == true ]]; then
    echo "--clean cannot be combined with --no-build" >&2
    usage >&2
    exit 1
  fi

  terminate_existing_opensnek
  exec "$SCRIPT_DIR/OpenSnek/scripts/run_macos_app.sh"
fi

terminate_existing_opensnek
if [[ "$CLEAN_BUILD" == true ]]; then
  BUILD_ARGS+=(--clean)
fi

if [[ ${#BUILD_ARGS[@]} -gt 0 ]]; then
  "$SCRIPT_DIR/OpenSnek/scripts/build_macos_app.sh" "${BUILD_ARGS[@]}"
else
  "$SCRIPT_DIR/OpenSnek/scripts/build_macos_app.sh"
fi
exec "$SCRIPT_DIR/OpenSnek/scripts/run_macos_app.sh"
