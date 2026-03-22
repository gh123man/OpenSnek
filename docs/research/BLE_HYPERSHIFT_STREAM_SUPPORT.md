# BLE Hypershift Stream Support

## Status

OpenSnek now has initial support for the Bluetooth Hypershift / DPI-clutch press stream on the capture-validated Basilisk V3 X HyperSpeed Bluetooth profile.

Current shipped support includes:

- `OpenSnek/Sources/OpenSnekCore/DeviceSupport.swift` defines a `PassiveButtonInputDescriptor` alongside the existing passive-DPI descriptor.
- `OpenSnek/Sources/OpenSnekCore/DeviceSupport.swift` gives the Basilisk V3 X HyperSpeed Bluetooth profile a capture-backed passive button descriptor for slot `0x06`, usage `0x01:0x02`, report ID `0x04`, subtype `0x04`.
- `OpenSnek/Sources/OpenSnekHardware/PassiveButtonEventMonitor.swift` classifies passive button reports as `pressed`, `released`, or `other`.
- `OpenSnek/Sources/OpenSnek/Bridge/BridgeClient.swift` arms passive HID listeners for both the DPI stream and any capture-backed passive button streams on the device profile.
- `OpenSnek/Sources/OpenSnek/Services/BackendSession.swift` and `OpenSnek/Sources/OpenSnek/Services/AppStateRuntimeController.swift` propagate passive button edges through the existing backend-state update path.
- `OpenSnek/Sources/OpenSnek/UI/DeviceDetailView.swift` shows the read-only button row and a live `Held` badge while the button is pressed.

That means the current app can now:

- listen for passive DPI stage changes
- mark the stream as healthy from heartbeat traffic
- stop fast polling once a real DPI event is observed
- subscribe to the separate Hypershift-specific HID stream on the validated V3 X Bluetooth path
- decode press/release edges conservatively from the observed payload pattern
- expose a live UI pressed/held indicator on the read-only button row

It still cannot:

- trigger clutch behavior directly from passive HID input
- expose Hypershift stream health in diagnostics
- remap the button through a validated BLE vendor command family

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

## What OpenSnek Still Needs To Support

### 1. Runtime behavior for clutch press/release

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

### 2. A separate transport-status surface

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

### 3. Device-profile metadata for additional supported products

Needed:

- initially only on capture-validated devices
- likely separate validation for:
  - Basilisk V3 X HyperSpeed Bluetooth (`0x00BA`)
  - any future Bluetooth devices that show the same stream shape

Why:

- OpenSnek intentionally gates passive HID features behind capture-backed profile data
- this avoids subscribing to the wrong HID interface on unrelated devices

### 4. Test coverage beyond the initial landing

Minimum tests needed before shipping:

- parser tests for press and release frames
- regression tests proving DPI packets still parse unchanged
- backend tests for press -> apply clutch -> release -> restore flow
- duplicate-event / reconnect-state tests

### 5. One more capture before clutch implementation

The remaining missing piece is the exact HID descriptor/identity of the `0x0027` stream.

Needed capture:

1. start capture before Bluetooth connection/setup completes
2. include CCCD writes and service discovery
3. open Synapse
4. press the Hypershift/DPI-clutch button once without moving the mouse

Goal:

- map `0x0027` to its characteristic UUID and CCCD enable path
- confirm whether the stream is standard HID-over-GATT input traffic versus a vendor-side notify path that only happens to sit outside the current vendor GATT command family

### 6. Windows HID GATT enumeration

The reconnect captures showed a consistent limitation: we can see live HID notifications on `0x0027`, `0x002b`, and `0x002f`, but the capture window still starts after Windows has already claimed and subscribed to the HID service.

That means a better next step is direct HID GATT enumeration on Windows instead of another Synapse capture.

Script:

- `tools/python/enumerate_hid_gatt.py`

What it prints:

- all visible GATT services
- every HID `0x2A4D` Report characteristic
- each report's:
  - characteristic handle
  - `0x2908` Report Reference descriptor handle
  - `0x2902` CCCD handle if present
  - report ID / report type

Windows setup:

1. Install Python 3 if needed.
2. Install Bleak:
   - `pip install bleak`
3. Turn the mouse on and make sure Windows can see it on Bluetooth.

Commands:

If you know the Bluetooth address:

```bash
python tools/python/enumerate_hid_gatt.py XX:XX:XX:XX:XX:XX
```

If you do not know the address yet:

```bash
python tools/python/enumerate_hid_gatt.py --name "BSK V3 X"
```

What to send back:

- the full `HID SERVICE DETAIL` section
- especially any rows whose characteristic or descriptor handles line up with the capture-backed notify handles:
  - `0x0027` Hypershift press/release stream
  - `0x002b` passive DPI / heartbeat stream
  - `0x002f` nearby zeroed notify seen during the first release edge

If Windows still cannot expose the HID service to Bleak on this host, that itself is useful evidence and we should pivot to Linux with HOGP disabled.

## Recommended Follow-Up Order

1. Capture the stream from connection start and identify the characteristic/descriptor path.
2. Add clutch press/release runtime behavior using the existing BLE DPI-stage write path.
3. Add separate Hypershift transport diagnostics.
4. Expand profile coverage only after capture-backed validation on each device.
5. Add reconnect and duplicate-edge hardening tests.

## Bottom Line

OpenSnek already has the right high-level architecture for passive, non-polling Bluetooth input.

What is still missing is not a polling loop. The remaining work is the runtime policy that turns validated press/release edges into clutch apply/restore behavior, plus diagnostics and broader device validation.
