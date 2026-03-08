# Codex Instructions

## Project Overview

**open-snek** configures supported Razer mice without Razer Synapse.

Current project scope includes:
- Python tooling (`razer_usb.py`, `razer_ble.py`, `razer_poc.py`)
- Swift macOS app (`OpenSnekMac`) and Swift BLE probe CLI (`OpenSnekProbe`)

## Canonical Documentation

Always read protocol docs before protocol changes:
- `PROTOCOL.md` (index)
- `USB_PROTOCOL.md`
- `BLE_PROTOCOL.md`
- `PARITY.md`

When protocol behavior changes, update docs in the same change.

## Key Files

| Path | Purpose |
|---|---|
| `razer_poc.py` | Transport wrapper CLI |
| `razer_usb.py` | USB HID implementation |
| `razer_ble.py` | BLE vendor + fallback implementation |
| `OpenSnekMac/Sources/OpenSnekMac/Bridge/BridgeClient.swift` | Swift transport bridge actor |
| `OpenSnekMac/Sources/OpenSnekMac/Bridge/BTVendorClient.swift` | CoreBluetooth vendor session manager |
| `OpenSnekMac/Sources/OpenSnekMac/Bridge/BLEVendorProtocol.swift` | BLE framing and payload helpers |
| `OpenSnekMac/Sources/OpenSnekMac/Services/AppState.swift` | SwiftUI state model + apply scheduling |
| `OpenSnekMac/Sources/OpenSnekMac/Services/AppLog.swift` | Runtime app logs |
| `OpenSnekMac/Sources/OpenSnekProbe/main.swift` | BLE probe CLI (read/set/cycle + verify) |

## Current Device Coverage

Validated device family:
- Basilisk V3 X HyperSpeed
  - USB/dongle PID `0x00B9` (VID `0x1532`)
  - Bluetooth PID `0x00BA` (VID `0x068E`)

## Working Areas

- USB: DPI, stages, poll rate, battery, device metadata
- BLE vendor GATT: DPI table read/write, active stage update, lighting raw/frame controls, button remap payloads
- Swift app: auto-apply, state polling, stale-read defenses, runtime logging

## Development Rules

1. Read protocol docs first for protocol-facing edits.
2. Keep BLE vendor operations sequential per connection.
3. Prefer coalesced/latest-wins apply semantics for rapid UI edits.
4. Treat malformed BLE DPI payloads as transient; ignore/retry instead of applying invalid state.
5. Update docs and tests in the same change for behavior changes.
6. For BLE DPI stages:
   - parse by declared stage count even when read payload is short by one byte
   - resolve active stage via stage-id mapping from payload entries
   - preserve stage IDs on writes
   - do not reintroduce stage “nudge/toggle” write sequences
7. Keep `CHANGELOG.md` up to date for user-visible behavior changes, protocol handling changes, and reliability workflow changes.

## Validation Workflow

### Python

```bash
python razer_poc.py --force-usb
python razer_poc.py --force-ble
```

### Swift App / Tests

```bash
swift test --package-path OpenSnekMac
swift run --package-path OpenSnekMac OpenSnekMac
```

### Swift Hardware Reliability Gate (required for BLE DPI/stage changes)

```bash
OPEN_SNEK_HW=1 swift test --package-path OpenSnekMac --filter HardwareDpiReliabilityTests
```

### Swift Probe CLI (preferred for fast BLE DPI iteration)

```bash
swift run --package-path OpenSnekMac OpenSnekProbe dpi-read
swift run --package-path OpenSnekMac OpenSnekProbe dpi-set --values 1600,6400 --active 2
swift run --package-path OpenSnekMac OpenSnekProbe dpi-cycle --sequence '1200,6400;2600,6400' --loops 10 --active 2
```

For stage-selection regressions, run this exact check:

```bash
swift run --package-path OpenSnekMac OpenSnekProbe dpi-set --values 1000,2000,3000 --active 1 --verify-retries 8 --verify-delay-ms 120
swift run --package-path OpenSnekMac OpenSnekProbe dpi-set --values 1000,2000,3000 --active 3 --verify-retries 8 --verify-delay-ms 120
swift run --package-path OpenSnekMac OpenSnekProbe dpi-read
```

Expected final output: `active=3 count=3 values=[1000, 2000, 3000]`.

### Runtime Logs

App log path:

```text
~/Library/Logs/OpenSnekMac/open-snek.log
```

Useful regression grep:

```bash
tail -n 300 ~/Library/Logs/OpenSnekMac/open-snek.log | rg "btSetDpiStages|btGetDpiStages|stale-read masked|values=\\["
```

Fail patterns:
- `btGetDpiStages` repeatedly returning mirrored last-slot values after multi-stage writes
- stale-read masking persisting without convergence

Pass pattern:
- write ack followed by stable readback matching requested values and active stage

## References

- [OpenRazer](https://github.com/openrazer/openrazer)
- [OpenRazer Protocol Wiki](https://github.com/openrazer/openrazer/wiki/Reverse-Engineering-USB-Protocol)
- [razer-macos](https://github.com/1kc/razer-macos)
- [RazerBlackWidowV3MiniBluetoothControllerApp](https://github.com/JiqiSun/RazerBlackWidowV3MiniBluetoothControllerApp)
