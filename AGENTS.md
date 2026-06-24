# Codex Instructions

Goal: shortest path from user request to the exact files, commands, and constraints needed to do the work.

## Start Here

| Task | Open First | Usually Validate With |
|---|---|---|
| BLE protocol, BT probe, BT device bug | `docs/protocol/PROTOCOL.md` then `docs/protocol/BLE_PROTOCOL.md`; `OpenSnek/Sources/OpenSnekProtocols/BLEVendorProtocol.swift`; `OpenSnek/Sources/OpenSnekHardware/BLEVendorTransportClient.swift`; `OpenSnek/Sources/OpenSnek/Bridge/BridgeClient+Bluetooth.swift`; `OpenSnek/Sources/OpenSnekProbe/{main.swift,ProbeTransport.swift}` | `swift test --package-path OpenSnek --filter BLEVendorProtocolTests`; build/run probe |
| Windows Synapse/BTVS capture, profile reverse engineering | `captures/README.md`; `docs/protocol/BLE_PROFILE_CRUD_SPEC.md`; `docs/research/BASILISK_V3_PRO_BT_EXTENDED.md`; run `tools/windows/capture-btvs.ps1` and inspect `synapse-events.md`, `correlation.md`, then `summary.md` | focused BTVS capture plus Synapse log correlation artifacts |
| USB protocol, USB lighting, USB buttons | `docs/protocol/PROTOCOL.md` then `docs/protocol/USB_PROTOCOL.md`; `OpenSnek/Sources/OpenSnekProtocols/USBHIDProtocol.swift`; `OpenSnek/Sources/OpenSnek/Bridge/BridgeClient+USB.swift`; `OpenSnek/Sources/OpenSnekCore/DeviceSupport.swift` | focused USB probe command; `DeviceProfilesTests`; `USBButtonHydrationTests` |
| Device support, product IDs, zones, button layout | `OpenSnek/Sources/OpenSnekCore/{DeviceSupport.swift,Models.swift,ButtonBindingSupport.swift}`; `docs/protocol/PARITY.md` if shipped-status changes | `swift test --package-path OpenSnek --filter DeviceProfilesTests` |
| App-state hydration, persistence, auto-apply | `OpenSnek/Sources/OpenSnek/Services/{AppState.swift,AppStateEditorController.swift,AppStateApplyController.swift,DeviceStore.swift,EditorStore.swift}`; `OpenSnek/Sources/OpenSnekAppSupport/DevicePreferenceStore.swift` | `swift test --package-path OpenSnek --filter AppStateRefactorCharacterizationTests` |
| Background service, bridge transport, snapshots | `OpenSnek/Sources/OpenSnek/Services/{BackendSession.swift,BackgroundServiceCoordinator.swift,AppStateRuntimeController.swift}`; `OpenSnek/Sources/OpenSnek/Bridge/BridgeClient.swift` | `swift test --package-path OpenSnek --filter BackgroundServiceTransportTests` or `RemoteServiceSnapshotTests` |
| UI, menu bar, startup/lifecycle | `OpenSnek/Sources/OpenSnek/UI/*.swift`; `OpenSnek/Sources/OpenSnek/{AppLifecycleDelegate.swift,OpenSnekApp.swift}`; `RuntimeStore.swift` | `swift test --package-path OpenSnek --filter AppLifecycleDelegateTests` or `ServiceMenuBarPresentationTests` |

Protocol behavior changes require docs, tests, and `CHANGELOG.md` updates in the same change.

## Canonical Sources

- Swift app/probe code and protocol docs are canonical.
- Python tooling (`tools/python/`) is useful for probing and comparison, but may lag; do not treat it as source of truth when it disagrees with Swift/docs.
- Open `docs/protocol/PARITY.md` only when support status, shipped capability, or transport parity changes.

## Current Validated Devices

- Basilisk V3 X HyperSpeed: USB `0x00B9`, Bluetooth `0x00BA`
- Basilisk V3 Pro: USB `0x00AB`, Bluetooth `0x00AC`
- Basilisk V3 35K: USB `0x00CB`

## Repo Rules

