# Validation

Prefer the smallest useful command first. Expand only when the change crosses boundaries.

## Fastest Useful Checks

| Change Area | Start Here | Expand When Needed |
|---|---|---|
| Probe CLI or protocol helper compile check | `swift build --package-path OpenSnek --product OpenSnekProbe` | run a live probe command |
| BLE key/parser changes | `swift test --package-path OpenSnek --filter BLEVendorProtocolTests` | add `BridgeClientBluetoothFallbackTests`; run live BT probe |
| Device profile / lighting zone / button-layout changes | `swift test --package-path OpenSnek --filter DeviceProfilesTests` | add probe readback |
| App-state hydration / persistence / auto-apply | `swift test --package-path OpenSnek --filter AppStateRefactorCharacterizationTests` | add `AppStateMultiDeviceTests` |
| Background service / backend transport | `swift test --package-path OpenSnek --filter BackgroundServiceTransportTests` | add `RemoteServiceSnapshotTests` or `ServiceModeTests` |
| Lifecycle / startup / menu bar | `swift test --package-path OpenSnek --filter AppLifecycleDelegateTests` | add `ServiceMenuBarPresentationTests` |
| USB button remap behavior | `swift test --package-path OpenSnek --filter USBButtonHydrationTests` | use `usb-button-read` / `usb-button-set` probe commands |
| BLE DPI stage behavior | `swift test --package-path OpenSnek --filter BLEVendorProtocolTests` | run hardware gate below when a supported device is connected |

Avoid `swift test --package-path OpenSnek` unless the change is broad or the user explicitly wants a full package run.

## Pre-Push Guard

Install the tracked git hook once per checkout:

```bash
./OpenSnek/scripts/install_git_hooks.sh
```

The hook runs the same command expected before publishing code:

```bash
./OpenSnek/scripts/pre_push_checks.sh
```

That guard runs strict Swift format, SwiftLint, developer-tool tests, the Swift unit suite,
and the code-backed device evidence manifest check. Formatter findings such as `RemoveLine`
are errors. `checked_command.sh` retains and summarizes compiler-time warnings as advisory
diagnostics while preserving the command exit code. Investigate reproducible compiler slowdowns;
a runner-dependent 200 ms warning alone does not fail validation. Build errors, formatting/lint
errors, test failures, and evidence-manifest failures remain blocking.

