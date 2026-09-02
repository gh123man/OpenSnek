#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Build a local macOS .app bundle for OpenSnek.

This uses the canonical Xcode app target when full Xcode is available. On a
Command Line Tools-only host it builds with SwiftPM and assembles the same
`OpenSnek/.dist/OpenSnek.app` path so local launches can reuse a stable bundle
path for TCC/Input Monitoring.

Usage:
  build_macos_app.sh [options]

Options:
  --clean                          Clean the existing build products before rebuilding
  --configuration <debug|release>   Build configuration (default: debug)
  --output <dir>                    Output directory for .app (default: OpenSnek/.dist)
  --bundle-id <id>                  CFBundleIdentifier override (default: io.opensnek.OpenSnek)
  --version <semver>                CFBundleShortVersionString override (default: project setting)
  --build-number <value>            CFBundleVersion override (default: 1)
  --build-channel <dev|release>     OpenSnek build channel metadata (default: derived from configuration)
  --sign-identity <value>           Signing identity: auto|preserve|adhoc|none|<codesign identity>
  --open                            Open app after build
  -h, --help                        Show this help

Environment overrides:
  OPEN_SNEK_BUNDLE_ID
  OPEN_SNEK_VERSION
  OPEN_SNEK_BUILD_NUMBER
  OPEN_SNEK_BUILD_CHANNEL
  OPEN_SNEK_SIGN_IDENTITY
  OPEN_SNEK_SPARKLE_PUBLIC_ED_KEY
USAGE
}

CONFIGURATION="debug"
OUTPUT_DIR=""
BUNDLE_ID="${OPEN_SNEK_BUNDLE_ID:-io.opensnek.OpenSnek}"
VERSION="${OPEN_SNEK_VERSION:-}"
BUILD_NUMBER="${OPEN_SNEK_BUILD_NUMBER:-1}"
BUILD_CHANNEL="${OPEN_SNEK_BUILD_CHANNEL:-}"
SIGN_IDENTITY="${OPEN_SNEK_SIGN_IDENTITY:-auto}"
SPARKLE_PUBLIC_ED_KEY="${OPEN_SNEK_SPARKLE_PUBLIC_ED_KEY:-}"
OPEN_AFTER_BUILD=false
CLEAN_BUILD=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean)
      CLEAN_BUILD=true
      shift
      ;;
    --configuration)
      CONFIGURATION="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --bundle-id)
      BUNDLE_ID="${2:-}"
      shift 2
      ;;
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --build-number)
      BUILD_NUMBER="${2:-}"
      shift 2
      ;;
    --build-channel)
      BUILD_CHANNEL="${2:-}"
      shift 2
      ;;
    --sign-identity)
      SIGN_IDENTITY="${2:-}"
      shift 2
      ;;
    --open)
      OPEN_AFTER_BUILD=true
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

if [[ "$CONFIGURATION" != "debug" && "$CONFIGURATION" != "release" ]]; then
  echo "Invalid configuration: $CONFIGURATION" >&2
  exit 1
fi

if [[ -z "$BUILD_CHANNEL" ]]; then
  if [[ "$CONFIGURATION" == "debug" ]]; then
    BUILD_CHANNEL="dev"
  else
    BUILD_CHANNEL="release"
  fi
fi

if [[ "$BUILD_CHANNEL" != "dev" && "$BUILD_CHANNEL" != "release" ]]; then
  echo "Invalid build channel: $BUILD_CHANNEL" >&2
  exit 1
fi

require_cmd() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "Missing required command: $name" >&2
    exit 1
  fi
}

detect_project_marketing_version() {
  local spec_file="$1"
  awk '/MARKETING_VERSION:/{print $2; exit}' "$spec_file"
}

detect_preferred_sign_identity() {
  if ! command -v security >/dev/null 2>&1; then
    return 1
  fi

  local identities
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  if [[ -z "$identities" ]]; then
    return 1
  fi

  local preferred
  preferred="$(printf '%s\n' "$identities" | awk -F'"' '/"Apple Development:/{print $2; exit}')"
  if [[ -z "$preferred" ]]; then
    preferred="$(printf '%s\n' "$identities" | awk -F'"' '/"Developer ID Application:/{print $2; exit}')"
  fi
  if [[ -z "$preferred" ]]; then
    return 1
  fi

  printf '%s\n' "$preferred"
}

