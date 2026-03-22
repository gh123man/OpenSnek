# BLE Hypershift Stream Support

## Status

OpenSnek does **not** currently monitor the Bluetooth Hypershift / DPI-clutch press stream.

Current live HID support in OpenSnek is DPI-only:

- `OpenSnek/Sources/OpenSnek/Bridge/BridgeClient.swift` keeps only passive-DPI event and heartbeat continuations.
- `OpenSnek/Sources/OpenSnek/Bridge/BridgeClient.swift` wires the monitor only to `handlePassiveDpiEvent` / `handlePassiveDpiHeartbeat`.
- `OpenSnek/Sources/OpenSnekHardware/USBPassiveDPIEventMonitor.swift` classifies reports only as `dpi`, `heartbeat`, or `other`.
- `OpenSnek/Sources/OpenSnekCore/DeviceSupport.swift` defines a single `PassiveDPIInputDescriptor` type.
- `OpenSnek/Sources/OpenSnekCore/DeviceSupport.swift` gives the Basilisk V3 X HyperSpeed Bluetooth profile only the validated passive-DPI descriptor: usage `0x01:0x02`, report ID `0x05`, subtype `0x02`, heartbeat subtype `0x10`.
- `OpenSnek/Sources/OpenSnek/Bridge/BridgeClient.swift` only arms HID listeners for devices whose report tuple matches that DPI descriptor.

That means the current app can:

- listen for passive DPI stage changes
- mark the stream as healthy from heartbeat traffic
- stop fast polling once a real DPI event is observed

It cannot currently:

- subscribe to a separate Hypershift-specific HID stream
- decode Hypershift press/release events
- trigger clutch behavior directly from passive HID input
- expose Hypershift stream health in diagnostics

## Capture-Backed Findings

The focused Windows capture `captures/ble/hypershift-hold-2026-03-22.pcapng` shows:

- a separate notify handle `0x0027`
- press payload `04 52 00 00 00 00 00 00`
- release payload `04 00 00 00 00 00 00 00`
- no `08 04 01 06` vendor remap write for slot `0x06`
- each press is followed by a software-side DPI-stage write/readback on `0B 04 01 00` / `0B 84 01 00`

Best current inference:

- Synapse is not detecting this button with a fast vendor poll loop.
- The button appears to arrive through a passive HID/report stream, and Synapse reacts by applying the clutch DPI through the existing vendor DPI-stage path.

## What OpenSnek Needs To Support

### 1. A second passive-HID descriptor type

The current `PassiveDPIInputDescriptor` is too narrow for this stream.

Needed:

- a new descriptor type for non-DPI passive HID events, or a generalized passive HID descriptor model
- support for matching a stream by usage page, usage, report ID, minimum report size, and event-specific decoding rules
- separate descriptors for:
  - passive DPI stream
  - passive Hypershift / clutch stream

Why:

- the Hypershift path does not decode into DPI X/Y values
- the current parser would classify these packets as `.other` and drop them

### 2. A dedicated Hypershift event model

Needed types:

- `PassiveHypershiftEvent`
- fields at minimum:
  - `deviceID`
  - `isPressed`
  - raw payload bytes
  - observed timestamp
  - optional decoded action byte

Why:

- we need press and release edges, not just a scalar DPI reading
- keeping raw bytes in the event lets us ship safely before every byte is fully named

### 3. Parser support for the new stream

The current parser in `OpenSnek/Sources/OpenSnekHardware/USBPassiveDPIEventMonitor.swift` only knows:

- `subtype == descriptor.subtype` -> DPI event
- `subtype == descriptor.heartbeatSubtype` -> heartbeat

Needed:

- a parser path for the Hypershift stream
- capture-backed rules for at least:
  - `04 52 00 00 00 00 00 00` -> press
  - `04 00 00 00 00 00 00 00` -> release
- tolerant handling for mapping-dependent press byte changes such as older `0x59` versus newer `0x52`

Important:

- do **not** hard-code `0x52` as a universal button ID yet
- treat the payload conservatively as a press/release pattern on the observed stream until the HID descriptor is captured

### 4. Watch-target selection beyond passive DPI