1. BLE vendor exchanges stay serialized one-at-a-time per connection.
2. Command-level retries are forbidden. Retries may only live in protocol/transport connection recovery for real connection errors; command failures must surface clearly instead of being papered over by repeating the command while device state settles.
3. When the user says something is broken, assume it is a regression unless evidence says otherwise. Do not guess or stack speculative fixes. Start from logs and existing diagnostics; if the available data is insufficient, add targeted logging/diagnostics, walk the user through a repro, then author the fix from the captured repro evidence.
4. For connection-state regressions, especially USB/Bluetooth presence, reachability, stale HID sessions, reconnect settle timing, background-service snapshots, and UI availability, treat disconnect and reconnect as one behavioral surface. Before changing that surface, inspect `git blame`, commit history, and relevant PR history for the touched paths; identify the previously working behavior; then add or update regression coverage for both directions: unplug/offline/sleep and replug/wake/recover. Do not ship a one-sided fix that proves only disconnect or only reconnect. If hardware validation is required and unavailable, add targeted diagnostics or a manual repro checklist and state the gap clearly.
5. Prefer focused reads, focused tests, and the smallest useful probe/build command instead of defaulting to full-package runs.
6. Keep latest-wins/coalesced apply behavior for rapid UI edits.
7. Treat malformed BLE DPI payloads as transient; ignore them instead of applying bad state or retrying the command.
8. For BLE DPI stages, preserve stage IDs on write, resolve active stage from stage IDs, and do not reintroduce stage nudge/toggle writes.
9. Keep `CHANGELOG.md` and GitHub release notes up to date for user-visible behavior changes and functional app/probe/tool changes. Release notes must start with the released version header, summarize major features and notable fixes, and omit non-functional/internal-only work such as linting, formatting, development environment setup, CI/release automation, dependency/tooling churn, docs-only work, and internal refactors unless they directly change user-facing app/probe behavior. Do not add pure protocol research findings, capture notes, or speculative mappings to the changelog; put those in protocol or research docs instead. Use `Fixed` only for defects that already exist on `main`; fixes made while stabilizing an unmerged feature branch should be folded into that feature's net `Added`/`Changed` entry.
10. Treat `OpenSnek/project.yml` as the Xcode source of truth; generate `OpenSnek/OpenSnek.xcodeproj` on demand and do not commit it.
11. Use `Validated` only for maintainer/local OpenSnek hardware validation. For device support validated by an outside contributor but not by maintainers, use `Contributor validated` and credit the contributor source in docs.
12. Before creating a new topic branch, fetch `origin` and branch from an up-to-date `origin/main`. Before opening or updating a PR, check whether the branch is behind `origin/main`; if it is, merge or rebase `origin/main`, resolve conflicts, rerun validation, and push the updated branch.
13. Before saying work is done or pushing code, run the complete unit test suite with `swift test --package-path OpenSnek` and ensure it passes locally.
14. For Windows Synapse/BTVS reverse engineering, prefer automated captures over manual Wireshark work. Use `tools/windows/capture-btvs.ps1`, let it choose a fresh port unless intentionally passing `-ReuseBtvs`, take a same-session idle baseline when background traffic is ambiguous, then start analysis from `synapse-events.md`, `correlation.md`, and `summary.md` before opening the raw `.pcapng`.
15. When asked to run the app, use `./run.sh` from the repository root unless the user explicitly asks for a different launch path.
16. Use code comments strategically. If a change has unclear but important UI/UX effects, leave a concise comment that explains the constraint so future changes do not regress it.
17. Avoid magic numbers unless the number is inherently self-descriptive. For bounded sets, including protocol characteristics where appropriate, prefer enums or named constants with clear domain names. For example, `let slot = 1` may be clear in local context, but `let button = 55` needs a descriptive name.
18. Avoid repeating multi-case conditionals across the codebase. If the same case set appears in multiple places, such as `device == foo || device == bar || device == abc`, move the rule into a helper method, enum extension, or other reusable code.
19. Treat Swift long-function-body compiler warnings from `-warn-long-function-bodies=200` as errors. Fix them immediately by simplifying or splitting the flagged method; do not suppress or defer them.

## Swift Style Defaults

Write new Swift as if strict SwiftLint default rules are already enforcing it. Prefer code shape
changes over local `swiftlint:disable` comments; only suppress a rule when the exception is
intentional, documented, and narrower than the next-best refactor.

- Keep functions and closures focused. If a method needs multiple phases, validation branches, or
  large local setup, split it into named helpers before it grows into a lint or compiler long-body
  problem.
- Avoid long parameter lists and large tuples. Group related values into small request, context,
  result, or snapshot structs with domain-specific names; reuse those types where the same shape
  crosses module or test boundaries.
- Prefer early `guard` exits and helper methods over deep nesting. Use `for ... where ...` when a
  loop body only runs for matching elements.
- Avoid force casts and force tries. In production code, use typed errors, optional binding, or
  guarded casts. In tests, prefer `try XCTUnwrap(...)` or explicit assertions that explain the
  expectation.
- Do not interpolate optionals directly into strings. Unwrap first, use `map(String.init)`, or
  provide an explicit fallback value.
- Use meaningful identifiers by default, even while `identifier_name` is temporarily disabled.
  Single-letter names are acceptable only for tiny local scopes where the domain is conventional,
  such as coordinates or RGB components.
- Keep literals and repeated case sets named. Use local constants, enums, or extensions for
  protocol bytes, button slots, device groups, and other bounded domains.
- Keep line wrapping readable even while `line_length` is temporarily disabled. Break long argument
  lists, arrays, dictionaries, chained calls, and assertions across lines with trailing commas
  omitted.