identity_is_available() {
  local requested="$1"
  [[ -n "$requested" ]] || return 1
  [[ "$requested" == "adhoc" || "$requested" == "-" ]] && return 0
  [[ "$requested" == "none" || "$requested" == "auto" || "$requested" == "preserve" ]] && return 1
  command -v security >/dev/null 2>&1 || return 1

  security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/"/{print $2}' | grep -Fx -- "$requested" >/dev/null 2>&1
}

detect_existing_sign_identity() {
  local app_bundle="$1"
  [[ -d "$app_bundle" ]] || return 1
  local details
  details="$(codesign -dv --verbose=4 "$app_bundle" 2>&1 || true)"
  [[ -n "$details" ]] || return 1

  if printf '%s\n' "$details" | grep -q '^Signature=adhoc$'; then
    printf '%s\n' "adhoc"
    return 0
  fi

  local authority
  authority="$(printf '%s\n' "$details" | awk -F= '/^Authority=/{print $2; exit}')"
  [[ -n "$authority" ]] || return 1
  printf '%s\n' "$authority"
  return 0
}

resolve_sign_identity() {
  local requested="$1"
  local existing="$2"

  case "$requested" in
    preserve)
      if [[ -n "$existing" ]] && { [[ "$existing" == "adhoc" || "$existing" == "-" ]] || identity_is_available "$existing"; }; then
        printf '%s\n' "$existing"
      else
        printf '%s\n' "auto"
      fi
      ;;
    auto)
      if [[ -n "$existing" && "$existing" != "adhoc" && "$existing" != "-" ]] && identity_is_available "$existing"; then
        printf '%s\n' "$existing"
      else
        printf '%s\n' "auto"
      fi
      ;;
    *)
      printf '%s\n' "$requested"
      ;;
  esac
}

ensure_generated_project() {
  xcodegen \
    --quiet \
    --use-cache \
    --spec "$SPEC_FILE" \
    --project "$PACKAGE_DIR"
}

print_xcodebuild_failure() {
  local log_file="$1"

  echo "[open-snek] Xcode build failed. Relevant diagnostics:" >&2
  if ! rg -n "error:|warning:" "$log_file" >&2; then
    tail -n 80 "$log_file" >&2 || true
  fi
  echo "[open-snek] Full xcodebuild log: $log_file" >&2
}

find_compatible_swift() {
  local candidate
  local candidates=()

  if command -v swift >/dev/null 2>&1; then
    candidates+=("$(command -v swift)")
  fi
  candidates+=(
    "/opt/homebrew/opt/swift/bin/swift"
    "/usr/local/opt/swift/bin/swift"
  )

  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]] && "$candidate" package --package-path "$PACKAGE_DIR" dump-package >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

has_full_xcode() {
  command -v xcodebuild >/dev/null 2>&1 && xcodebuild -version >/dev/null 2>&1
}

