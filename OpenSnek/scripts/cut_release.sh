#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Cut a tagged OpenSnek release from main.

Usage:
  cut_release.sh --version <semver> [--skip-tests]

Options:
  --version <semver>   Release version without leading v (required)
  --skip-tests         Skip swift test preflight
  -h, --help           Show this help
USAGE
}

VERSION=""
SKIP_TESTS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --skip-tests)
      SKIP_TESTS=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  echo "--version is required" >&2
  usage
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PACKAGE_DIR/.." && pwd)"
TAG="v$VERSION"

if [[ -n "$(git -C "$REPO_ROOT" status --short)" ]]; then
  echo "Working tree must be clean before cutting a release." >&2
  exit 1
fi

git -C "$REPO_ROOT" fetch origin main --tags
git -C "$REPO_ROOT" checkout main
git -C "$REPO_ROOT" pull --ff-only origin main

if git -C "$REPO_ROOT" rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "Tag already exists: $TAG" >&2
  exit 1
fi

if [[ "$SKIP_TESTS" == false ]]; then
  swift test --package-path "$PACKAGE_DIR"
fi

git -C "$REPO_ROOT" tag -a "$TAG" -m "OpenSnek $VERSION"
git -C "$REPO_ROOT" push origin main
git -C "$REPO_ROOT" push origin "$TAG"

echo "Pushed $TAG from main."
