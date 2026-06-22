#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Install and register a SourceKit-LSP MCP bridge for Codex.

Usage:
  setup_sourcekit_lsp_mcp.sh [--replace] [--name <mcp-name>] [--skip-install]

Options:
  --replace       Replace an existing Codex MCP server with the same name.
  --name NAME     MCP server name to register. Default: sourcekit-lsp
  --skip-install  Do not install or update github.com/isaacphi/mcp-language-server.
  -h, --help      Show this help.

Environment:
  SOURCEKIT_LSP_BIN          Override the SourceKit-LSP executable path.
  MCP_LANGUAGE_SERVER_BIN    Override the mcp-language-server executable path.
USAGE
}

MCP_NAME="sourcekit-lsp"
REPLACE=false
INSTALL_BRIDGE=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --replace)
      REPLACE=true
      shift
      ;;
    --name)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "--name requires a value" >&2
        exit 1
      fi
      MCP_NAME="$2"
      shift 2
      ;;
    --skip-install)
      INSTALL_BRIDGE=false
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! command -v codex >/dev/null 2>&1; then
  echo "codex CLI is required to register MCP servers." >&2
  exit 1
fi

EXISTING_MCP=false
if codex mcp get "$MCP_NAME" >/dev/null 2>&1; then
  if ! $REPLACE; then
    echo "Codex MCP server '$MCP_NAME' already exists. Current config:" >&2
    codex mcp get "$MCP_NAME" >&2
    echo "Re-run with --replace to recreate it for this checkout." >&2
    exit 0
  fi
  EXISTING_MCP=true
fi

if [[ -n "${SOURCEKIT_LSP_BIN:-}" ]]; then
  SOURCEKIT_LSP="$SOURCEKIT_LSP_BIN"
elif SOURCEKIT_LSP="$(xcrun --find sourcekit-lsp 2>/dev/null)"; then
  :
elif SOURCEKIT_LSP="$(command -v sourcekit-lsp 2>/dev/null)"; then
  :
else
  echo "sourcekit-lsp was not found. Install Xcode or a Swift toolchain first." >&2
  exit 1
fi

if [[ ! -x "$SOURCEKIT_LSP" ]]; then
  echo "sourcekit-lsp is not executable: $SOURCEKIT_LSP" >&2
  exit 1
fi

BRIDGE_BIN_OVERRIDDEN=false
if [[ -n "${MCP_LANGUAGE_SERVER_BIN:-}" ]]; then
  BRIDGE_BIN="$MCP_LANGUAGE_SERVER_BIN"
  BRIDGE_BIN_OVERRIDDEN=true
else
  if ! command -v go >/dev/null 2>&1; then
    echo "Go is required to install mcp-language-server. Install with: brew install go" >&2
    exit 1
  fi

  GO_BIN_DIR="$(go env GOBIN)"
  if [[ -z "$GO_BIN_DIR" ]]; then
    GO_BIN_DIR="$(go env GOPATH)/bin"
  fi
  BRIDGE_BIN="$GO_BIN_DIR/mcp-language-server"
fi

if $INSTALL_BRIDGE && ! $BRIDGE_BIN_OVERRIDDEN; then
  if ! command -v go >/dev/null 2>&1; then
    echo "Go is required to install mcp-language-server. Install with: brew install go" >&2
    exit 1
  fi
  go install github.com/isaacphi/mcp-language-server@latest
fi

if [[ ! -x "$BRIDGE_BIN" ]]; then
  echo "mcp-language-server is not executable: $BRIDGE_BIN" >&2
  echo "Run without --skip-install or set MCP_LANGUAGE_SERVER_BIN." >&2
  exit 1
fi

if $EXISTING_MCP; then
  codex mcp remove "$MCP_NAME"
fi

ADD_ARGS=(
  mcp add
  --env "PATH=$PATH"
)

if [[ -n "${DEVELOPER_DIR:-}" ]]; then
  ADD_ARGS+=(--env "DEVELOPER_DIR=$DEVELOPER_DIR")
elif DEVELOPER_DIR_FROM_XCODE_SELECT="$(xcode-select -p 2>/dev/null)"; then
  ADD_ARGS+=(--env "DEVELOPER_DIR=$DEVELOPER_DIR_FROM_XCODE_SELECT")
fi

ADD_ARGS+=(
  "$MCP_NAME"
  --
  "$BRIDGE_BIN"
  --workspace "$PACKAGE_DIR"
  --lsp "$SOURCEKIT_LSP"
  --
  --default-workspace-type swiftPM
)

codex "${ADD_ARGS[@]}"

cat <<EOF
Registered Codex MCP server '$MCP_NAME'.

Workspace: $PACKAGE_DIR
SourceKit-LSP: $SOURCEKIT_LSP
MCP bridge: $BRIDGE_BIN

Open a new Codex thread or restart Codex before expecting the new MCP tools to
appear in the tool list.
EOF
