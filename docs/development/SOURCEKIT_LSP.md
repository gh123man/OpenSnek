# SourceKit-LSP For Codex

OpenSnek uses SwiftPM as the SourceKit-LSP workspace. The package root is
`OpenSnek/`, not the repository root, so LSP clients should open or configure
`OpenSnek/` as the workspace.

`OpenSnek/.sourcekit-lsp/config.json` pins SourceKit-LSP to SwiftPM workspace
mode and debug configuration. Keep this file small; build and test commands are
still the source of truth for validation.

## Codex MCP Setup

Codex can use SourceKit-LSP through an MCP bridge. From the repository root:

```bash
./OpenSnek/scripts/setup_sourcekit_lsp_mcp.sh
```

The script:

- locates `sourcekit-lsp` through `xcrun --find sourcekit-lsp` or `PATH`
- installs `github.com/isaacphi/mcp-language-server@latest` with Go
- registers a global Codex MCP server named `sourcekit-lsp`
- scopes the bridge to the absolute `OpenSnek/` package path

Prerequisites:

- Xcode or a Swift toolchain that includes `sourcekit-lsp`
- Go, for installing the MCP bridge (`brew install go`)
- Codex CLI, for `codex mcp add`

If a `sourcekit-lsp` MCP server already exists, the script prints the current
config and exits. Recreate it for this checkout with:

```bash
./OpenSnek/scripts/setup_sourcekit_lsp_mcp.sh --replace
```

Useful checks:

```bash
codex mcp get sourcekit-lsp
codex mcp list
```

Remove the integration with:

```bash
codex mcp remove sourcekit-lsp
```

Codex discovers MCP tools when a thread/session starts. After running the setup
script, open a new Codex thread or restart Codex before expecting the
`sourcekit-lsp` tools to be callable.

## Using It

When available, prefer SourceKit-LSP for semantic Swift questions:

- `hover` for inferred declarations and signatures
- `definition` for jumping to declarations
- `references` before broad rename or call-site edits
- `diagnostics` after edits when a focused Swift compile/test would be slower

Use it as a supplement to `rg`, focused tests, and `swift test --package-path
OpenSnek`. LSP diagnostics are not a replacement for the repository validation
commands in `docs/development/VALIDATION.md`.

Prime SourceKit after a fresh checkout or after large dependency/interface
changes:

```bash
swift build --package-path OpenSnek
```

Before saying work is done or pushing code, still run:

```bash
swift test --package-path OpenSnek
```

## Troubleshooting

If tools are missing, run `codex mcp get sourcekit-lsp` and start a new Codex
thread after confirming the server is enabled.

If SourceKit returns stale or missing cross-module information, run a fresh
Swift build or test. SourceKit-LSP depends on current build products and index
data for the best cross-module results.

If diagnostics appear to hang on a cold checkout, wait for the initial
project-wide diagnostic/index pass or run a package build first. Large
project-wide diagnostic streams can be slower than `hover` or `definition`.

If `sourcekit-lsp` cannot be found, verify the selected developer directory:

```bash
xcode-select -p
xcrun --find sourcekit-lsp
```

Set `SOURCEKIT_LSP_BIN` when using a non-default toolchain:

```bash
SOURCEKIT_LSP_BIN=/path/to/sourcekit-lsp ./OpenSnek/scripts/setup_sourcekit_lsp_mcp.sh --replace
```