stage_swiftpm_app() {
  local swift_bin_path="$1"
  local built_executable="$swift_bin_path/$PRODUCT_NAME"
  local built_framework="$swift_bin_path/Sparkle.framework"
  local contents_dir="$APP_BUNDLE/Contents"
  local executable_dir="$contents_dir/MacOS"
  local frameworks_dir="$contents_dir/Frameworks"
  local resources_dir="$contents_dir/Resources"
  local info_plist="$contents_dir/Info.plist"
  local icon_source_dir="$PACKAGE_DIR/App/Resources/Assets.xcassets/AppIcon.appiconset"
  local icon_work_dir
  local iconset_dir

  if [[ ! -x "$built_executable" ]]; then
    echo "Built executable not found: $built_executable" >&2
    exit 1
  fi
  if [[ ! -d "$built_framework" ]]; then
    echo "Built Sparkle framework not found: $built_framework" >&2
    exit 1
  fi

  rm -rf "$APP_BUNDLE"
  mkdir -p "$executable_dir" "$frameworks_dir" "$resources_dir"
  ditto "$built_executable" "$executable_dir/$PRODUCT_NAME"
  ditto "$built_framework" "$frameworks_dir/Sparkle.framework"
  ditto "$PACKAGE_DIR/App/Resources/snek-menu-template.png" "$resources_dir/snek-menu-template.png"
  ditto "$PACKAGE_DIR/App/Resources/snek-menu.png" "$resources_dir/snek-menu.png"

  install_name_tool -add_rpath "@executable_path/../Frameworks" "$executable_dir/$PRODUCT_NAME"

  ditto "$PACKAGE_DIR/App/Info.plist" "$info_plist"
  plutil -replace CFBundleDevelopmentRegion -string "en" "$info_plist"
  plutil -replace CFBundleExecutable -string "$PRODUCT_NAME" "$info_plist"
  plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$info_plist"
  plutil -replace CFBundleName -string "$PRODUCT_NAME" "$info_plist"
  plutil -replace CFBundleShortVersionString -string "$VERSION" "$info_plist"
  plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$info_plist"
  plutil -replace LSMinimumSystemVersion -string "14.0" "$info_plist"
  plutil -replace OpenSnekBuildChannel -string "$BUILD_CHANNEL" "$info_plist"
  plutil -replace SUPublicEDKey -string "$SPARKLE_PUBLIC_ED_KEY" "$info_plist"
  plutil -insert CFBundleIconFile -string "OpenSnek.icns" "$info_plist"

  icon_work_dir="$(mktemp -d "${TMPDIR:-/tmp}/open_snek_icon.XXXXXX")"
  iconset_dir="$icon_work_dir/OpenSnek.iconset"
  mkdir -p "$iconset_dir"
  for icon_file in "$icon_source_dir"/icon_*.png; do
    ditto "$icon_file" "$iconset_dir/$(basename "$icon_file")"
  done
  iconutil --convert icns --output "$resources_dir/OpenSnek.icns" "$iconset_dir"
  rm -rf "$icon_work_dir"
}

build_with_swiftpm() {
  local swift_command="$1"
  local swift_scratch_path="$DERIVED_DATA_PATH/SwiftPM"
  local swift_cache_path="$DERIVED_DATA_PATH/SwiftPMCache"
  local swift_config_path="$DERIVED_DATA_PATH/SwiftPMConfig"
  local swift_security_path="$DERIVED_DATA_PATH/SwiftPMSecurity"
  local module_cache_path="$DERIVED_DATA_PATH/ModuleCache"
  local developer_dir=""
  local swift_environment=(env "CLANG_MODULE_CACHE_PATH=$module_cache_path")
  local swift_arguments=(
    --disable-keychain
    --package-path "$PACKAGE_DIR"
    --scratch-path "$swift_scratch_path"
    --cache-path "$swift_cache_path"
    --config-path "$swift_config_path"
    --security-path "$swift_security_path"
    --configuration "$CONFIGURATION"
  )

  if developer_dir="$(xcode-select -p 2>/dev/null)" && [[ -d "$developer_dir/usr/lib/sourcekitdInProc.framework" ]]; then
    swift_environment+=("XCODE_DEFAULT_TOOLCHAIN_OVERRIDE=$developer_dir")
  fi

  if [[ "$CLEAN_BUILD" == true ]]; then
    rm -rf "$swift_scratch_path" "$module_cache_path"
  fi
  mkdir -p "$swift_cache_path" "$swift_config_path" "$swift_security_path" "$module_cache_path"

  echo "[open-snek] Full Xcode unavailable; building $PRODUCT_NAME ($CONFIGURATION) with SwiftPM..."
  "${swift_environment[@]}" "$swift_command" build "${swift_arguments[@]}" --product "$PRODUCT_NAME"

  local swift_bin_path
  swift_bin_path="$("${swift_environment[@]}" "$swift_command" build "${swift_arguments[@]}" --show-bin-path)"
  stage_swiftpm_app "$swift_bin_path"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$PACKAGE_DIR/.dist}"