- Let Swift format conventions carry simple control flow: no unnecessary parentheses around `if`,
  `guard`, `while`, or `switch` conditions.
- Before pushing Swift changes, run
  `swift package --package-path OpenSnek plugin --allow-writing-to-package-directory swiftlint`
  plus the focused tests for the touched area; run `swift test --package-path OpenSnek` before
  declaring the branch ready.

## Quick Commands

```bash
swift build --package-path OpenSnek --product OpenSnekProbe
swift run --package-path OpenSnek OpenSnekProbe dpi-read
swift run --package-path OpenSnek OpenSnekProbe bt-lighting-info --name "BSK V3 PRO"
swift run --package-path OpenSnek OpenSnekProbe usb-lighting-info --pid 0x00ab
./run.sh
```

Codex SourceKit-LSP MCP setup for semantic Swift navigation, hover, references, and diagnostics:

```bash
./OpenSnek/scripts/setup_sourcekit_lsp_mcp.sh
```

Use `docs/development/SOURCEKIT_LSP.md` for setup details and troubleshooting. The SwiftPM LSP workspace root is `OpenSnek/`, not the repository root.

Windows BTVS/Synapse capture:

```powershell
powershell -ExecutionPolicy Bypass -File tools\windows\capture-btvs.ps1 -Name <capture-name> -Seconds 60
```

Highest-value focused tests:

```bash
swift test --package-path OpenSnek --filter BLEVendorProtocolTests
swift test --package-path OpenSnek --filter DeviceProfilesTests
swift test --package-path OpenSnek --filter AppStateRefactorCharacterizationTests
swift test --package-path OpenSnek --filter BackgroundServiceTransportTests
```

Manual XCUITest happy path. This is manual-only and runs the full macOS app against a connected real USB device. The default scope is Basilisk V3 Pro USB (`vendor 0x1532`, `product 0x00AB`, `protocol usb-hid`, profile `basilisk_v3_pro`); override it with the `OPEN_SNEK_UITEST_EXPECTED_*` environment variables when intentionally testing another supported device.

```bash
./OpenSnek/scripts/xcodebuild_generated.sh \
  -scheme OpenSnekUITests \
  -destination 'platform=macOS' \
  -only-testing:OpenSnekUITests/PollRateHappyPathUITests/testChangingPollRateAppliesExpectedUSBCommandAndState \
  test
```

Manual V3 Pro USB feature sweep. This changes and restores several hardware settings in one full-app XCUITest to catch cross-feature interference between back-to-back UI actions.

```bash
./OpenSnek/scripts/xcodebuild_generated.sh \
  -scheme OpenSnekUITests \
  -destination 'platform=macOS' \
  -only-testing:OpenSnekUITests/V3ProUSBFeatureSweepUITests/testV3ProUSBFeatureSweepDoesNotCrossInterfere \
  test
```

Manual V3 Pro Bluetooth feature sweep. This runs the same composable feature harness against the real Bluetooth protocol scope (`vendor 0x068E`, `product 0x00AC`, `protocol ble-vendor`, profile `basilisk_v3_pro`).

```bash
./OpenSnek/scripts/xcodebuild_generated.sh \
  -scheme OpenSnekUITests \
  -destination 'platform=macOS' \
  -only-testing:OpenSnekUITests/V3ProBluetoothFeatureSweepUITests/testV3ProBluetoothFeatureSweepDoesNotCrossInterfere \
  test
```

The test requires Input Monitoring for the built `OpenSnek.app` and Accessibility permission for the app launching `xcodebuild` (`Terminal`, `Codex`, or `Xcode`). Permission or device-scope failures should be reported as clear XCUITest failures with the attached event log.

Hardware gate for BLE DPI/stage changes when a supported device is connected:

```bash
OPEN_SNEK_HW=1 swift test --package-path OpenSnek --filter HardwareDpiReliabilityTests
```

## High-Value Gotchas

- Basilisk V3 Pro Bluetooth lighting is multi-zone. Static color uses per-zone `10 83` / `10 03`; brightness uses per-zone `10 85` / `10 05`. Do not assume legacy `10 84` / `10 04` works on that device.
- Basilisk V3 Pro Bluetooth notify headers are 8 bytes. Older captures/tools may assume 20-byte headers.
- If `swift run --package-path OpenSnek OpenSnekProbe ...` aborts with `__TCC_CRASHING_DUE_TO_PRIVACY_VIOLATION__`, fix macOS Bluetooth permission for the launching host before debugging protocol logic.
- `OpenSnek/Sources/OpenSnek/Bridge/BridgeClient.swift` is a high-churn file. Check `git diff -- <file>` before editing and stage only intended hunks when the worktree is dirty.

## Deeper Docs

- `docs/development/README.md`
- `docs/development/REPO_MAP.md`
- `docs/development/SOURCEKIT_LSP.md`
- `docs/development/VALIDATION.md`
- `docs/protocol/PROTOCOL.md`
