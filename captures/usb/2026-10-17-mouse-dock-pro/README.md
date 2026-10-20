# Mouse Dock Pro discovery + validation (2026-10-17)

Device: Razer Mouse Dock Pro `1532:00A4`, firmware `0x02010201`, serial `632616U44201307`,
`bcdDevice` `0x0101`. Raw probe output: [probe-log.txt](probe-log.txt).

## Why

The Mouse Dock Pro is a different accessory from the original Mouse Dock (`0x007E`) that OpenSnek
already supports, and it does not behave the same way on the wire. This capture records the
transaction-ID discovery, the failed-attempt evidence, and the write/readback checks that justify
the shipped `0x00A4` profile.

## Transaction ID: this dock answers only `0xFF`

`0x0F:0x84` and `0x00:0x82` were sent with each candidate transaction ID:

| Transaction ID | Result |
| --- | --- |
| `0x1F` | status `0x04` (timeout) on every command |
| `0x3F` | status `0x04` (timeout) on every command |
| `0xFF` | status `0x02`, valid payload |

This matches OpenRazer, which sets `request.transaction_id.id = 0xFF` for
`USB_DEVICE_ID_RAZER_MOUSE_DOCK_PRO`. The original Mouse Dock keeps `0x1F`, so the two docks need
separate profiles; the shipped profile pins `usbTransactionID: 0xFF` and the app applies it from the
resolved profile.

## Identifying a stale HID session

Before the dock was physically replugged, every write failed at the macOS layer with
`IOHIDDeviceSetReport` returning `0xE00002D6` (`kIOReturnTimeout`, not `kIOReturnNotPermitted`),
while `IOHIDDeviceOpen` succeeded and `IOHIDDeviceGetReport(report 0)` returned success with
`length 0`. The failure spanned every report ID `0..8` and both `kIOHIDReportTypeFeature` and
`kIOHIDReportTypeOutput`, so it was not a report-shape problem:

| Open mode | `SetReport` result | `GetReport(0)` result |
| --- | --- | --- |
| `kIOHIDOptionsTypeNone` | `0xE00002D6` on lengths 8, 88, 90, and output | success, `length 0` |
| `kIOHIDOptionsTypeSeizeDevice` | identical | identical |
| after unplug/replug | success | valid 90-byte payload |

Uninstalling Razer Synapse and its DriverKit extension did **not** change the result on its own; the
replug did. Treat a dock that answers nothing but opens cleanly as a stale session before changing
protocol logic.

## Identity and lighting

| Check | Command | Observed |
| --- | --- | --- |
| Serial | `00:82` | `632616U44201307` |
| Firmware | `00:81` | `0x02010201` |
| Device mode | `00:84` | `00 00` |
| Brightness read | `0f:84` `01 00 00` | status `0x02` at LED `0x00`, but the value is always `00` |
| Brightness read (correct address) | `0f:84` `01 0f 00` | tracks the written value: `200` -> `c8`, `64` -> `40`, `255` -> `ff`, `0` -> `00` |
| Brightness write | `0f:04` `01 00 ff` | accepted and visually confirmed; the value only reads back at LED `0x0F` |
| Effect read | `0f:82` `01 00 ...` | returns a 12-byte effect state; the LED echo comes back as `0x0f` for every requested LED, including `0x0f` itself |
| Effect writes | `0f:02` LED `0x00` | off, static, spectrum, wave (directions 1 and 2), reactive, and breath random/single/dual all answer `status 0x02` |
| LED set | `0f:82` / `0f:84` per LED | only `0x00` answers for writes; `0x01`-`0x08` return status `0x03` |
| Transaction IDs | `00:82` / `0f:84` per txn | `0x1F` and `0x3F` return status `0x04`; only `0xFF` answers |
| Custom frame / row | `0f:03` | 1-cell, 4-cell, and 8-cell row writes all answer `status 0x02` |
| Visual confirmation | `0f:02` | static pure red at brightness `0xff` rendered red; a wave effect animated; a slow breath-single effect visually pulsed blue |

The dock is declared by OpenRazer as `MATRIX_DIMS = [1, 8]`, which is consistent with the 8-cell row
being accepted.

## Shipped scope

- One zone: logo LED `0x00` (`formFactor = .accessory`).
- Effects: `off`, `static`, `spectrum`, `wave`, and the three pulse modes. Static, wave, and a
  breathing effect were visually confirmed; `reactive` is not in OpenRazer's method list for this
  device and is not exposed.
- Brightness writes and reads both ship. Writes use LED `0x00` and reads use LED `0x0F`, so the
  profile sets `usbBrightnessLEDIDs` and `usbBrightnessReadLEDIDs` separately.

## App validation follow-up

In the [2026-10-18 app pass](../2026-10-17-naga-v3-pro/app-validation-2026-10-18.md),
the owner confirmed dock removal and recovery after unplug/replug, with brightness
still readable afterward. This did not exercise the dock's receiver or charging handoff.

## Gaps

- Per-cell rendering of the 1x8 row is not mapped, so the dock ships **without** a
  software-lighting frame layout. The original Mouse Dock's single-cell frame layout and Battery
  Meter preset are therefore not offered here yet.
- Charging state and any dock-to-mouse handoff behavior were not probed; this pass only covers the
  dock's own lighting surface.
- The dock's charging/receiver role for a paired mouse was not exercised, because the test mouse
  used its own 2.4 GHz dongle rather than the dock's receiver.