PROJECT_FILE="$PACKAGE_DIR/OpenSnek.xcodeproj"
SPEC_FILE="$PACKAGE_DIR/project.yml"
PRODUCT_NAME="OpenSnek"
DISPLAY_NAME="OpenSnek"
APP_BUNDLE="$OUTPUT_DIR/$DISPLAY_NAME.app"
DERIVED_DATA_PATH="$OUTPUT_DIR/.derived-data"
XCODEBUILD_LOG=""
PRESERVE_NESTED_SIGNATURES=false

require_cmd ditto

"$SCRIPT_DIR/check_swift_format.sh"

if [[ -z "$VERSION" ]]; then
  VERSION="$(detect_project_marketing_version "$SPEC_FILE")"
fi
VERSION="${VERSION:-0.1.0}"

mkdir -p "$OUTPUT_DIR"

EXISTING_SIGN_IDENTITY=""
if [[ -d "$APP_BUNDLE" ]]; then
  EXISTING_SIGN_IDENTITY="$(detect_existing_sign_identity "$APP_BUNDLE" || true)"
fi
RESOLVED_SIGN_IDENTITY="$(resolve_sign_identity "$SIGN_IDENTITY" "$EXISTING_SIGN_IDENTITY")"

if [[ "$SIGN_IDENTITY" == "preserve" ]]; then
  if [[ -n "$EXISTING_SIGN_IDENTITY" ]]; then
    if [[ "$RESOLVED_SIGN_IDENTITY" == "$EXISTING_SIGN_IDENTITY" ]]; then
      echo "[open-snek] Reusing existing signing identity: $EXISTING_SIGN_IDENTITY"
    else
      echo "[open-snek] Existing signing identity unavailable; falling back to auto signing"
    fi
  else
    echo "[open-snek] No prior app signature found; falling back to auto signing"
  fi
fi
if [[ "$SIGN_IDENTITY" == "auto" && -n "$EXISTING_SIGN_IDENTITY" && "$EXISTING_SIGN_IDENTITY" != "adhoc" ]]; then
  if [[ "$RESOLVED_SIGN_IDENTITY" == "$EXISTING_SIGN_IDENTITY" ]]; then
    echo "[open-snek] Auto mode reusing existing signing identity: $EXISTING_SIGN_IDENTITY"
  else
    echo "[open-snek] Existing signing identity unavailable; auto mode will detect another identity or use ad-hoc signing"
  fi
fi
if [[ "$SIGN_IDENTITY" == "auto" && "$EXISTING_SIGN_IDENTITY" == "adhoc" ]]; then
  echo "[open-snek] Existing app is ad-hoc signed; auto mode will try a real signing identity for stable TCC grants"
fi

if has_full_xcode; then
  require_cmd xcodegen

  XCODE_CONFIGURATION="$(tr '[:lower:]' '[:upper:]' <<< "${CONFIGURATION:0:1}")${CONFIGURATION:1}"
  ACTIVE_PROJECT_FILE="$PROJECT_FILE"
  ensure_generated_project
  echo "[open-snek] Ensured generated Xcode project at: $ACTIVE_PROJECT_FILE"

  echo "[open-snek] Building $PRODUCT_NAME ($CONFIGURATION) via Xcode target..."
  XCODEBUILD_LOG="$(mktemp "${TMPDIR:-/tmp}/open_snek_xcodebuild.XXXXXX")"
  XCODEBUILD_ACTIONS=(build)
  if [[ "$CLEAN_BUILD" == true ]]; then
    XCODEBUILD_ACTIONS=(clean build)
  fi
  if ! xcodebuild \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    -project "$ACTIVE_PROJECT_FILE" \
    -scheme OpenSnek \
    -configuration "$XCODE_CONFIGURATION" \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    "${XCODEBUILD_ACTIONS[@]}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    OPEN_SNEK_BUILD_CHANNEL="$BUILD_CHANNEL" \
    OPEN_SNEK_SPARKLE_PUBLIC_ED_KEY="$SPARKLE_PUBLIC_ED_KEY" >"$XCODEBUILD_LOG" 2>&1; then
    print_xcodebuild_failure "$XCODEBUILD_LOG"
    exit 1
  fi

  BUILT_APP="$DERIVED_DATA_PATH/Build/Products/$XCODE_CONFIGURATION/OpenSnek.app"
  if [[ ! -d "$BUILT_APP" ]]; then
    echo "Built app not found: $BUILT_APP" >&2
    exit 1
  fi

  rm -rf "$APP_BUNDLE"
  ditto "$BUILT_APP" "$APP_BUNDLE"