Today `OpenSnek/Sources/OpenSnek/Bridge/BridgeClient.swift` only builds watch targets from `profile.passiveDPIInput`.

Needed:

- profile metadata for the Hypershift stream candidate
- bridge logic that can arm more than one passive HID target per Bluetooth device
- registration bookkeeping that keeps these streams separate

Why:

- the DPI stream and Hypershift stream are distinct
- OpenSnek needs to subscribe to both without conflating them

### 5. Backend streams for Hypershift events

Today the bridge and backend expose:

- `passiveDpiEventStream()`
- `passiveDpiHeartbeatStream()`

Needed:

- `passiveHypershiftEventStream()`
- bridge-side state for:
  - armed Hypershift targets
  - observed Hypershift targets
  - last seen press/release timestamp

Why:

- the rest of the app already consumes asynchronous backend streams
- we should keep Hypershift aligned with the same architecture instead of sneaking it through polling paths

### 6. Runtime behavior for clutch press/release

Supporting the stream is not just capture and decode. The app needs a policy for what to do on press and release.

For the current Synapse-like DPI clutch behavior, OpenSnek would need:

- on press:
  - determine the configured clutch DPI
  - cache the pre-clutch active DPI/stage state
  - apply the clutch target DPI, likely through the existing BLE DPI-stage write path
- on release:
  - restore the previous active DPI/stage state

Needed safeguards:

- latest-wins semantics for repeated rapid presses
- release handling that is robust if a readback is stale
- reconnect-safe clearing of any “button still held” state

### 7. A separate transport-status surface

Current diagnostics only describe the passive DPI stream through `OpenSnek/Sources/OpenSnek/Services/AppStateTypes.swift`:

- `listening`
- `streamActive`
- `realTimeHID`
- `pollingFallback`

Needed:

- a second status for Hypershift stream readiness, separate from DPI
- diagnostics/UI wording such as:
  - `Hypershift HID listening`
  - `Hypershift HID active`
  - `Hypershift HID unavailable`

Why:

- a device can have healthy passive DPI streaming while Hypershift remains unsupported
- mixing the two into one status would be misleading

### 8. Device-profile metadata for supported products

Needed:

- a profile field for the Hypershift passive HID descriptor
- initially only on capture-validated devices
- likely separate validation for:
  - Basilisk V3 X HyperSpeed Bluetooth (`0x00BA`)
  - any future Bluetooth devices that show the same stream shape

Why:

- OpenSnek intentionally gates passive HID features behind capture-backed profile data
- this avoids subscribing to the wrong HID interface on unrelated devices

### 9. Test coverage

Minimum tests needed before shipping:

- parser tests for press and release frames
- regression tests proving DPI packets still parse unchanged
- watch-target selection tests showing both DPI and Hypershift targets can coexist
- backend tests for press -> apply clutch -> release -> restore flow
- duplicate-event / reconnect-state tests

### 10. One more capture before implementation

The remaining missing piece is the exact HID descriptor/identity of the `0x0027` stream.

Needed capture:

1. start capture before Bluetooth connection/setup completes
2. include CCCD writes and service discovery
3. open Synapse
4. press the Hypershift/DPI-clutch button once without moving the mouse

Goal:

- map `0x0027` to its characteristic UUID and CCCD enable path
- confirm whether the stream is standard HID-over-GATT input traffic versus a vendor-side notify path that only happens to sit outside the current vendor GATT command family

## Recommended Implementation Order

1. Capture the stream from connection start and identify the characteristic/descriptor path.
2. Generalize passive HID descriptors so one device can expose multiple passive input streams.
3. Add a Hypershift event parser that emits press/release with raw payload preservation.
4. Add bridge/backend async streams for Hypershift events.
5. Add clutch press/release runtime behavior using the existing BLE DPI-stage write path.
6. Add diagnostics and tests.

## Bottom Line

OpenSnek already has the right high-level architecture for passive, non-polling Bluetooth input.

What is missing is not a polling loop. The missing pieces are:

- a second passive HID descriptor
- a second passive HID parser/event pipeline
- runtime logic that turns press/release edges into clutch apply/restore behavior

So this looks feasible without introducing a fast poller, but it is not already implemented.
