# Razer USB HID Protocol Documentation

This document describes the USB HID protocol used by Razer mice, based on reverse engineering from the [OpenRazer](https://github.com/openrazer/openrazer) project and our own testing.

## Table of Contents

- [Overview](#overview)
- [Report Structure](#report-structure)
- [Command Classes](#command-classes)
- [Implemented Commands](#implemented-commands)
- [Unimplemented Commands](#unimplemented-commands)
- [Device-Specific Notes](#device-specific-notes)
- [References](#references)

---

## Overview

Razer devices communicate via USB HID Feature Reports. The protocol uses 90-byte reports for both requests and responses.

### Connection Types

| Connection | Vendor ID | Protocol Support |
|------------|-----------|------------------|
| USB Cable | `0x1532` | Full |
| 2.4GHz Dongle | `0x1532` | Full |
| Bluetooth | `0x068e` (some devices) | Partial / transport-dependent |

**Important**: Bluetooth behavior varies by device/firmware/OS HID stack. Some devices expose configuration over Bluetooth HID, but transport method and transaction ID may differ from USB.

---

## Report Structure

All reports are exactly **90 bytes**.

```
Offset  Size  Field              Description
------  ----  -----              -----------
0       1     Status             Request: 0x00 (new command)
                                 Response: 0x01 (busy), 0x02 (success),
                                          0x03 (failure), 0x04 (timeout),
                                          0x05 (not supported)
1       1     Transaction ID     Device-specific, groups request/response
2       2     Remaining Packets  Big-endian, usually 0x0000
4       1     Protocol Type      Always 0x00
5       1     Data Size          Size of arguments (max 80)
6       1     Command Class      Category of command
7       1     Command ID         Specific command (bit 7: 0=set, 1=get)
8-87    80    Arguments          Command parameters
88      1     CRC                XOR of bytes 2-87
89      1     Reserved           Always 0x00
```

Client implementations should use the validated transaction ID for the resolved
device profile when one is known. For those devices, a command-level `0x03`
response is a firmware rejection for that command and state; do not treat it as
a signal to retry the same command with another transaction ID. Transaction-ID
candidate scanning is only a fallback for devices without a validated profile
transaction ID.

Multi-command flows must also be serialized per physical device, not merely per
HID handle or process. This includes full state sweeps, read-modify-write
helpers, and onboard profile create/rename/update/delete/select transactions.
macOS can expose more than one HID handle for the same mouse, and OpenSnek can
have both the UI app and background service alive. Interleaving a polling read
sweep with a profile metadata write can produce valid-looking command rejections
even when each command is correct in isolation.

### CRC Calculation

```python
def calculate_crc(report: bytes) -> int:
    crc = 0
    for i in range(2, 88):
        crc ^= report[i]
    return crc
```

### Command ID Convention

- **Bit 7 = 0**: SET command (write to device)
- **Bit 7 = 1**: GET command (read from device)
- Example: `0x05` = SET, `0x85` = GET (same command, different direction)

---

## Command Classes

| Class | Name | Description |
|-------|------|-------------|
| `0x00` | Standard | Device mode, serial, firmware, poll rate |
| `0x02` | Configuration | Scroll wheel, button mapping, profiles |
| `0x03` | LED | Legacy LED control |
| `0x04` | DPI | DPI and sensitivity settings |
| `0x07` | Misc | Battery, idle time, dock settings |
| `0x0F` | Matrix | RGB lighting effects |

---

## Implemented Commands

### Class 0x00 - Standard

#### Get Serial Number
```
Command:  Class 0x00, ID 0x82, Size 0x16
Args:     (none)
Response: args[0-21] = ASCII serial string
TxnID:    0xFF
```

#### Get Firmware Version
```
Command:  Class 0x00, ID 0x81, Size 0x02
Args:     (none)
Response: args[0] = major, args[1] = minor
TxnID:    0xFF
```

#### Get Poll Rate
```
Command:  Class 0x00, ID 0x85, Size 0x01
Args:     (none)
Response: args[0] = rate byte
TxnID:    0x1F (modern mice) or 0xFF (older mice)

Rate byte mapping:
  0x01 = 1000 Hz
  0x02 = 500 Hz
  0x08 = 125 Hz
```

#### Set Poll Rate
```
Command:  Class 0x00, ID 0x05, Size 0x01
Args:     [0] = rate byte (see above)
TxnID:    0x1F (modern mice) or 0xFF (older mice)
```

#### Get/Set Device Mode
```
Command:  Class 0x00, ID 0x84 (get) / 0x04 (set), Size 0x02
Args:     [0] = mode, [1] = param

Modes:
  0x00, 0x00 = Normal Mode (onboard memory active)
  0x03, 0x00 = Driver Mode (software control)
```

---

### Class 0x02 - Configuration

#### Get Scroll Mode
```
Command:  Class 0x02, ID 0x94, Size 0x02
Args:     [0] = storage/profile ID
Response: args[1] = mode (0x00=tactile, 0x01=freespin)
TxnID:    0x1F
```

#### Set Scroll Mode
```
Command:  Class 0x02, ID 0x14, Size 0x02
Args:     [0] = storage/profile ID, [1] = mode
TxnID:    0x1F
```

#### Get/Set Scroll Acceleration
```
Command:  Class 0x02, ID 0x96 (get) / 0x16 (set), Size 0x02
Args:     [0] = storage/profile ID, [1] = enabled (0x00/0x01)
TxnID:    0x1F
```

#### Get/Set Scroll Smart Reel
```
Command:  Class 0x02, ID 0x97 (get) / 0x17 (set), Size 0x02
Args:     [0] = storage/profile ID, [1] = enabled (0x00/0x01)
TxnID:    0x1F
```

#### Get/Set Button Function
```
Get:      Class 0x02, ID 0x8C, Size 0x0A
Set:      Class 0x02, ID 0x0C, Size 0x0A
Args:     [0] = profile (`0x00` direct/effective layer, `0x01` persistent slot 1;
                        Basilisk V3 35K also validates persistent slots `0x02..0x05`)
          [1] = button slot
          [2] = hypershift flag (0x00 normal, 0x01 hypershift layer)
          [3] = function class
          [4] = function-data length (0..5)
          [5..9] = function data bytes
TxnID:    0x1F
```

Validated slot ids on Basilisk V3 X HyperSpeed (`0x00B9`): `0x01..0x05`, `0x09`, `0x0A`, `0x60`.
Known rejection on Basilisk V3 X HyperSpeed (`0x00B9`):
- `0x06`: Hypershift / Boss-sniper control returns status `0x03` on `0x02:0x8C` reads and is not exposed by the validated USB button-function path

Validated slot ids on Basilisk V3 Pro (`0x00AB`): `0x01..0x05`, `0x09`, `0x0A`, `0x0F`, `0x34`, `0x35`, `0x6A`.
Observed control labels on `0x00AB`:
- `0x0F`: sensitivity clutch / DPI clutch
- `0x34`: wheel tilt left
- `0x35`: wheel tilt right
- `0x6A`: profile button
- observed non-match: `0x60` does not read back like the Basilisk V3 35K top DPI-button block and is not currently shipped as a validated V3 Pro control
- observed write behavior: slot `0x0F` accepts remap writes and restores cleanly to its default block; slot `0x6A` accepted remap writes during probe, but repeated write/readback cycles became unstable enough that OpenSnek keeps it hidden for now

Validated slot ids on Basilisk V3 35K (`0x00CB`): `0x01..0x05`, `0x09`, `0x0A`, `0x0E`, `0x0F`, `0x34`, `0x35`, `0x60`, `0x6A`.
Observed control labels on `0x00CB`:
- `0x0E`: scroll-mode toggle
- `0x0F`: sensitivity clutch / DPI clutch
- `0x34`: wheel tilt left
- `0x35`: wheel tilt right
- `0x60`: top DPI button
- `0x6A`: profile button

Validated function block examples:
- right click: `01 01 02 00 00 00 00`
- back button (default for slot `0x04`): `01 01 04 00 00 00 00`
- keyboard key `A` (HID `0x04`): `02 02 00 04 00 00 00`
- keyboard key with modifier, for example `Command + [` (modifier `0x08`, HID `0x2F`): `02 02 08 2f 00 00 00`
- disable: `00 00 00 00 00 00 00`
- DPI cycle action: `06 01 06 00 00 00 00`
- Basilisk V3-family observed/inferred working scroll left action: `0e 03 68 00 14 00 00`
- Basilisk V3-family observed/inferred working scroll right action: `0e 03 69 00 14 00 00`
- Basilisk V3 Pro DPI clutch action: `06 05 05 01 90 01 90`
- Basilisk V3 Pro DPI clutch action at 800 DPI: `06 05 05 03 20 03 20`
- Basilisk V3 Pro sensitivity-clutch default (`0x0F`): `06 05 05 01 90 01 90`
- Basilisk V3 Pro wheel-tilt defaults (`0x34`, `0x35`) observed on 2026-04-03 after Synapse rebind: `0e 03 68 00 14 00 00` / `0e 03 69 00 14 00 00`
- OpenSnek now applies that same wheel-tilt block across the Basilisk V3 / V3 Pro / 35K USB family as the best current inference from their shared slot model; only the V3 Pro form has been directly read back in-session so far
- Basilisk V3 35K sensitivity-clutch default (`0x0F`): `06 01 05 01 90 01 90`
- Basilisk V3 Pro / 35K profile-button default (`0x6A`): `12 01 01 00 00 00 00`
- Basilisk V3 35K observed alternate DPI-button block (`0x60`): `04 02 0F 7B 00 00 00`

Client note:
- USB function blocks are not BLE `p0/p1/p2` payloads. Use `class,len,data[]` encoding directly.
- Legacy non-analog write command `0x02:0x0D` is still observed in ecosystem notes but is fallback-only on this device.
- On Basilisk V3 X HyperSpeed (`0x00B9`), the Hypershift / Boss-sniper control (`0x06`) rejects `0x02:0x8C` button reads with status `0x03`; do not treat it as part of the writable/readable USB button-function slot set.
- Basilisk V3 Pro (`0x00AB`) and Basilisk V3 35K (`0x00CB`) `0x02:0x8C` reads do not use the simpler Basilisk V3 X payload shape. Observed extended-layout slots decode from `response[11..<18]`; treating `response[10...]` as the block causes false positives and mislabels on extra controls.
- Always validate the echoed `profile` and `slot` bytes before decoding a `0x02:0x8C` read. This device will otherwise yield stale-looking success frames that can be mistaken for additional slots.
- Treat layered button writes as all-or-nothing at the client boundary: if a persistent-layer write is requested and fails, do not continue on to a direct/live write and do not surface the operation as success.
- OpenSnek normalizes both `06 01 06 00 00 00 00` and the observed `0x60` variant `04 02 0F 7B 00 00 00` as the user-facing `DPI Cycle` action.
- On the observed V3 Pro clutch slot (`0x0F`), the default block is not a simple mouse/keyboard payload; preserve `06 05 05 01 90 01 90` when restoring the native clutch behavior.
- For the observed V3 Pro / 35K DPI payloads, the trailing four bytes are configurable X/Y DPI values. OpenSnek now preserves and writes independent X/Y values on the Basilisk V3 Pro and Basilisk V3 35K instead of collapsing them to a single scalar.
- The same `DPI Clutch` block was also written/read back successfully on other writable Basilisk USB slots (`0x04` on both the V3 Pro and 35K), so OpenSnek exposes `DPI Clutch` as a remap action on both supported Basilisk USB profiles.
- On the attached Basilisk V3 35K (`0x00CB`) on March 24, 2026, the native clutch slot `0x0F` accepted both a right-click remap and the same `06 05 05 03 20 03 20` 800-DPI clutch payload on persistent profile `0x01`, and slot `0x04` also accepted the `DPI Clutch` payload on direct/live profile `0x00`.
- Preserve the observed 35K native clutch restore block `06 01 05 01 90 01 90` when restoring slot `0x0F`; the 35K default differs from the V3 Pro default even though both devices accept the same `DPI Clutch` action payload.
- On the observed V3 Pro profile-button slot (`0x6A`), remap writes can land, but repeated `0x02:0x0C` / `0x02:0x8C` cycles eventually returned timeout/no-response frames during probing. Keep this slot out of shipped UI until that write/readback path is stable.
- Keyboard category function data is `modifier byte, HID key`. The modifier byte follows the Razer/Basilisk convention documented from Synapse captures: `0x01` left Ctrl, `0x02` left Shift, `0x04` left Alt/Option, `0x08` left GUI/Command, `0x10` right Ctrl, `0x20` right Shift, `0x40` right Alt/Option, `0x80` right GUI/Command.
- Treat button access as three separate categories during new-device bring-up:
  - `editable`: validated over `0x02:0x0C`
  - `protocol-read-only`: readable from `0x02:0x8C`, but no validated writable path
  - `software-read-only`: fixed control exposed to software through auxiliary HID input/report paths rather than button-function writes
- On Basilisk V3 35K, OpenRazer documents keyboard-interface report-4 codes `0x50 = profile` and `0x51 = sensitivity clutch`. The profile button still behaves like a software-read-only control, but the native clutch slot also has a validated USB button-function write path, so do not blanket-mark `0x0F` as software-read-only on this device.

#### Get Onboard Profile Summary
```
Command:  Class 0x00, ID 0x87, Size 0x00
Response: args[0] = reported profile/state byte candidate
          args[1] = unknown; observed as both 0x00 and 0x32
          args[2] = onboard profile count candidate
TxnID:    0x1F
```

Observed on Basilisk V3 35K (`0x00CB`):
- response payload `01 00 05` on USB, indicating active profile `1` and `5` onboard profiles
- tested write candidates `0x00:0x07` with payloads `02`, `02 00`, `02 00 05`, and `02 00 00` all returned status `0x05` (`not supported`) on the attached device
- the hardware active-profile write path therefore remains unresolved
- confirmed profile-model behavior from live write/readback on slot `0x04`:
  - writing persistent profile `0x05` is isolated storage: profile `0x05` reads back the new block while persistent profile `0x01` and direct/live profile `0x00` stay unchanged
  - writing persistent profile `0x01` while the device reports active profile `1` also changes direct/live profile `0x00`
  - writing direct/live profile `0x00` afterward does not write back into persistent profile `0x01`
- practical interpretation:
  - profile `1` is the hardware-default active backing store
  - profiles `2...5` behave like dumb persistent storage slots
  - profile `0` (`NOSTORE` / direct) is a writable live layer
  - software can project a stored slot into the live layer, but that is not the same thing as changing a hardware-selected active profile number
  - this slot-addressed model is currently validated only for button mappings; DPI and lighting use separate storage keys below and should not be assumed to participate in profiles `2...5`

Observed on Basilisk V3 Pro (`0x00AB`):
- observed payloads `01 00 03` and `02 00 03` on USB during different sessions
- on the attached V3 Pro on March 25, 2026, the bottom profile LED changed while `0x00:0x87` continued to report `02 00 03`, so this register is not yet validated as the hardware-selected live profile on that device
- on the attached V3 Pro on June 16, 2026, the same register returned `02 32 03`; the middle byte is therefore not reserved-zero and should remain unknown until decoded
- in that same pass, USB direct/live storage `0` and persistent/base storage `1` did not match stored storage `2`, so `args[0] = 0x02` is not enough evidence to treat `0x00:0x87` as the active effective profile
- later on June 16, 2026, direct active-profile reads were mapped through `0x05:0x84`; this summary register stayed `02 32 03` while `0x05:0x84` changed between `03` and `01` with the physical profile-cycle button
- a follow-up V3 Pro pass found `0x05:0x84` can return `data_size = 00` while still carrying the active profile in `args[0]`; clients should parse the success/class/cmd echo and `args[0]`, not require a non-zero size byte
- nearby profile-management reads remain summary-only: `0x05:0x80` returned `03`, `0x05:0x8A` returned `05`, and `0x05:0x81` returned `05 01 03 05`, but `0x05:0x04 05` still rejected, so none is a trusted cycleable inventory list
- the corresponding low-bit write candidate (`0x00:0x07`) is not yet validated for active-profile switching

Client note:
- See [USB Profile CRUD Draft](./USB_PROFILE_CRUD_SPEC.md) for the current USB profile-bank model.
- Per-slot button-function storage via `0x02:0x8C` / `0x02:0x0C` is still validated and remains the canonical source for button-slot inspection and write/readback testing.
- OpenSnek should use `0x05:0x84` for V3 Pro USB active-profile hydration and treat `0x00:0x87` as summary/count telemetry. Full onboard profile controls still need safe inventory and metadata-write/create semantics before the UI can reflect the mouse honestly.

Bring-up checklist for future devices:
- read `0x00:0x87` before and after changing profiles in vendor software; if the reported active slot never changes, do not assume the device has a writable hardware active-profile register
- if physical profile indicators or button behavior change while `0x00:0x87` does not, treat the register as a profile summary hint only and do not surface it as authoritative UI state
- test `0x02:0x0C` / `0x02:0x8C` on one non-active stored slot and confirm whether the write is isolated or leaks into direct/live state
- test persistent profile `0x01` and direct/live profile `0x00` separately; some devices alias or mirror those paths when profile `1` is the hardware-default active store
- test a direct/live write after a persistent profile `0x01` write to learn whether the mirroring is one-way or fully aliased
- only claim true hardware profile switching after validating both the reported active-profile state and the effective live behavior across reconnects / vendor-software exit

---

### Class 0x04 - DPI

#### Get DPI
```
Command:  Class 0x04, ID 0x85, Size 0x07
Args:     [0] = storage (NOSTORE=0x00 or VARSTORE=0x01)
Response: args[0] = storage
          args[1-2] = DPI X (big-endian)
          args[3-4] = DPI Y (big-endian)
TxnID:    0x1F (Basilisk V3 X), 0x3F or 0xFF (others)
```

Observed on Basilisk V3 35K (`0x00CB`):
- both `0x00` and `0x01` read back successfully
- writing `0x01` updates the persisted DPI state and also mirrors into `0x00` live state
- writing `0x00` updates only the live state and does not write back into `0x01`
- no slot-indexed DPI storage path is currently known beyond this `0x00`/`0x01` live-vs-persisted split

Observed on Basilisk V3 Pro (`0x00AB`) on June 16, 2026:
- storage/profile IDs `0..5` all read back successfully through `0x04:0x85`
- IDs `2` and `3` matched the stored profiles previously created over Bluetooth, confirming that USB and BLE address the same stored DPI banks on this device
- see `USB_PROFILE_CRUD_SPEC.md` for the full storage table and write-safety notes

#### Set DPI
```
Command:  Class 0x04, ID 0x05, Size 0x07
Args:     [0] = storage
          [1-2] = DPI X (big-endian, 100-30000)
          [3-4] = DPI Y (big-endian, 100-30000)
          [5-6] = 0x00, 0x00
TxnID:    0x1F
```

#### Get DPI Stages
```
Command:  Class 0x04, ID 0x86, Size 0x26
Args:     [0] = storage/profile ID
Response: args[0] = storage
          args[1] = active stage ID (on Basilisk V3 X this is 1-indexed)
          args[2] = number of stages (1-5)
          args[3+n*7] = stage data for each stage

Stage data (7 bytes each):
  [0] = stage ID (commonly 1-indexed on Basilisk V3 X)
  [1-2] = DPI X (big-endian)
  [3-4] = DPI Y (big-endian)
  [5-6] = reserved (0x00)
TxnID:    0x1F
```

#### Set DPI Stages
```
Command:  Class 0x04, ID 0x06, Size 0x26
Args:     [0] = storage/profile ID
          [1] = active stage ID (must match a stage entry ID)
          [2] = count (1-5)
          [3+n*7] = stage data (same format as above)
TxnID:    0x1F
```

Client note: treat `active` as a stage-ID token and map it against entry `[0]` stage IDs. Do not assume a fixed zero-based index.

Observed on Basilisk V3 Pro (`0x00AB`) on June 16, 2026:
- `0x04:0x86` accepted storage/profile IDs `0..5` when queried serially
- storage `2` returned the Bluetooth-created target-`2` table `400,800,1600,3200,6400`
- storage `3` returned the Bluetooth-recreated target-`3` table `760,960,1160,1360,1560`
- stored-bank writes are not yet enabled in production; changed-value `0x04:0x05` / `0x04:0x06` write/readback with restore is validated on profile `5`, and those values persisted across USB reconnect. Cross-transport readback and power-cycle persistence still need guarded validation before shipping.

#### Passive USB DPI Input Report (Observed on Basilisk V3 X HyperSpeed `0x00B9`, Basilisk V3 Pro `0x00AB`; matching interface tuple present on Basilisk V3 35K `0x00CB`)

The 90-byte USB configuration protocol above remains a host-initiated HID `Feature` report exchange. It does not expose a generic subscription channel for device state.

Separately, the observed Basilisk V3 X HyperSpeed and Basilisk V3 Pro USB stacks emit a spontaneous HID `Input` report on an auxiliary keyboard-style interface when the mouse DPI changes on-device. A locally attached Basilisk V3 35K exposes the same auxiliary HID interface tuple, so OpenSnek now arms the same passive listener there and keeps fast-poll fallback enabled until a live callback is actually observed on the current host:

```
Interface: usage page 0x01, usage 0x06, max input report size 16, max feature report size 1
Report ID: 0x05
Payload:   0x02 <dpi_x_hi> <dpi_x_lo> <dpi_y_hi> <dpi_y_lo> ...
```

Observed examples:
- `05 02 03 20 03 20 ...` -> `800 x 800`
- `05 02 07 d0 07 d0 ...` -> `2000 x 2000`
- `05 02 04 4c 04 4c ...` -> `1100 x 1100`

Client notes:
- OpenSnek now enables this passive HID listener on the Basilisk V3 X HyperSpeed USB (`0x00B9`), Basilisk V3 Pro USB (`0x00AB`), and Basilisk V3 35K USB (`0x00CB`) profiles
- accept both callback buffer shapes seen on macOS HID stacks:
  - leading report id present: `05 02 ...`
  - report id already stripped: `02 ...`
- use this report only for live DPI refresh
- battery, poll rate, lighting, profile, and other USB configuration state still require normal feature-report polling/readback
- host/API caveat from local macOS probing on 2026-03-12:
  - `OpenSnekProbe usb-input-listen --pid 0x00ab` armed all five exposed USB HID interfaces (`0x01:0x02`, two `0x59:0x01`, and two `0x01:0x06`) and observed zero `IOHIDDeviceRegisterInputReportCallback` deliveries during live DPI-cycle attempts
  - `OpenSnekProbe usb-input-values --pid 0x00ab` likewise observed zero `IOHIDManagerRegisterInputValueCallback` deliveries during the same DPI-cycle probing window
  - `OpenSnekProbe usb-input-listen --pid 0x00cb` on an attached Basilisk V3 35K exposed four HID interfaces, including the same two `0x01:0x06` candidates (`input=16/8`, `feature=1/0`) used for passive DPI listener matching
  - treat passive USB DPI callbacks as host-stack-dependent until a live callback is observed on the current machine; keep USB fast-DPI polling as the recovery path

#### Passive USB Profile-Cycle Input Report (Observed on Basilisk V3 Pro `0x00AB`)

The physical profile-cycle button emits a passive HID hint on the same
keyboard-style `0x01:0x06` interface family used for USB passive DPI reports.
On the attached V3 Pro on June 16, 2026, two profile-button presses produced
the same pair on the `input=16`, `feature=1` interface:

```text
04 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
05 39 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

The reports were separated by about 200 ms. Treat the `05 39 ...` report as
the debounce trigger, then refresh effective storage/profile `0`. In the same
pass, storage `0` moved first to the stored profile `2` DPI table and then to
the stored profile `3` DPI/brightness state. `0x00:0x87` stayed `02 32 03`, so
do not use the summary register as the active profile ID on this device.

---

### Class 0x07 - Misc

#### Get Battery Level
```
Command:  Class 0x07, ID 0x80, Size 0x02
Args:     (none)
Response: args[0] = charging (0x00=no, 0x01=yes)
          args[1] = level (0-255, map to 0-100%)
TxnID:    0x1F
```

#### Get/Set Idle Time
```
Command:  Class 0x07, ID 0x83 (get) / 0x03 (set), Size 0x02
Args:     [0-1] = idle time in seconds (big-endian)
TxnID:    0x1F

OpenRazer bounds:
  60..900 seconds
```

#### Get/Set Low Battery Threshold
```
Command:  Class 0x07, ID 0x81 (get) / 0x01 (set), Size 0x01
Args:     [0] = threshold percentage
TxnID:    0x1F

OpenRazer raw threshold clamp:
  0x0C..0x3F
Examples:
  0x0C ~= 5%
  0x26 ~= 15%
  0x3F ~= 25%
```

### Class 0x02 - Scroll Wheel Controls

#### Get/Set Scroll Mode
```
Command:  Class 0x02, ID 0x94 (get) / 0x14 (set), Size 0x02
Args:     [0] = storage/profile ID, [1] = mode
Modes:    0x00=tactile, 0x01=freespin
```

#### Get/Set Scroll Acceleration
```
Command:  Class 0x02, ID 0x96 (get) / 0x16 (set), Size 0x02
Args:     [0] = storage/profile ID, [1] = enabled (0x00/0x01)
```

#### Get/Set Scroll Smart Reel
```
Command:  Class 0x02, ID 0x97 (get) / 0x17 (set), Size 0x02
Args:     [0] = storage/profile ID, [1] = enabled (0x00/0x01)
```

### Class 0x0F - Scroll LED Brightness and Effects

Validated on Basilisk V3 X HyperSpeed (`0x00B9`), Basilisk V3 Pro (`0x00AB`), and Basilisk V3 35K (`0x00CB`) over USB.

#### Get/Set Scroll LED Brightness
```
Get:      Class 0x0F, ID 0x84, Size 0x03
Set:      Class 0x0F, ID 0x04, Size 0x03
Args:     [0] = storage (`0x00` direct/live observed on `0x00CB`, `0x01` persisted/VARSTORE), [1] = LED ID, [2] = brightness (0..255)
```

Validated LED IDs on `0x00B9`:
- `0x01`: supported for brightness read/write
- other tested IDs (`0x00`, `0x02..0x08`): failure status on brightness get

Validated LED IDs on `0x00CB`:
- `0x01`: scroll wheel
- `0x04`: logo
- `0x0A`: underglow

Validated LED IDs on `0x00AB`:
- `0x01`: scroll wheel
- `0x04`: logo
- `0x0A`: underglow

Client note:
- For whole-device USB lighting on Basilisk V3 Pro and Basilisk V3 35K, apply brightness/effect writes to all validated LED IDs (`0x01`, `0x04`, and `0x0A`).
- On the attached Basilisk V3 35K, brightness reads on `0x0F:0x84` succeed for both storage `0x00` and `0x01`. Treat lighting the same way as DPI until proven otherwise: a separate live/persisted layer, not a slot-addressed onboard-profile store.
- On the attached Basilisk V3 Pro on June 16, 2026, brightness reads on `0x0F:0x84` succeeded for storage/profile IDs `0..5` and all validated LED IDs. Storage `3` returned `0x60`, matching the Bluetooth-recreated target-`3` profile, while the other banks returned `0x54`. Treat brightness as profile-scoped on this device. Changed-value `0x0F:0x04` stored-bank write/readback with restore is validated on profile `5`, and those values persisted across USB reconnect. Cross-transport readback and power-cycle persistence still need guarded validation before shipping.

#### Get/Set Scroll LED Effects
```
Get:      Class 0x0F, ID 0x82, Size 0x0C
Set:      Class 0x0F, ID 0x02, Size varies
Common:   [0] = storage/profile ID, [1] = LED ID, [2] = effect id
```

Observed-working payload families:
- none: `01 01 00 00 00 00`
- spectrum: `01 01 03 00 00 00`
- wave: `01 01 04 <dir> 28 00` (`dir` tested `0x01`/`0x02`)
- static: `01 01 01 00 00 01 <R> <G> <B>`
- reactive: `01 01 05 00 <speed 1..4> 01 <R> <G> <B>`
- breath random: `01 01 02 00 00 00`
- breath single: `01 01 02 01 00 01 <R> <G> <B>`
- breath dual: `01 01 02 02 00 02 <R1> <G1> <B1> <R2> <G2> <B2>`

Validated on Basilisk V3 Pro (`0x00AB`) on June 16, 2026:
- `0x0F:0x82`, size `0x0C`, args `<profile> <led> 00 00 00 00 00 00 00 00 00 00` returns a 12-byte effect-state payload for profile IDs `0..5` and LED IDs `0x01`, `0x04`, and `0x0A`.
- static-color readback shape: `00 <led> 01 00 00 01 <R> <G> <B> 00 00 00`. The first response byte stayed `00` even for stored profile reads; use the requested profile plus the LED echo, not that storage echo, to associate the response.
- assigned stored profile `2` accepted per-zone static-color writes through `0x0F:0x02`, size `0x09`, payload `<profile> <led> 01 00 00 01 <R> <G> <B>`.
- after selecting profile `2` with `0x05:0x04`, effective profile `0` returned the same per-zone static colors through `0x0F:0x82`; selecting profile `1` restored effective profile `0` to profile `1`'s static red state.
- non-static payloads are readable raw effect state. OpenSnek currently decodes/writes static colors in onboard profile snapshots and leaves non-static effect editing outside the v1 profile CRUD model.

---

## Unimplemented Commands

These commands are documented but not yet implemented in this tool.

### Advanced Button Action Catalog

`0x02:0x8C/0x0C` is now validated for base function-block transport, but the full action taxonomy
(macro families, media/consumer, analog variants) is still incomplete per device/firmware.

Open questions:
- exact behavior of advanced function classes (`0x03..0x05`, `0x07`, `0x09`, `0x0A`, `0x0F`, `0x12`)
- interoperability of legacy non-analog command `0x02:0x0D`
- per-device slot map differences beyond the validated Basilisk V3 X set

### Profile Management

**Status**: Partially documented in [USB Profile CRUD Draft](./USB_PROFILE_CRUD_SPEC.md).

Current known USB profile support is setting-bank oriented:
- DPI scalar/stages: `0x04:0x85/0x05` and `0x04:0x86/0x06` with storage/profile IDs
- button bindings: `0x02:0x8C/0x0C` with profile IDs
- scroll mode / acceleration / smart reel: `0x02:0x94/0x14`, `0x02:0x96/0x16`, `0x02:0x97/0x17` with storage/profile IDs
- lighting brightness: `0x0F:0x84/0x04` with storage/profile IDs
- active profile ID read: `0x05:0x84`, size `0x00`
- active profile selector: `0x05:0x04` with a profile ID
- assigned profile inventory: `0x05:0x81`, with count hint `0x05:0x80`
- metadata reads/writes: `0x05:0x88` / `0x05:0x08` chunks with slot IDs `0x02..0x05`
- metadata create/assign prelude: `0x05:0x02 <profile>` before full `0x05:0x08` chunks
- delete/unassign from the hardware cycle ring: `0x05:0x03` with a stored profile ID

#### Get Active Onboard Profile
```
Command:  Class 0x05, ID 0x84, Size 0x00
Response: args[0] = active profile ID
```

Observed on Basilisk V3 Pro (`0x00AB`) on June 16, 2026:
- `0x05:0x84` returned `03` while effective profile `0` matched stored profile `3`.
- after a physical profile-cycle button press, `0x05:0x84` returned `01` and effective profile `0` matched base/profile `1`.
- after another physical profile-cycle button press, `0x05:0x84` returned `03` and effective profile `0` again matched stored profile `3`.
- `0x00:0x87` stayed `02 32 03` throughout those transitions.

#### Set Active Onboard Profile
```
Command:  Class 0x05, ID 0x04, Size 0x01
Args:     [0] = active profile ID
Response: success echoes the requested profile ID
```

Observed on Basilisk V3 Pro (`0x00AB`) on June 16, 2026:
- `0x05:0x04`, args `01`, ACKed and left/reported active profile `1`.
- `0x05:0x04`, args `03`, ACKed, `0x05:0x84` changed to `03`, and effective profile `0` matched stored profile `3`.
- `0x05:0x04`, args `02`, `04`, and `05`, returned status `0x03` when those profiles were unassigned or had invalid metadata, even though those banks remained readable.
- after `0x05:0x02 04` plus four full `0x05:0x08` chunks, `0x05:0x04 04` ACKed; after `0x05:0x03 04`, it rejected again.

Client note:
- Treat `0x05:0x04` as the active selector for assigned/cycleable USB profiles. Prefer `0x05:0x81` for inventory and `0x05:0x84` for passive active-profile refresh.

#### Get Assigned Onboard Profiles
```
Count:    Class 0x05, ID 0x80, Size 0x00
Response: args[0] = assigned profile count

List:     Class 0x05, ID 0x81, Size 0x00
Response: args[0] = max profile ID
          args[1...] = assigned profile IDs
```

Observed on Basilisk V3 Pro (`0x00AB`) on June 16, 2026:
- after cleanup, `0x05:0x80` returned `02` and `0x05:0x81` returned `05 01 03`.
- after `0x05:0x02 04` plus full `0x05:0x08` metadata chunks, `0x05:0x80` returned `04` and `0x05:0x81` returned `05 01 03 04 05`.
- after `0x05:0x03 04` and `0x05:0x03 05`, `0x05:0x80` returned `02` and `0x05:0x81` returned `05 01 03`.
- `0x05:0x8A` returned `05` and is treated as a max-bank hint, not the assigned list.

#### Onboard Profile Metadata Bulk Object
```
Read:     Class 0x05, ID 0x88, Size 0x50
Write:    Class 0x05, ID 0x08, Size 0x50
Args:     [0] = slot/profile ID
          [1-2] = offset bytes as used by Synapse/OpenRazer chunks
          [3] = 0x00
          [4] = 0xFA marker
          [5...] = metadata bytes for writes
Response: args[0-4] echo the chunk header
          args[5...] = metadata bytes
```

The object length is `0x00FA` bytes. Reads use four full `0x50` chunks with
offsets `0x0000`, `0x004B`, `0x0096`, and `0x00E1`.

Product metadata writes must write the full `0x00FA` object using offsets
`0x0000`, `0x004B`, `0x0096`, and `0x00E1`. The `0x00E1` chunk is padding-only
for the mapped UUID/name/owner fields, but Basilisk V3 Pro USB firmware can
leave the metadata object invalid after partial known-field writes. Treat strict
metadata readback as required for create/rename success.

The padding-tail write at offset `0x00E1` can return no status even when the
firmware has accepted the full metadata object. Treat a missing tail response as
indeterminate, not as a final failure: do not issue a second metadata write
unless readback proves the object did not land. Require strict `05:88` readback
of the UUID/name/owner fields before reporting success.

Rename transactions are metadata-object-only. Check assignment from raw
inventory, read the existing UUID/name/owner chunks completely, then write the
full renamed metadata object while preserving the existing UUID and owner. Do
not perform a full profile snapshot read before the metadata write, and do not
synthesize a fallback UUID for a rename write when metadata readback is
incomplete.

All-zero or all-`0xFF` UUID bytes are invalid metadata, not real UUIDs. If an
assigned USB profile has complete known metadata chunks but an all-`0xFF` UUID,
repair the metadata object before applying the requested rename: generate a new
UUID, preserve any readable owner if present, write the full `0x00FA` metadata
object, then require strict metadata readback. This repair path is only for
assigned profiles with corrupt metadata; ordinary create/rename transactions
also use full metadata object writes.

Observed on Basilisk V3 Pro (`0x00AB`) on June 16, 2026:
- slot `0x02`, offset `00 00`: UUID `3a35ec93-bee1-4b29-9d3d-0d2b88f9edef`, name `OPENSNEK_MAC_SLOT_1`
- slot `0x03`, offset `00 00`: UUID `c7aae39e-43b0-41ae-bf46-b4ae556a4a02`, name `OPENSNEK_RECREATE_SLOT_2`
- slot `0x03`, offsets `00 40` and `00 80`: owner-hash chunks matching the Bluetooth metadata structure
- slot `0x04`, offset `00 00`: UUID `27530668-c3e2-4e0a-a06e-a4854383c4e9`, name `OS_P4_RENAMED`
- slot `0x05`, offset `00 00`: UUID `18f2a4cc-ecb8-4765-b532-9df401a686d6`, name `OS_P5`
- after an unsafe partial `0x05:0x08` probe, slot `0x05` metadata read back as UUID `ffffffff-ffff-ffff-ffff-ffffffffffff`, name `nil`.
- a later full-object `0x05:0x08` repair restored slot `0x05` to UUID `18f2a4cc-ecb8-4765-b532-9df401a686d6`, name `OS_P5_BULK_MAP`, without changing mapped DPI/brightness/button settings.
- a full-object `0x05:0x08` repair also restored assigned slot `0x04` from all-`0xFF` metadata to UUID `27530668-c3e2-4e0a-a06e-a4854383c4e9`, name `Profile 4`, without changing mapped DPI/brightness/button settings.
- direct `0x05:0x08` on unassigned slot `0x04` returned status `0x03`; `0x05:0x02 04` followed by four full `0x05:0x08` chunks assigned it and made `0x05:0x04 04` ACK.
- the `0x05:0x02` assignment path disturbed profile `4` DPI/brightness and required profile-addressed content restore. Treat create as metadata assignment followed by explicit content writes/readback.

#### Delete / Unassign Onboard Profile
```
Command:  Class 0x05, ID 0x03, Size 0x01
Args:     [0] = stored profile ID
Response: echoes the stored profile ID
```

Observed on Basilisk V3 Pro (`0x00AB`) on June 16, 2026:
- `0x05:0x03`, args `05`, ACKed and did not erase profile `5`'s readable settings/metadata bank.
- `0x05:0x03`, args `02`, ACKed; profile `2` remained readable, but the next physical profile-cycle press skipped profile `2` and moved effective profile `0` to stored profile `3`.
- `0x05:0x03`, args `04` and `05`, ACKed after temporary create/repair probes; `0x05:0x81` returned to `05 01 03`, and selectors for `04`/`05` rejected again.

Delete note:
- Treat this as cycle-ring unassign, not storage erase. It matches the USB role of Bluetooth `03 06 <target> 00` closely enough for guarded research tooling, but production UI should avoid promising destructive erase semantics.

Client note:
- `0x05:0x88` / `0x05:0x08` map the UUID/name/owner metadata object, not a whole settings blob. Use only full-object chunks.
- `0x05:0x02` + full `0x05:0x08` can create/assign a named profile, but the profile content must be rewritten and verified after assignment.
- `OpenSnekProbe usb-profile-read` is the current read-only diagnostic path for collecting `00:87`, profile metadata chunks, DPI scalar/stages, brightness zones, and selected button slots in one serial USB pass.
- `OpenSnekProbe usb-profile-active-read` reads the direct active-profile ID via `0x05:0x84`.
- `OpenSnekProbe usb-profile-active-set --profile 3 --yes` wraps the validated `0x05:0x04` selector for assigned profiles.
- `OpenSnekProbe usb-profile-verify-writes --profile 5 --yes` is the current guarded same-value write verifier for stored-profile DPI scalar, DPI stages, and brightness. It validates echoed profile/LED bytes on readback to reject stale USB feature-report replies.
- `OpenSnekProbe usb-profile-verify-changed-writes --profile 5 --yes` is the guarded changed-value verifier. It snapshots profile `5`, writes temporary DPI scalar/stage/brightness changes, validates readback, and restores the original values before exit.
- `OpenSnekProbe usb-profile-delete --profile 2 --yes` is the guarded delete/unassign probe path. Confirm the physical profile-cycle behavior after running it, because the profile bank remains readable.
- In the reconnect persistence pass, profile `5` retained temporary scalar `900x900`, first stage `500x500`, and `0x55` brightness on all three zones after USB unplug/replug, then restored to the original `800x800`, `400/800/1600/3200/6400`, and `0x54` brightness values.

Unresolved:
- power-cycle and cross-transport persistence for full create/rename/delete flows
- non-static effect payload editing, macro, and any other Synapse-only per-profile surfaces

### RGB Lighting (Class 0x0F)

**Status**: Partially implemented. Scroll wheel LED brightness and effect families above are implemented and hardware-validated. Matrix-wide/custom-frame and multi-zone abstractions are still unimplemented.

```
Static Effect:
  Command: Class 0x0F, ID 0x02, Size varies
  Args: [0]=VARSTORE, [1]=LED_ID, [2]=effect, [3+]=params

Effects:
  0x00 = Off
  0x01 = Wave
  0x02 = Reactive
  0x03 = Breathing
  0x04 = Spectrum
  0x05 = Custom Frame
  0x06 = Static
```

---

## USB/BLE Parity Matrix

| Feature (User-Level) | USB (this spec) | BLE Vendor Spec | Script Status (`razer_usb.py` / `razer_ble.py`) | Gap |
|---|---|---|---|---|
| Serial read | `00:82` | Observed key `01 83 00 00` (read only) | Implemented in both scripts via HID path | Need stable BLE vendor mapping support across stacks |
| Firmware read | `00:81` | Not mapped in BLE vendor keys | Implemented in both scripts via HID path | Need BLE vendor command mapping |
| Device mode | `00:84/04` | Not mapped | Implemented in both scripts via HID path | Need BLE vendor command mapping |
| DPI XY | `04:85/05` | HID fallback + staged vendor path | Implemented in both scripts | BLE direct set still stack-dependent outside vendor staged path |
| DPI stages | `04:86/06` | `0B84` / `0B04` + op `0x26` | Implemented in both scripts | Mostly covered |
| Poll rate | `00:85/05` | No stable vendor mapping yet | Implemented in both scripts via HID path | Need BLE vendor mapping for reliable parity |
| Battery | `07:80` | Battery Service + observed vendor read key | Implemented in both scripts | Need unified source preference and charging semantics on BLE |
| Idle time | `07:83/03` | Not mapped | Implemented in both scripts via HID path | Need BLE vendor mapping |
| Low battery threshold | `07:81/01` | Not mapped | Implemented in both scripts via HID path | Need BLE vendor mapping |
| Scroll mode | `02:94/14` | Not mapped | Implemented in both scripts via HID path | Need BLE vendor mapping |
| Scroll acceleration | `02:96/16` | Not mapped | Implemented in both scripts via HID path | Need BLE vendor mapping |
| Scroll smart reel | `02:97/17` | Not mapped | Implemented in both scripts via HID path | Need BLE vendor mapping |
| Scroll LED brightness/effects | `0F:84/04`, `0F:02` | Not mapped | Implemented in both scripts via HID path | Need BLE vendor mapping for non-HID parity |
| Button remap | `0x02:0x8C/0x0C` validated for base function blocks | Vendor write path documented and implemented | BLE implemented, USB read/write validated for base categories | Need advanced action taxonomy validation (macro/media/analog) |
| RGB / matrix effects | OpenRazer-documented classes | Partial BLE raw lighting scalar only | Not implemented end-to-end in scripts | Need cross-transport effect model and commands |

---

## Device-Specific Notes

### Razer Basilisk V3 X HyperSpeed (0x00B9)

| Setting | Value |
|---------|-------|
| USB VID:PID | `1532:00B9` |
| Bluetooth VID:PID | `068e:00BA` |
| Transaction ID | `0x1F` |
| Max DPI | 18000 |
| DPI Stages | 5 |
| Poll Rates | 125, 500, 1000 Hz |

**Known Issues**:
- DPI button stops working when OpenRazer daemon is active ([#2701](https://github.com/openrazer/openrazer/issues/2701))
- Bluetooth configuration support is device/transport dependent

### Razer Basilisk V3 35K (0x00CB)

| Setting | Value |
|---------|-------|
| USB VID:PID | `1532:00CB` |
| Transaction ID | `0x1F` |
| Max DPI | 35000 |
| DPI Stages | 5 |
| Poll Rates | 125, 500, 1000 Hz |
| Validated matrix LEDs | `0x01` scroll wheel, `0x04` logo, `0x0A` underglow |
| Extra validated button slots | `0x0E` scroll mode (protocol-read-only), `0x0F` sensitivity clutch / DPI clutch (editable; default `06 01 05 01 90 01 90`), `0x34` wheel tilt left, `0x35` wheel tilt right, `0x60` DPI button, `0x6A` profile button (software-read-only / report-4 `0x50`) |

### Razer Basilisk V3 Pro (0x00AA / 0x00AB)

| Setting | Value |
|---------|-------|
| USB VID:PID | `1532:00AA`, `1532:00AB` |
| Transaction ID | `0x1F` |
| DPI Stages | 5 |
| Onboard Profiles | 3 |
| Validated matrix LEDs | `0x01` scroll wheel, `0x04` logo, `0x0A` underglow |
| Extra validated button slots | `0x0F` sensitivity clutch / DPI clutch (editable; default `06 05 05 01 90 01 90`), `0x34` wheel tilt left, `0x35` wheel tilt right, `0x6A` profile button (default `12 01 01 00 00 00 00`, remap path observed but not yet reliable enough to ship) |
| Button-read layout note | `0x02:0x8C` extended slots decode from `response[11..<18]`, matching the 35K-style offset rather than the Basilisk V3 X shape |
| Discovery note | Observed on 2026-03-25: the directly cabled macOS USB path reports `1532:00AA`; OpenSnek aliases it to the same shipped V3 Pro USB profile as `1532:00AB` |

### Transaction ID by Device

| Device Type | Transaction ID |
|-------------|---------------|
| Modern wireless (2022+) | `0x1F` |
| Modern wired (2020+) | `0x3F` |
| Older devices | `0xFF` |

---

## Storage Modes

| Value | Name | Description |
|-------|------|-------------|
| `0x00` | NOSTORE | Apply immediately, don't persist |
| `0x01` | VARSTORE | Apply and save to device memory |

---


## References


- [OpenRazer Project](https://github.com/openrazer/openrazer)
- [OpenRazer Protocol Wiki](https://github.com/openrazer/openrazer/wiki/Reverse-Engineering-USB-Protocol)
- [OpenRazer Issue #2031 - Button Remapping](https://github.com/openrazer/openrazer/issues/2031)
- [OpenRazer Issue #2701 - Basilisk V3 X HyperSpeed](https://github.com/openrazer/openrazer/issues/2701)
- [razer-macos Project](https://github.com/1kc/razer-macos) (macOS IOKit reference)

---
