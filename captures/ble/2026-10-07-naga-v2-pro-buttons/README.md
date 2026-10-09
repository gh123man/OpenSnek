# Naga V2 Pro Bluetooth button capture (2026-10-07, live session)

Device: Razer Naga V2 Pro over Bluetooth Low Energy.
macOS HID identity: vendor `0x068E`, product `0x00A9`, name "Naga V2 Pro", transport BLE.
Same vendor-ID convention as the Basilisk V3 Pro Bluetooth profile (`0x068E`).

## Battery discrepancy

| Source | Reading |
| --- | --- |
| Razer Synapse 4 | 27% |
| USB receiver vendor read | `0x45` raw -> 27% |
| BLE vendor read `05 81 00 01` | `0x45` raw -> 27% |
| macOS Bluetooth HID battery | 100% (unreliable) |

The standard BLE HID battery characteristic reports 100%; the vendor protocol agrees with
Synapse. Bluetooth support should read battery from the vendor keys `05 81 00 01` (raw) and
`05 80 00 01` (status), which is what the existing BLE battery path already does.

## Vendor surface

- The vendor GATT service is present and answers the same key families as the Naga Pro BT.
- `00 81 00 00` returned `01 03 00 00` (not the USB firmware shape); serial `00 82 00 00`
  is unsupported (`status 0x05`).
- Profile inventory `03 80 00 00` -> `01 02`; active target `03 82 00 00` -> `01` (live projection).
- DPI: hardware-active (target 0) and live projection (target 1) share the owner's table;
  stored target 2 is the `Jack` profile (400..6400, active 1600); targets 3/4/5 are the
  unassigned native 400..6400 tables.
- Lighting LEDs: `0x04` and `0x05` (USB only exposed `0x04`). Brightness for stored targets
  3/4/5 reads 85; active/live targets read 0.

## Button surface

Every slot read on targets 0-5. Panel slots mirror the USB values: `0x40`-`0x4B` keyboard
`1..9,0,-,=` and `0x50`-`0x55` keyboard `1..6`. Wheel tilt uses the Basilisk-family button
IDs `0x68`/`0x69`, same as this device's USB path (unlike Naga Pro v1 BT, which uses
`0x09`/`0x0A`).

Top slots show the owner's live remaps plus the native block in the BLE read shape:

| Slot | Lane A (live) | Lane B (native/alt) |
| --- | --- | --- |
| `0x0E` (14) | `06 01 06` (DPI cycle) | `07 01 04` (scroll mode) |
| `0x34`/`0x35` (52/53) | `0d 04 00 4b/4e 00 32` (PageUp/PageDown) | `0e 01 68/69 00 14` (native tilt) |
| `0x43` (67) | `02 02 00 21` | `02 01 00 21` |
| `0x60` (96) | `02 02 00 6e` (F19) | `06 01 06` |
| `0x6D` (109) | `02 02 00 6d` (F18) | `12 01 04` |

When the two lanes differ, the 16-byte `08 84` payload interleaves them byte-by-byte; the
probe decodes this as `decoded-even-lane` / `decoded-odd-lane`. When they match, it decodes
as the duplicated-byte `decoded-function` shape. Any Swift BLE button parser must handle both.

## Flakiness

Stored target 2 reads intermittently returned stale responses (payloads beginning with request
ids such as `09`, `1a`, `1b`, or DPI-stage bytes) or `nil` for some slots. Targets 3/4 read
cleanly. Treat BLE button reads as needing the same stale-response matching the DPI path uses.

## Files

- `probe-log.txt` - identity, battery, profile, lighting, and full button sweep transcript

## BLE write/readback/restore check (2026-10-07)

Performed on the unassigned stored target 3 (stored slot 2), button slot `64`:

1. Read before: `02 01 00 1e` (native keyboard 1).
2. Wrote `keyboard_simple` HID key `0x1D` (`Z`): write ACKed `status 0x02`.
3. Readback: `decoded-even-lane 02 02 00 1d`, `decoded-odd-lane 02 01 00 1e`.
4. Restored the exact native payload `03 40 00 02 01 00 1e 00 00 00`.
5. Final readback: `02 01 00 1e`.

Confirmed: BLE stored-bank buttons are writable, read back, and restore byte-for-byte. No live
behavior was affected (target 3 is unassigned).

### Payload shapes

- 10-byte write payload: `01 <slot> 00` + 7-byte function block. Retarget by replacing byte 0
  with the target ID; for a stored target the first two bytes must be `<target> <slot>`.
- 16-byte read payload: `<slot> 00` + 14 data bytes. When the current and previous blocks are
  equal, every data byte is duplicated and the block decodes directly. When they differ, the
  payload interleaves the current block (even lane) with the alternate/previous block (odd lane),
  so any Swift parser must handle both shapes. Evidence: live slot `0x34` read current PageUp
  remap on the even lane and native tilt on the odd lane; stored target 3 slot 64 read the new
  `Z` remap on the even lane and the previous native block on the odd lane.

## Physical press over Bluetooth (2026-10-07)

With the 6-button panel installed, pressing printed labels 1..6 in a text field typed
`123456` over Bluetooth, matching the 2.4 GHz receiver capture. Button output parity between
transports is confirmed for the panel slots.

## Side-panel lighting investigation (2026-10-07, live)

Wrote static colors to each responsive LED on the live target and checked visually:

| LED | Result |
| --- | --- |
| `0x04` | Palm snake logo (red confirmed). |
| `0x05` | 12-button side-panel lighting (green confirmed). |
| `0x0A` | Writes ACK and read back empty; no visible zone. Treat as unused/write-only. |
| `0x00` | Whole-device/aggregate state; not an independent visible zone. |
| `0x01`-`0x03`, `0x06`-`0x09`, `0x0B`-`0x10` | Unsupported (`status 0x03` / no payload). |

Panel behavior:

- The 12-button plate lights through LED `0x05`.
- The 6-button plate has no lighting at all (owner checked physically; Synapse exposes no zone).
- The 2-button plate has no lighting.
- The Naga V2 Pro has no scroll-wheel lighting; Synapse exposes no scroll-wheel zone (owner
  verified in Synapse 4).

Implication for support: both transports expose the same two real zones. The USB profile
currently declares only the logo (`0x04`); it should also declare a `side_panel` zone on
`0x05`, gated to the 12-button plate if available. The Bluetooth profile should declare both
from the start.