Fresh checks are the default. The installed hook uses `--reuse` only when the same source,
toolchain, and relevant environment passed within one hour; changed inputs run fresh checks.
CI and hardware runs never reuse receipts. See [Review](REVIEW.md#validate-once-publish-safely)
for scope/limitations; no successful receipt is written if files change during validation.

For focused compile/test commands with captured logs and compiler-time summaries, use:

```bash
./OpenSnek/scripts/checked_command.sh swift test --package-path OpenSnek --filter BLEVendorProtocolTests
```

## Protocol Implementation Guardrails

Protocol transactions should encode the device contract directly rather than
assuming every successful command has the same ACK/readback shape.

- Serialize multi-command device transactions for a single device, including app
  and service process access.
- Treat write ACKs as transport evidence only. Product operations must succeed
  from authoritative readback of the fields they changed.
- If a validated command can return no status after the firmware accepted it,
  model that response as indeterminate and resolve it with a single strict
  readback. Do not retry writes or readbacks to wait for device state to settle.
- Prefer direct registers or inventory commands over fingerprinting or inferred
  state. Use fingerprinting only when no direct register is mapped.
- Do not infer identity from non-unique values. For example, passive DPI events
  identify an active stage by DPI value only when that value maps to exactly one
  configured stage; duplicate values require a direct fast stage read.

## Safe hardware validation

Required for BLE DPI/stage changes when supported hardware is connected, but always opt-in.
Stop both app/service and other BLE control clients first. Keep the mouse awake. The manual
BLE probe lease fails fast on running OpenSnek processes or another probe; it never retries a
command or changes normal app connection ownership. Disconnect other matching Bluetooth models
so name-based routing is unambiguous.

Both mutating hardware unit tests (`HardwareDpiReliabilityTests`, `HardwareUSBButtonRemapTests`)
require an exact discovered device ID and a new absolute journal path. They no longer select the
first Bluetooth/USB device. Read-only discovery can use `usb-info` or candidate IDs printed by
`bt-profile-hid-watch --name "NAME" --duration 1`; do not confuse a product ID with the full ID.

```bash
export OPEN_SNEK_HW_DEVICE_ID='<exact-discovered-device-id>'
export OPEN_SNEK_HW_JOURNAL="$HOME/opensnek-hardware-check.json"  # must not already exist
OPEN_SNEK_HW=1 swift test --package-path OpenSnek --filter HardwareDpiReliabilityTests
# Or select HardwareUSBButtonRemapTests with the exact USB device ID and a different journal.
```

The test captures the full original state, writes a private recovery journal before mutation,
and restores/verifies the original even if an operation throws. DPI restores use the captured
raw stage bytes rather than rebuilding defaults or clamping a high-DPI tail stage. USB remap
restoration preserves distinct persistent/live blocks, restoring live last. Incomplete baseline
reads abort before testing. Never delete a failed/unrecovered journal or substitute factory defaults.

If unplug/sleep/process interruption prevents restore, reconnect the **same** device, stop competing
clients, then run recovery only with the matching test (DPI versus USB button):

```bash
OPEN_SNEK_HW=1 OPEN_SNEK_HW_RECOVER_JOURNAL="$HOME/opensnek-hardware-check.json" \
  swift test --package-path OpenSnek --filter HardwareDpiReliabilityTests
```

The same `OPEN_SNEK_HW_DEVICE_ID` is required. Recovery rejects mismatched device/schema/payload,
then restores and reads back once; no command-level retries. Keep the journal until its phase is
`restored`, then archive it before another run. A hard kill cannot run cleanup; the on-disk journal
is the recovery mechanism, not a guarantee that disconnected hardware can be restored immediately.

Report the result as `pass`, `fail`, or `skipped` with the actual scope. A passing software-only
restore-adapter test is not physical hardware validation. Persistence checks power-cycle with the
app/service stopped, read every changed setting before restoring any, and report per-setting results.

## Validation Labels

Use validation labels consistently in support docs and changelog entries:

- `Validated`: OpenSnek maintainers locally validated the behavior with hardware, captures, or probes.
- `Contributor validated`: an outside contributor validated the behavior with their hardware, but OpenSnek maintainers have not locally reproduced it.
- `Mapped`: OpenSnek ships metadata or an implementation based on known protocol shape, ecosystem sources, or profile similarity, but the behavior is not hardware-validated.

Do not describe contributor-only hardware results as simply `Validated`; credit them as contributor-validated until maintainers reproduce the behavior locally.

## Probe Cheat Sheet

### BLE DPI

```bash
swift run --package-path OpenSnek OpenSnekProbe dpi-read
swift run --package-path OpenSnek OpenSnekProbe dpi-set --values 1600,6400 --active 2
swift run --package-path OpenSnek OpenSnekProbe dpi-cycle --sequence '1200,6400;2600,6400' --loops 10 --active 2
```

Stage-selection regression check:

```bash
swift run --package-path OpenSnek OpenSnekProbe dpi-set --values 1000,2000,3000 --active 1
swift run --package-path OpenSnek OpenSnekProbe dpi-set --values 1000,2000,3000 --active 3
swift run --package-path OpenSnek OpenSnekProbe dpi-read
```

Expected final output:

```text
active=3 count=3 values=[1000, 2000, 3000]
```

### Basilisk V3 Pro Bluetooth Lighting

```bash
swift run --package-path OpenSnek OpenSnekProbe bt-lighting-info --name "BSK V3 PRO"
swift run --package-path OpenSnek OpenSnekProbe bt-lighting-read --zone all --name "BSK V3 PRO"
swift run --package-path OpenSnek OpenSnekProbe bt-lighting-brightness --value 96 --zone all --name "BSK V3 PRO"
swift run --package-path OpenSnek OpenSnekProbe bt-lighting-color --color 00ff40 --zone all --name "BSK V3 PRO"
swift run --package-path OpenSnek OpenSnekProbe bt-lighting-color --color ff6600 --zone logo --name "BSK V3 PRO"
swift run --package-path OpenSnek OpenSnekProbe bt-profile-watch --name "BSK V3 PRO" --slot 4 --poll-ms 1000 --samples 20
```

Validated zone map:

- `scroll_wheel` -> `0x01`
- `logo` -> `0x04`
- `underglow` -> `0x0A`

### USB Lighting

```bash
swift run --package-path OpenSnek OpenSnekProbe usb-lighting-info --pid 0x00ab
swift run --package-path OpenSnek OpenSnekProbe usb-lighting-read --zone all --pid 0x00ab
swift run --package-path OpenSnek OpenSnekProbe usb-lighting-brightness --value 96 --zone all --pid 0x00ab
swift run --package-path OpenSnek OpenSnekProbe usb-lighting-effect --kind static --color 00ff40 --zone all --pid 0x00ab
```

### Python Transport Wrapper

```bash
python3 tools/python/razer_poc.py --force-usb
python3 tools/python/razer_poc.py --force-ble
```

## App / Xcode Flows

Use these only when the task needs them. Root `run.sh` builds incrementally and requires the
foreground app to acknowledge a visible main window. It does not treat a service PID or successful
`open` request as sufficient. Receipt verification does not need Accessibility permission. A timeout
fails clearly; inspect the app log instead of claiming the window opened. Only `--no-build` skips
the root build; the launcher saying "staged app bundle" is not evidence that the build was skipped.

```bash
./run.sh --show-window
swift run --package-path OpenSnek OpenSnek
./OpenSnek/scripts/run_macos_app.sh
./OpenSnek/scripts/generate_xcodeproj.sh
./OpenSnek/scripts/xcodebuild_generated.sh -scheme OpenSnek -destination 'platform=macOS' build
./OpenSnek/scripts/xcodebuild_generated.sh -scheme OpenSnek -destination 'platform=macOS' test
./OpenSnek/scripts/xcodebuild_generated.sh -scheme OpenSnekProbe -destination 'platform=macOS' build
```

`OpenSnek/OpenSnek.xcodeproj` is generated from `OpenSnek/project.yml` on demand and is not committed.

## Permissions / TCC

Bluetooth:

- `OpenSnekProbe` BT commands require macOS Bluetooth privacy approval for the launching host process.
- If a BT command aborts with `__TCC_CRASHING_DUE_TO_PRIVACY_VIOLATION__`, fix host permission before changing BLE code.
- On this workspace, a quick verification command is:

```bash
swift run --package-path OpenSnek OpenSnekProbe bt-raw-read --name 'BSK V3 PRO' --key 10850101 --timeout-ms 1200
```

Expected success shape on the Basilisk V3 Pro BT path:

- notify header `30 01 00 00 00 00 00 02`
- payload `ff`

HID/Input Monitoring:

- Passive HID listeners and some USB/Bluetooth state flows require macOS Input Monitoring approval for the launching host.

## Runtime Logs

App log path:

```text
~/Library/Logs/OpenSnek/open-snek.log
```

Useful grep:

```bash
tail -n 300 ~/Library/Logs/OpenSnek/open-snek.log | rg "btSetDpiStages|btGetDpiStages|stale-read masked|values=\\["
```

Pass pattern:

- write ACK followed by stable readback matching the requested values and active stage

Fail patterns:

- repeated mirrored last-slot values after multi-stage writes
- stale-read masking that never converges

### Stale USB battery diagnosis

Enable Debug logging in Settings → Logging before reproducing. Keep the
app and background service running when the battery becomes stale; restarting
can erase the stuck state. Note the time, the app and menu bar percentages, the
selected device, whether the main window is open, and whether the mouse recently
slept, disconnected, or started charging.

```bash
tail -n 1500 ~/Library/Logs/OpenSnek/open-snek.log | rg "usbBattery|refreshState|remoteSnapshot selected|software-lighting-cache"
swift run --package-path OpenSnek OpenSnekProbe usb-battery-read --pid 0x00ab
```

The probe is a read-only comparison for a connected Basilisk V3 Pro. Run it while
the UI is stale, before restarting. `usbBattery` records the USB response header
and two power payload bytes for battery (`07:80`) and charging (`07:84`), plus
the parsed value. `refreshState read-result` shows incoming battery telemetry;
`refreshState cached` shows the merged state; `remoteSnapshot selected` shows
the state delivered to the app. A `nil` incoming battery may retain the previous
percentage, so a successful refresh alone does not prove fresh battery data.
Read-start without read-result, skipped refresh reasons, or missing reads help
separate a blocked refresh from a stale device response or snapshot.
`readState software-lighting-cache` identifies a poll served from the software
lighting cache, including its cached battery value and state timestamp.

Capture both sleep/offline and wake/reconnect while checking that battery updates
resume without an app restart. Compare with the app window open and closed. A
stable percentage over a short interval is normal; compare charging transitions
or an independently observed battery change. Save the relevant log before
restoring Warning logging, since changing the log level in-app resets the log.

### USB connection-state diagnosis

A USB device that flips between Connected and Reconnecting while DPI, stages, and poll rate read successfully usually returned a state missing one supported telemetry field; the missing field is misread as an unavailable device. Enable debug logging first and restore `warning` afterwards:

```bash
defaults write io.opensnek.OpenSnek openSnek.logLevel -string debug
defaults write io.opensnek.OpenSnek openSnek.logLevel -string warning
```

Useful greps:

```bash
tail -n 300 ~/Library/Logs/OpenSnek/open-snek.log | rg "readState usb|partial usb telemetry treated unavailable|refreshState backoff|usbControlAvailability"
```

Fail pattern (Naga V2 Pro brightness example):

- `readState usb ... elapsed=` succeeds
- `refreshState partial usb telemetry treated unavailable` follows immediately
- `refreshState backoff ... until=...` repeats and the status indicator cycles

When that pattern appears, probe the missing register directly before touching recovery logic. For brightness, check which LED answers `0F:84`:

```bash
swift run --package-path OpenSnek OpenSnekProbe usb-raw --class 0x0f --cmd 0x84 --size 0x03 --args 01,04,00 --pid 0x00a8
```

Byte 0 is the status: `0x02` success (value in byte 10), `0x03` failure, `0x04` timeout. On the Naga V2 Pro, args `01 00 00` return `0x03` while `01 04 00` return `0x02`; the profile fixes that with `usbBrightnessReadLEDIDs` in `DeviceSupport.swift` instead of weakening the telemetry check. A `0x04` timeout can simply mean the mouse is asleep; wake it before treating a read as a rejection.
