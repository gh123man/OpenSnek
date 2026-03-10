#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Prepare GitHub release secrets for OpenSnek DMG signing/notarization.

Usage:
  prepare_release_secrets.sh --cert <developer-id-app.p12> --cert-password <password> \
    --team-id <APPLE_TEAM_ID> --notary-key <AuthKey_XXXX.p8> \
    --notary-key-id <KEY_ID> --notary-issuer-id <ISSUER_ID> [--repo <owner/repo>] [--apply]

Behavior:
  - Encodes the Developer ID Application .p12 as base64 for GitHub secrets.
  - Reads the App Store Connect API key (.p8) as plain text for GitHub secrets.
  - With --apply and gh installed, writes the secrets directly to the target GitHub repo.
  - Without --apply, prints the exact gh secret commands to run.
USAGE
}

CERT_PATH=""
CERT_PASSWORD=""
TEAM_ID=""
NOTARY_KEY_PATH=""
NOTARY_KEY_ID=""
NOTARY_ISSUER_ID=""
REPO=""
APPLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cert)
      CERT_PATH="${2:-}"
      shift 2
      ;;
    --cert-password)
      CERT_PASSWORD="${2:-}"
      shift 2
      ;;
    --team-id)
      TEAM_ID="${2:-}"
      shift 2
      ;;
    --notary-key)
      NOTARY_KEY_PATH="${2:-}"
      shift 2
      ;;
    --notary-key-id)
      NOTARY_KEY_ID="${2:-}"
      shift 2
      ;;
    --notary-issuer-id)
      NOTARY_ISSUER_ID="${2:-}"
      shift 2
      ;;
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --apply)
      APPLY=true
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

for required in CERT_PATH CERT_PASSWORD TEAM_ID NOTARY_KEY_PATH NOTARY_KEY_ID NOTARY_ISSUER_ID; do
  if [[ -z "${!required}" ]]; then
    echo "Missing required argument: $required" >&2
    usage
    exit 1
  fi
done

[[ -f "$CERT_PATH" ]] || { echo "Certificate file not found: $CERT_PATH" >&2; exit 1; }
[[ -f "$NOTARY_KEY_PATH" ]] || { echo "Notary key file not found: $NOTARY_KEY_PATH" >&2; exit 1; }

CERT_BASE64="$(base64 < "$CERT_PATH" | tr -d '\n')"
NOTARY_KEY_CONTENT="$(cat "$NOTARY_KEY_PATH")"
GH_ARGS=()
if [[ -n "$REPO" ]]; then
  GH_ARGS+=(--repo "$REPO")
fi

print_commands() {
  cat <<EOF
gh secret set APPLE_DEVELOPER_ID_APP_CERT_BASE64 ${GH_ARGS[*]} <<< '$CERT_BASE64'
gh secret set APPLE_DEVELOPER_ID_APP_CERT_PASSWORD ${GH_ARGS[*]} <<< '$CERT_PASSWORD'
gh secret set APPLE_DEVELOPER_TEAM_ID ${GH_ARGS[*]} <<< '$TEAM_ID'
gh secret set APPLE_NOTARY_KEY_ID ${GH_ARGS[*]} <<< '$NOTARY_KEY_ID'
gh secret set APPLE_NOTARY_ISSUER_ID ${GH_ARGS[*]} <<< '$NOTARY_ISSUER_ID'
cat <<'KEY' | gh secret set APPLE_NOTARY_API_KEY_P8 ${GH_ARGS[*]}
$NOTARY_KEY_CONTENT
KEY
EOF
}

if [[ "$APPLY" == true ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "gh CLI is required for --apply" >&2
    exit 1
  fi
  printf '%s' "$CERT_BASE64" | gh secret set APPLE_DEVELOPER_ID_APP_CERT_BASE64 "${GH_ARGS[@]}"
  printf '%s' "$CERT_PASSWORD" | gh secret set APPLE_DEVELOPER_ID_APP_CERT_PASSWORD "${GH_ARGS[@]}"
  printf '%s' "$TEAM_ID" | gh secret set APPLE_DEVELOPER_TEAM_ID "${GH_ARGS[@]}"
  printf '%s' "$NOTARY_KEY_ID" | gh secret set APPLE_NOTARY_KEY_ID "${GH_ARGS[@]}"
  printf '%s' "$NOTARY_ISSUER_ID" | gh secret set APPLE_NOTARY_ISSUER_ID "${GH_ARGS[@]}"
  printf '%s' "$NOTARY_KEY_CONTENT" | gh secret set APPLE_NOTARY_API_KEY_P8 "${GH_ARGS[@]}"
  echo "GitHub secrets updated."
else
  print_commands
fi
