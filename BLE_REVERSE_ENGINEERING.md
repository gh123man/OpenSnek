# BLE Reverse Engineering Notes

## Objective

Reverse engineer the Razer BLE configuration path used by Synapse and implement stable features in `razer_ble.py`.

## Device Context

- Primary target: Basilisk V3 X HyperSpeed
- BLE IDs: `VID 0x068E`, `PID 0x00BA`
- OS used during work: macOS (live validation), Windows captures for protocol discovery

## Capture Timeline

- `fitleredcap.pcapng`
  - First full Synapse BLE config capture
  - Established vendor write/notify path and request/response framing
  - Identified command-key model in bytes `4..7`
- `power-lighting.pcapng`
  - Isolated power timeout, sleep timeout, lighting changes
  - Confirmed raw get/set scalar key pairs
- `basic-rebind.pcapng`
  - Isolated button rebind operations for multiple slots
  - Confirmed two-step slot-select + payload write for button bindings
- `right-click-bind.pcapng`
  - Focused right-click slot transitions
  - Confirmed slot `0x02` payloads for default, left-click remap, keyboard `F`, and restore

## Reverse Engineering Strategy

1. Capture one UI action class at a time.
2. Diff write sequences and cluster by `(op, key bytes 4..7, payload length)`.
3. Correlate request id in writes with response notify headers.
4. Validate each inferred key with live write + readback.
5. Add narrow API methods only after live confirmation.
6. Keep raw fallback APIs for untyped keys.

## Core Findings

- Synapse BLE config uses vendor GATT (`...1524` write, `...1525` notify).
- Requests use an 8-byte header with request id + op + 4-byte key.
- Notify header status codes: `0x02` success, `0x03` error, `0x05` parameter error.
- Many reads/writes are scalar values via a common framing pattern.
- DPI stage table uses a dedicated multi-chunk write/read path.
- Button rebinding uses:
  - header select: `op=0x0a`, key `08 04 01 <slot>`
  - then 10-byte action payload

## Implemented from Captures

- DPI stages read/write (all 5 slots)
- Single-DPI mode helper (derived from stage table behavior)
- Power timeout raw read/write (`05 84` / `05 04`)
- Sleep timeout raw read/write (`05 82` / `05 02`)
- Lighting value raw read/write (`10 85` / `10 05`)
- Button rebinding:
  - raw payload writer
  - default helper
  - keyboard helpers
  - generic action helper
  - mouse-button helpers (left/right click)

## Validation Method

- For each setter:
  1. Send set command.
  2. Require ACK with matching request id and status `0x02`.
  3. Read back value (or repeat getter) to confirm state.
- For button actions:
  - Validate command ACK and verify physical behavior on mouse buttons.

## Operational Constraints

- BLE session can enter a bad state after aggressive probing.
- Reliable recovery: physical Bluetooth toggle on mouse (off/on), then reconnect.
- Parallel command runs can conflict on BLE access; run writes sequentially.

## Open Work

- Expand full command-key catalog for remaining Synapse settings.
- Decode remaining button action types and all slot semantics.
- Map raw scalar values to exact Synapse UI units/options.
- Capture and decode macro/media/system rebind payloads.
- Add automated capture parser tooling for key/payload diffing.

## Practical Capture Guidance

- Record one setting family per capture.
- Change one control at a time with clear before/after states.
- Include explicit restore-to-default actions in the same capture.
- For rebind captures, include: default -> target mapping -> alternate mapping -> default.
- Keep timestamps/action logs while capturing to improve correlation speed.
