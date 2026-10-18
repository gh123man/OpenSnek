# OpenSnek Agent Guide

Goal: reach the relevant code, reproduce the behavior, and make the smallest evidence-backed change.

## Navigation

| Task | Open first |
|---|---|
| Add a device or transport | `docs/development/ADDING_DEVICE_SUPPORT.md` |
| Device IDs, capabilities, zones, buttons | `OpenSnek/Sources/OpenSnekCore/{DeviceSupport.swift,Models.swift,ButtonBindingSupport.swift}` |
| USB protocol / probing | `docs/protocol/PROTOCOL.md`, `docs/protocol/USB_PROTOCOL.md`; `OpenSnek/Sources/OpenSnekProtocols/USBHIDProtocol.swift`; `OpenSnek/Sources/OpenSnek/Bridge/BridgeClient+USB.swift` |
| BLE protocol / probing | `docs/protocol/BLE_PROTOCOL.md`; `OpenSnek/Sources/OpenSnekProtocols/BLEVendorProtocol.swift`; `OpenSnek/Sources/OpenSnekHardware/BLEVendorTransportClient.swift`; `OpenSnek/Sources/OpenSnekProbe/ProbeBridge.swift` |
| State, hydration, auto-apply | `OpenSnek/Sources/OpenSnek/Services/{AppStateEditorController.swift,AppStateApplyController.swift,DeviceStore.swift,EditorStore.swift}` |
| Service, presence, snapshots | `OpenSnek/Sources/OpenSnek/Services/{BackendSession.swift,BackgroundServiceCoordinator.swift,AppStateRuntimeController.swift}`; `OpenSnek/Sources/OpenSnek/Bridge/BridgeClient.swift` |
| UI / lifecycle | `OpenSnek/Sources/OpenSnek/UI/`; `OpenSnek/Sources/OpenSnek/{AppLifecycleDelegate.swift,OpenSnekApp.swift}` |
| Checks, hardware journals, logs, TCC | `docs/development/VALIDATION.md` |
| Windows Synapse/BTVS capture | `captures/README.md`; use `tools/windows/capture-btvs.ps1` and start analysis with `synapse-events.md`, `correlation.md`, `summary.md` |
| Independent review / coding conventions | `CODING_STANDARDS.md`; `docs/development/REVIEW.md` |

For deeper routing use `docs/development/REPO_MAP.md`. SourceKit-LSP setup lives in
`docs/development/SOURCEKIT_LSP.md`; its SwiftPM workspace is `OpenSnek/`.

## Safety and behavior

- Swift and protocol docs are canonical. Python protocol tools may lag.
- Serialize BLE vendor exchanges. Command failures surface without command-level retries;
  connection recovery alone may retry real connection errors.
- Treat reported breakage as a regression: start with logs and a reproducer. If evidence is
  insufficient, capture targeted diagnostics before changing behavior.
- Connection-state changes cover both disconnect/offline/sleep and reconnect/wake/recover.
  Inspect blame, commits, and relevant PR history first, then cover both directions.
  State any unavailable hardware-validation gap explicitly.
- Preserve latest-wins/coalesced apply. Ignore malformed BLE DPI reads, preserve stage IDs on
  writes, resolve active stages from IDs, and keep stage nudge/toggle writes out of the apply path.
- Hardware mutation requires exact device scope, an original-state journal, and verified restore.
  BLE probes require the app/service stopped. See the hardware workflow before sending writes.
- `Validated` means maintainer/local hardware validation. Use `Contributor validated` with a
  credited source for contributor hardware; separate mapped, untested, and unsupported features.

## Delivery

- Fetch `origin` before creating a topic branch; branch from current `origin/main`. Before
  opening/updating a PR, reconcile any drift from `origin/main`, then rerun affected checks.
- Install the tracked hook with `./OpenSnek/scripts/install_git_hooks.sh`. Before publishing,
  run `./OpenSnek/scripts/pre_push_checks.sh`. It performs fresh checks by default; the hook
  may reuse a recent exact-input success. Hardware runs and CI are never reused.
- Run the app with `./run.sh` (foreground window verified). Use `--no-build` only when intentionally
  launching the staged bundle; ordinary launch already builds incrementally.
- `OpenSnek/project.yml` is the Xcode source of truth. Generate the project when needed; leave
  `OpenSnek/OpenSnek.xcodeproj` untracked.
- Protocol behavior changes include tests, protocol docs, and `CHANGELOG.md`. User-visible
  app/probe/tool changes also update the changelog; pure captures/research stay in their docs.
  See `CODING_STANDARDS.md` for release-note and review conventions.
- `BridgeClient.swift` is high churn: inspect its working diff before editing and stage only
  intended changes when the checkout contains unrelated work.