else
  require_cmd iconutil
  require_cmd install_name_tool
  require_cmd plutil

  if ! SWIFT_COMMAND="$(find_compatible_swift)"; then
    echo "Swift 6.2 or newer is required. Install it with: brew install swift" >&2
    exit 1
  fi
  build_with_swiftpm "$SWIFT_COMMAND"
  PRESERVE_NESTED_SIGNATURES=true
fi

if command -v codesign >/dev/null 2>&1; then
  ADHOC_REQ="=designated => identifier \"$BUNDLE_ID\""
  codesign_app() {
    if [[ "$PRESERVE_NESTED_SIGNATURES" == true ]]; then
      codesign --force "$@"
    else
      codesign --force --deep "$@"
    fi
  }
  sign_adhoc() {
    if codesign_app --sign - --requirements "$ADHOC_REQ" "$APP_BUNDLE" >/dev/null 2>&1; then
      echo "[open-snek] Signed app with ad-hoc identity (stable designated requirement: identifier \"$BUNDLE_ID\")"
      echo "[open-snek] If HID remains blocked after this build, run once: tccutil reset ListenEvent $BUNDLE_ID"
      return 0
    fi
    if codesign_app --sign - "$APP_BUNDLE" >/dev/null 2>&1; then
      echo "[open-snek] Signed app with ad-hoc identity"
      echo "[open-snek] Warning: stable designated requirement could not be applied; Input Monitoring grants may not survive rebuilds."
      echo "[open-snek] If HID remains blocked, run: tccutil reset ListenEvent $BUNDLE_ID"
      return 0
    fi
    return 1
  }

  case "$RESOLVED_SIGN_IDENTITY" in
    none)
      if [[ "$PRESERVE_NESTED_SIGNATURES" == true ]]; then
        # install_name_tool invalidates SwiftPM's ad-hoc executable signature.
        # Remove it so an explicitly unsigned build is unsigned rather than invalidly signed.
        codesign --remove-signature "$APP_BUNDLE/Contents/MacOS/$PRODUCT_NAME"
      fi
      echo "[open-snek] Skipping codesign (sign identity: none)"
      ;;
    adhoc|-)
      if sign_adhoc; then
        :
      else
        echo "[open-snek] Warning: ad-hoc codesign failed"
      fi
      ;;
    auto)
      if detected_identity="$(detect_preferred_sign_identity)"; then
        if codesign_app --sign "$detected_identity" "$APP_BUNDLE" >/dev/null 2>&1; then
          echo "[open-snek] Signed app with detected identity: $detected_identity"
        else
          echo "[open-snek] Warning: signing with detected identity failed; falling back to ad-hoc"
          if sign_adhoc; then
            :
          else
            echo "[open-snek] Warning: ad-hoc codesign failed"
          fi
        fi
      else
        echo "[open-snek] No signing identity detected; using ad-hoc signature"
        if sign_adhoc; then
          :
        else
          echo "[open-snek] Warning: ad-hoc codesign failed"
        fi
      fi
      ;;
    *)
      if codesign_app --sign "$RESOLVED_SIGN_IDENTITY" "$APP_BUNDLE" >/dev/null 2>&1; then
        echo "[open-snek] Signed app with requested identity: $RESOLVED_SIGN_IDENTITY"
      else
        echo "[open-snek] Error: codesign failed for identity: $RESOLVED_SIGN_IDENTITY" >&2
        exit 1
      fi
      ;;
  esac
fi

echo "[open-snek] App bundle ready: $APP_BUNDLE"

if $OPEN_AFTER_BUILD; then
  open "$APP_BUNDLE"
fi
