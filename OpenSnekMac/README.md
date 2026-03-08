# OpenSnekMac

Pure Swift macOS frontend for `open-snek`.

## Targets

- `OpenSnekMac`: SwiftUI desktop app
- `OpenSnekProbe`: Swift CLI for BLE DPI read/set/cycle verification

## App Architecture

- `Sources/OpenSnekMac/Bridge/`
  - `BridgeClient`: actor coordinating USB HID and BLE vendor operations
  - `BTVendorClient`: CoreBluetooth session manager for vendor write/notify path
  - `BLEVendorProtocol`: BLE framing, key map, and DPI payload parsing/building
- `Sources/OpenSnekMac/Services/`
  - `AppState`: UI state model, coalesced auto-apply queue, stale-read guards
  - `AppLog`: runtime file + OSLog logger
- `Sources/OpenSnekMac/UI/`
  - `ContentView`: SwiftUI dashboard and controls

## Runtime Guarantees

- BLE vendor transactions are serialized per connection.
- Auto-apply edits are coalesced (latest-wins) to prevent write backlog.
- Refresh and fast-poll responses are revision-gated to drop stale results.
- Invalid DPI payloads are ignored (with retry) to avoid UI snapback on transient malformed frames.

## Build / Run

```bash
swift run --package-path OpenSnekMac OpenSnekMac
```

```bash
swift test --package-path OpenSnekMac
```

## Logs

Runtime app logs:

```text
~/Library/Logs/OpenSnekMac/open-snek.log
```

## Probe CLI

### Read current BLE DPI

```bash
swift run --package-path OpenSnekMac OpenSnekProbe dpi-read
```

### Set DPI and verify readback

```bash
swift run --package-path OpenSnekMac OpenSnekProbe dpi-set --values 1600,6400 --active 2
```

### Stress cycle values

```bash
swift run --package-path OpenSnekMac OpenSnekProbe dpi-cycle --sequence '1200,6400;2600,6400;3200,6400' --loops 20 --active 2
```

