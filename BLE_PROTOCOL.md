# Razer BLE Vendor GATT Protocol Documentation

This document describes the BLE protocol and vendor GATT behavior for Razer mice, based on captures and live validation.

## BLE (Bluetooth Low Energy) Protocol

The standard 90-byte USB HID Feature Report protocol does **NOT** work over BLE. Testing with the Basilisk V3 X HyperSpeed (BT PID `0x00BA`) on macOS revealed a completely different transport.

### BLE HID Report Descriptor

The BLE HID descriptor contains **only Input reports** — zero Feature or Output reports. This means the USB feature report protocol cannot be used over BLE.

### GATT Services Discovered

Three services are present on the Basilisk V3 X HyperSpeed over BLE:

| Service | UUID | Purpose |
|---------|------|---------|
| Battery Service | `0x180F` | Standard battery level (0-100%) |
| HID Service | `0x1812` | Mouse input reports (movement, buttons, DPI status) |
| Vendor Service | `52401523-F97C-7F90-0E7F-6C6F4E36DB1C` | Razer vendor-specific (lighting, config?) |

### Battery Service (0x180F) — Working

The standard BLE Battery Service provides battery level readings:

```
Service:        0x180F (Battery Service)
Characteristic: 0x2A19 (Battery Level)
  Properties:   Read, Notify
  Value:        uint8 (0-100 percentage)
```

This is the most reliable way to read battery on BLE-connected Razer devices. It does not require the 90-byte Razer protocol and works directly via GATT.

**Limitation**: No charging status is available — only the level percentage.

### Passive HID Input Reports — Working (Read-Only)

DPI status can be read passively from HID input reports:

```
Report ID: 0x05
Format:    05 05 02 XX XX YY YY 00 00
  Byte 0:    Report ID (0x05)
  Byte 1:    Length/type (0x05)
  Byte 2:    Subtype (0x02 = DPI status)
  Bytes 3-4: DPI X (big-endian)
  Bytes 5-6: DPI Y (big-endian)
  Bytes 7-8: Reserved (0x00)
```

These reports are emitted when DPI changes (e.g., DPI button press). They can be read via `hidapi` on the BLE HID device path.

### Vendor GATT Service

```
Service:        52401523-F97C-7F90-0E7F-6C6F4E36DB1C
Characteristics:
  Write:        52401524-F97C-7F90-0E7F-6C6F4E36DB1C (write-with-response only)
    GATT handle: 0x3D (61 decimal)
  Notify 1:     52401525-F97C-7F90-0E7F-6C6F4E36DB1C (read, notify)
    GATT handle: 0x3F (63 decimal)
    CCCD handle: 0x40 (64 decimal)
  Notify 2:     52401526-F97C-7F90-0E7F-6C6F4E36DB1C (read, notify)
```

**Note**: Only 3 GATT services are exposed via CoreBluetooth: 180A (Device Info),
180F (Battery), and the vendor service. The HID service (0x1812) is **claimed by
macOS** and NOT accessible via GATT — it's handled entirely by the OS HID stack.

This same vendor service UUID appears on both Razer keyboards (e.g., BlackWidow V3 Mini)
and mice (e.g., Basilisk V3 X HyperSpeed, Basilisk X HyperSpeed). The only known
third-party implementation is [JiqiSun/RazerBlackWidowV3MiniBluetoothControllerApp](https://github.com/JiqiSun/RazerBlackWidowV3MiniBluetoothControllerApp) (Swift/macOS, lighting only).

#### Synapse Connection Handshake (from Windows BLE GATT capture)

When Synapse connects, it follows this sequence:

1. **Subscribe to notifications**: Write 0x0100 to CCCD at handle 0x40 (enables notifications on 0x3F)
2. **Get Serial**: First command after subscribe — reads device serial number
3. **Config queries**: DPI, poll rate, battery, etc. — all via the same handle pair

Total traffic observed: 217 write requests (→ 0x3D), 242 notifications (← 0x3F).
The ~1.11:1 ratio suggests most commands get exactly one response; a few commands
(like staged DPI queries) generate multiple notification events.

**All writes are ATT Write Requests (0x12)** — no Write Commands (0x52). Every
write expects and waits for a response. There is no fragmentation across multiple
ATT PDUs observed in the capture.

#### Command Protocol

> **Updated 2026-03-07** based on Windows BLE GATT capture of Synapse traffic.
> The two-write pair format below was discovered through earlier macOS testing and applies
> specifically to lighting control. Synapse's actual config path (DPI, serial, poll rate)
> uses a different single-write framing — see "Synapse Write Format" below.

Commands use a **two-write pair**: an 8-byte init followed by a 10-byte payload.
Both writes go to the write characteristic (`...1524`) using write-with-response.
The writes must be sent on separate GATT write operations (not batched), with at
least ~50ms between them (the ATT write response from the first must complete
before the second is sent).

**Important**: Do NOT use write-without-response for the init — it will be silently
dropped and the payload will be treated as a standalone (failing) command.

**Init format (8 bytes)**:
```
13 0a 00 00 [mode_hi] [mode_lo] 00 00

Init bytes are STRICT:
  byte[0] = 0x13 (only value that works)
  byte[1] = 0x0a (only value that works; 20 other values tested, all fail)
  bytes[2-3] = 0x00 0x00 (padding)
  bytes[4-5] = mode selector (see below)
  bytes[6-7] = 0x00 0x00 (padding)

Working modes:
  10 03  — Lighting control (confirmed: changes scroll wheel LED)
  10 04  — DANGEROUS: freezes mouse input (still BLE-connected, no movement)
  10 05  — Unknown (accepts all payloads, no observable effect)
  10 06  — Unknown (accepts all payloads, no observable effect)

Failing modes (error 0x03):
  10 00, 10 01, 10 02, 10 07, 10 08, 10 09, 10 0a, 10 0b,
  10 0c, 10 0d, 10 0e, 10 0f

Parameter error (0x05):
  20 XX, 04 XX
```

**Response format (20 bytes, on notify1 / `...1525`)**:
```
[echo_byte0] 00 00 00 00 00 00 [status] [12-byte session token]

echo_byte0: First byte of the INIT command (0x13 for valid pairs)
Status values:
  0x02 = Success
  0x03 = Error (unknown command / bad format)
  0x05 = Parameter error

Session token: Changes on each BT reconnect.
  Example: 71 f8 b9 97 94 b6 eb 41 6a ff 9b 6b
```

**Unsolicited notification on subscribe**: `01 00 00 00 00 00 00 03 [token]`
(Always status 0x03/ERR — this is normal, not an error condition)

**Notify2 read value** (8 bytes): `aa ef 6d 16 2c 27 4f 48`
(Purpose unknown, possibly device identifier; constant across sessions)

#### Synapse Write Format (from BLE GATT capture — decoded frame layout)

The Windows BLE GATT capture shows Synapse writes to handle 0x3D (the vendor GATT
write characteristic) for ALL config operations including DPI, serial, battery, and
poll rate — **not just lighting**. This means the vendor GATT service is the primary
BLE configuration path, overturning the earlier "lighting-only" conclusion.

**Key confirmed facts (from `fitleredcap.pcapng`):**
- Synapse uses **ATT Write Request (0x12)** to handle `0x003D` for config traffic
- No Write Command (`0x52`) and no ATT-level fragmentation observed
- Dominant request payload is **8 bytes** (203/217 writes in this capture)
- Responses are ATT Handle Value Notifications (`0x1B`) on handle `0x003F`

**Primary request frame (8 bytes):**
```
Offset  Size  Field                    Notes
------  ----  ------------------------ ---------------------------------------
0       1     Request ID               Echoed by response header byte 0
1       1     Op/flags                 Usually 0x00/0x01, varies by command
2-3     2     Reserved                 Usually 0x0000
4-7     4     Command payload key      Command-specific selector/args
```

**Primary response header frame (20 bytes):**
```
Offset  Size  Field                    Notes
------  ----  ------------------------ ---------------------------------------
0       1     Request ID echo          Matches request byte 0
1       1     Data length              Number of response payload bytes
2-6     5     Reserved                 Observed 0x00
7       1     Status                   0x02=OK, 0x03=ERR, 0x05=param error
8-19    12    Session/aux bytes        Commonly stable per session; not sufficient
                                        alone for command payload decoding
```

**Data transfer behavior:**
- Header notification (`req_id` echo) carries status/length metadata
- Command payload is delivered in follow-up notification(s), even for short values
  (1-byte/2-byte responses observed live)
- If `data length > 12`, multiple follow-up notifications are used
- Serial reads use this multi-notification path and contain ASCII data (`632602H30204897`)

**Example request/response pairs:**
- `0100000001830000` -> header `0116...02...` then extra notifications with serial payload
- `0f0000000b840100` -> header `0f24...02...` then extra notifications carrying 0x24 bytes
- `??000000088401XX` -> status `0x03` (invalid parameter sweep in capture)

**Observed command-key signatures in this capture (bytes `4..7`):**

| Key (`bytes[4..7]`) | Observed header length | Status | Observed payload signature | Notes |
|---------------------|------------------------|--------|----------------------------|-------|
| `01 83 00 00` | `0x16` | `0x02` | ASCII serial in follow-up notifies | Includes `632602H30204897` |
| `0B 84 01 00` | `0x24` | `0x02` | Multi-part numeric block | Matches staged value pattern |
| `05 84 00 00` | `0x02` | `0x02` | `2C 01` in payload | 16-bit scalar value |
| `10 85 01 01` | `0x01` | `0x02` | `54` in payload | 8-bit scalar value |
| `08 84 01 XX` | `0x00` | `0x03` | none | Invalid parameter sweep (`XX` tested) |

#### Live Validation (macOS CoreBluetooth, 2026-03-08)

The following mappings were validated live against a connected Basilisk V3 X HS
(`BSK V3 X HS`, BLE PID `0x00BA`) using direct writes to `...1524` and notifications
from `...1525`.

| Operation | Request(s) | Result |
|----------|------------|--------|
| Get 1-byte threshold | `.. 05 82 00 00` | Returns 1-byte value (tested: `0x01`) |
| Set threshold | `.. 05 02 00 00` then write 1 byte | Writable and persistent in-session (`0x01 -> 0x0A -> 0x01`) |
| Get 1-byte setting B | `.. 10 85 01 01` | Returns 1-byte value (tested: `0x54`) |
| Set setting B | `.. 10 05 01 00` then write 1 byte | Writable/readback confirmed (`0x54 -> 0x53 -> 0x54`) |
| Get battery raw level | `.. 05 81 00 01` | Returns 1-byte raw level (tested: `0xF2`) |
| Get status flag | `.. 05 80 00 01` | Returns 1-byte flag (tested: `0x01`) |
| Get 2-byte scalar | `.. 05 84 00 00` | Returns `0x012C` on test device |
| Get staged block | `.. 0B 84 01 00` | Returns 36-byte multi-notification payload |
| Set DPI stages | `.. 0B 04 01 00` then 38-byte payload (20+18) | Writable/readback confirmed live |

Notes:
- `..` above is the per-request prefix `[request_id] [op] 00 00`
- For these live-tested commands, setter writes return a short ACK notification
  with status `0x02`; value is then verified via the corresponding getter
- Key `.. 05 80 00 01` remained `0x01` during threshold and `10/05` setting tests,
  so it is likely a different setting
- `05 81` battery correlation is strong: `0xF2` (242) maps to ~94.9%,
  matching standard Battery Service read `0x5E` (94%)
- Attempted `10 03` + 4-byte payload writes for the `05 84` scalar returned
  status `0x05` (parameter error) in this live session

#### DPI Stages over Vendor GATT (verified from existing pcap + live replay)

The DPI slot change seen in `fitleredcap.pcapng` is a confirmed writable flow.

Write sequence:
1. Send 8-byte command header: `[req] 26 00 00 0B 04 01 00`
2. Send first 20 bytes of stage payload
3. Send remaining 18 bytes of stage payload
4. Device ACK notification: `[req] 00 00 00 00 00 00 02 ...`

Read sequence:
1. Send 8-byte command header: `[req] 00 00 00 0B 84 01 00`
2. Receive header notify with length `0x24`
3. Receive two continuation notifications containing stage data

Observed set payload format (38 bytes, little-endian DPI values):
```
[active] [count]
[stage0_id] [dpi0_x_le16] [dpi0_y_le16] [00] [00]
[stage1_id] [dpi1_x_le16] [dpi1_y_le16] [00] [00]
[stage2_id] [dpi2_x_le16] [dpi2_y_le16] [00] [00]
[stage3_id] [dpi3_x_le16] [dpi3_y_le16] [00] [00]
[stage4_id] [dpi4_x_le16] [dpi4_y_le16] [00] [00]
[tail]
```

Captured/live-tested example payload:
```
02 05
00 30 11 30 11 00 00
01 2e 09 2e 09 00 00
02 76 16 76 16 00 00
03 9e 07 9e 07 00 00
04 fc 08 fc 08 00 03
00
```

Live mutation test (2026-03-08):
- Baseline stage0: `0x1130` (4400 DPI)
- Wrote stage0 -> `0x1162` (4450 DPI) using same `0B 04 01 00` path
- Readback via `0B 84 01 00` returned updated value (`... 62 11 62 11 ...`)
- Restored stage0 to `0x1130` and readback confirmed restoration

Extended slot validation (2026-03-08):
- All five DPI slots were independently modified and read back successfully
  (slot-by-slot +25 DPI test, then per-slot restore)
- Therefore, this path supports writing each stage, not only the active slot

Single-stage mode (preliminary):
- During live probing, `0B 84 01 00` temporarily switched from a 36-byte staged
  response to an 8-byte response containing only one stage-like entry
  (`01 01 01 30 11 30 11 00`), consistent with a "single fixed DPI" mode
- Original 5-stage configuration was restored and verified by readback
- Exact minimal payload for intentionally enabling/disabling single-stage mode
  still needs one clean capture sequence to document definitively

**Still not fully mapped:**
- Exact semantic mapping of `bytes[4..7]` to USB class/ID for every command
- Full reconstruction format for continuation notifications in long replies
- Meaning of short auxiliary writes (`0d`, `54`, `02`, `0300`, `08000000`) seen between main commands

**Why earlier DPI testing failed:** The 8+10 byte two-write pair format (mode `10 03`)
appears to be lighting-specific. Synapse's config commands likely use a different
format or mode that wasn't discovered during manual probing.

#### Session State and Recovery

The vendor GATT service can enter a **permanent error state** where all commands
return ERR (status 0x03), including previously working lighting commands. This
appears to happen after sending many commands (especially failed ones) in rapid
succession during probing.

**Recovery**: Toggle Bluetooth off and back on on the mouse (physical switch).
A software disconnect/reconnect via CoreBluetooth is NOT sufficient — the device
must be power-cycled. After reconnecting, the session token changes and the GATT
service accepts commands again.

This matches the BlackWidow V3 Mini BLE app's setup instructions: "Toggle the
keyboard's Bluetooth off, then back on."

#### Payload Validation Behavior

In working modes (10/03, 10/05, 10/06), the device accepts **any** 10-byte payload
without error. It does NOT validate payload content — only the mode is checked.
Payloads that don't match a known command format are silently ignored.

This means OK responses do NOT indicate the command had any effect — only that the
mode was valid.

Mode 10/04 is more selective (rejects byte0=0x00) but still accepts most payloads.
**WARNING**: Mode 10/04 can freeze mouse input.

#### Lighting Payload (mode 10 03) — Confirmed Working

```
Payload (10 bytes): [effect] [param1] [param2] [color_count] [R] [G] [B] [R2] [G2] [B2]

Effects:
  0x01 = Static      e.g., 01 00 00 01 ff ff ff 00 00 00 (white)
  0x02 = Breathe     e.g., 02 00 00 01 00 ff 00 00 00 00
  0x03 = Spectrum     e.g., 03 00 00 00 00 00 00 00 00 00
  0x04 = Wave        e.g., 04 02 28 00 00 00 00 00 00 00
  0x05 = Reactive    e.g., 05 00 03 01 00 ff 00 00 00 00

LED off: 01 00 00 01 00 00 00 00 00 00 (static black)
```

**Confirmed on Basilisk V3 X HyperSpeed**: Static and spectrum effects change the
scroll wheel LED. Sending static black turns LED off. The LED brightness may
decrease after sending many commands in sequence.

#### DPI Write Testing — Exhaustive Results (macOS, two-write format)

Earlier testing using the 8+10 byte two-write pair format confirmed that DPI cannot
be changed using that specific protocol variant. The following approaches were all
tried with HID DPI sniffing active (monitoring report 0x05 0x05 0x02):

| Approach | Modes Tested | Payloads | DPI Changes |
|----------|-------------|----------|-------------|
| byte0=0x08 + DPI X/Y big-endian | 10/03, 04, 05, 06 | 400-3200 DPI | 0 |
| byte0=0x00-0x05 + DPI data | 10/03, 04, 05 | 800 DPI | 0 |
| USB class+id (0x04 0x05) as payload | 10/03, 05, 06 | 800 DPI | 0 |
| USB GET DPI (0x04 0x85) as payload | 10/03, 05, 06 | read | 0 |
| DPI/100 single byte | 10/03, 05, 06 | 4,8,16,32 | 0 |
| DPI at various byte positions | 10/06 | 800 DPI | 0 |
| Full 90-byte USB report | (direct) | various | 0 |
| Chunked USB report (20, 10 bytes) | (direct) | various | 0 |
| Raw DPI bytes (2-8 bytes) | (direct) | various | 0 |
| HID output reports via hidapi | all report IDs | 800 DPI | all return -1 |
| HID feature reports via hidapi | all report IDs | GET DPI | all return -1 |

**Updated conclusion** (2026-03-07): These failures were due to using the wrong write
format, not a wrong GATT service. A Windows BLE capture confirms Synapse successfully
reads DPI (and likely writes it) via the same vendor GATT service using a different
single-write format. The 8+10 two-write pair with the `13 0a` init appears to be
lighting-specific. See "Synapse Write Format" above for the correct approach.

#### HID Report Limitations on BLE

The BLE HID descriptor contains **only Input reports**:
- No Feature reports (cannot send/receive USB-style configuration)
- No Output reports (cannot send commands via HID)
- All HID output/feature report writes via hidapi return -1
- All HID feature report reads via hidapi raise OSError

### macOS BLE Discovery

macOS hides paired BLE HID devices from normal BLE scans (`CBCentralManager.scanForPeripherals`). To find them, use:

```objc
// Objective-C / CoreBluetooth
[centralManager retrieveConnectedPeripheralsWithServices:@[batteryServiceUUID]];
```

```python
# Python via pyobjc
battery_uuid = CBUUID.UUIDWithString_("180F")
peripherals = manager.retrieveConnectedPeripheralsWithServices_([battery_uuid])
```

### Current BLE Capabilities

| Feature | Status | Notes |
|---------|--------|-------|
| Battery read | Working | Via BLE Battery Service (0x180F) |
| DPI read | Working | Passive HID input reports (report 0x05) |
| LED/Lighting | Working | Vendor GATT service, mode `10 03`, two-write format |
| Vendor GATT frame layout | Working | Single-write request + notify header/continuation is now decoded |
| DPI write | Partial | Transport/frame known, command mapping still incomplete |
| Poll rate | Partial | Transport/frame known, command mapping still incomplete |
| Button remapping | Unknown | Likely same transport; command IDs/args not yet mapped |

---

## Windows BLE Driver Architecture

Analysis of the Razer driver stack on Windows 11 reveals how Synapse communicates
with the mouse over BLE. This is critical for understanding the config write path.

### GATT Services (from Windows device enumeration)

| Service | UUID | GATT Handle | Windows Driver |
|---------|------|-------------|----------------|
| Generic Access | `0x1800` | 1 | UmPass |
| Generic Attribute | `0x1801` | 10 | UmPass |
| Device Information | `0x180A` | 14 | UmPass |
| Battery Service | `0x180F` | 19 | UmPass |
| **HID Service** | **`0x1812`** | **23** | **mshidumdf** (+ Razer filter) |
| Vendor Service | `52401523...` | 59 | UmPass |

The HID service (handle 23) is the only one with a specialized driver stack.
All other services use the generic `UmPass` (User-Mode Pass-through) driver.

### Driver Stack

```
┌──────────────────────────────────────────────────────┐
│  Razer Synapse (usermode)                            │
│  Communicates via IOCTLs to RZCONTROL device         │
├──────────────────────────────────────────────────────┤
│  RzCommon.sys                                        │
│  Manages RZCONTROL virtual bus device                │
│  Custom class GUID: {1750F915-5639-497C-...}         │
├──────────────────────────────────────────────────────┤
│  RzDev_00ba.sys  (UPPER filter on Col01 mouse)       │
│  Creates RZCONTROL child device                      │
│  Sets: ControlDevice=1, DeviceType=1                 │
├──────────────────────────────────────────────────────┤
│  HID Collection 01 (Mouse)                           │
│  + Col02 (Pointer), Col03-05, Col06 (Keyboard)       │
├──────────────────────────────────────────────────────┤
│  mshidumdf  (Microsoft HID minidriver for UMDF)      │
├──────────────────────────────────────────────────────┤
│  RzDev_00ba.sys  (LOWER filter on BLE HID parent)    │
│  Flags: DkmKeyDevice, DkmMouseDevice, MouseExDevice  │
├──────────────────────────────────────────────────────┤
│  WudfRd + HidOverGatt  (Microsoft BLE-to-HID)        │
│  Translates HID reports to/from GATT characteristics  │
├──────────────────────────────────────────────────────┤
│  BthLEEnum  (Windows BLE enumerator)                 │
│  GATT transport layer                                │
└──────────────────────────────────────────────────────┘
```

### Key Observations

1. **`RzDev_00ba.sys` sits at TWO levels**: lower filter on the BLE HID parent device
   AND upper filter on HID Collection 01 (mouse) and Collection 06 (keyboard).

2. **RZCONTROL virtual bus**: The upper filter creates a child device on the RZCONTROL
   bus (`RZCONTROL\VID_068E&PID_00BA&MI_00`). Synapse communicates through this device
   via IOCTLs, which flow down through `RzDev_00ba` to `HidOverGatt` to GATT writes.

3. **HidOverGatt**: Microsoft's WUDF driver that translates HID Feature/Output reports
   into GATT write operations on the HID service's Report characteristics. This is how
   Razer's 90-byte protocol reaches the mouse over BLE.

4. **Six HID Collections** (from the BLE HID Report Map):
   - Col01: Mouse (Generic Desktop / Mouse)
   - Col02: Pointer (Generic Desktop / Pointer)
   - Col03: Consumer Control
   - Col04: System Control
   - Col05: Vendor (Generic Desktop / Undefined) — Report ID 4
   - Col06: Keyboard (Generic Desktop / Keyboard)

5. **The INF files** (`razer_bt_dump/oem64.inf`, `oem66.inf`) contain the full
   driver configuration. `oem64.inf` installs the lower filter with `MouseEx_ReportId=1`.

### BLE HID Report Descriptor (254 bytes)

Extracted via IOKit on macOS. Six report IDs, **all Input-only**:

| Report ID | Collection | Size | Type |
|-----------|-----------|------|------|
| 1 | Mouse (buttons + X/Y/wheel) | 9 bytes | Input |
| 2 | Consumer Control | 7 bytes | Input |
| 3 | System Control | 8 bytes | Input |
| 4 | Vendor (Generic Desktop, Usage 0x00) | 8 bytes | Input |
| 5 | Vendor (Generic Desktop, Usage 0x00) | 8 bytes | Input |
| 6 | Keyboard | 7 bytes | Input |

**Critical**: The descriptor declares `MaxFeatureReportSize=1` and `MaxOutputReportSize=1`.
There are **zero Feature Reports and zero Output Reports** in the BLE HID descriptor.

This means the HID Report Map visible to the OS does NOT include Razer's 90-byte
protocol. On Windows, `HidOverGatt` + `RzDev_00ba` likely inject or intercept
reports at the driver level, writing directly to GATT characteristics that have
Feature-type Report Reference descriptors — even though the Report Map doesn't
advertise them.

### What This Means

The 90-byte Razer protocol almost certainly travels over BLE through **GATT
characteristics within the HID service (0x1812)** that have Feature-type Report
Reference descriptors. These characteristics exist at the GATT level but are NOT
described in the HID Report Map. The Razer Windows driver (`RzDev_00ba.sys`) knows
about them because it's purpose-built for this device — it doesn't rely on the
Report Map to discover writable characteristics.

---

## What We Need To Uncover Next

### 1. Map 8-byte command keys to concrete settings

**This is the critical next step.** The frame transport is now known; the remaining gap
is command semantics. We need a deterministic map from request bytes `4..7` to
operations (Get DPI, Set DPI, Get Poll Rate, Set Poll Rate, etc.).

**Approach**:
- Use `fitleredcap.pcapng` plus controlled Synapse actions (change one setting at a time)
- Correlate changed write keys with changed response payloads
- Build a command matrix (`key -> setting -> argument format`)

**Expected outcome**:
- Stable map for high-value commands (DPI, poll rate, battery threshold, idle timeout)
- Known error set (`0x03`/`0x05`) for invalid command/parameter combinations

### 2. Implement BLE Config Writes (Windows/Linux)

Now that frame layout is known:
1. Implement a `send_ble_command()` function using bleak (cross-platform)
2. Parse the 20-byte notify header (request echo, length, status)
3. Reassemble multi-notification payloads for `length > 12`
4. Validate with known responses (serial ASCII, staged DPI block)

### 3. macOS Path (If Possible)

On macOS, the vendor GATT service IS accessible via CoreBluetooth (unlike the HID
service). With the frame layout decoded, DPI/config writes should be possible once the
command-key mapping is completed.

The earlier failure is now explained: the 8+10 two-write format is lighting-specific.

### 4. Enumerate HID Service GATT Characteristics (Linux — Lower Priority)

The HID service (0x1812) investigation is now lower priority since the capture
confirms the vendor GATT service is the actual config path. Still useful to:
- Understand what HidOverGatt maps to GATT characteristics
- Confirm whether the HID service path is used at all by Synapse

**Tool**: `enumerate_hid_gatt_linux.py` on a Steam Deck or Linux machine with BlueZ.

---

## References

- [OpenRazer Project](https://github.com/openrazer/openrazer)
- [OpenRazer Protocol Wiki](https://github.com/openrazer/openrazer/wiki/Reverse-Engineering-USB-Protocol)
- [OpenRazer Issue #2031 - Button Remapping](https://github.com/openrazer/openrazer/issues/2031)
- [OpenRazer Issue #2701 - Basilisk V3 X HyperSpeed](https://github.com/openrazer/openrazer/issues/2701)
- [razer-macos Project](https://github.com/1kc/razer-macos) (macOS IOKit reference)

---

## Changelog

- **2026-03-08**: Decoded Synapse vendor GATT frame structure from `fitleredcap.pcapng`:
  - Identified dominant 8-byte request frame format (203/217 writes) with echoed request ID
  - Documented 20-byte response header format on notify handle 0x3F:
    request echo, data length, status (`0x02`/`0x03`/`0x05`), payload bytes
  - Confirmed long responses use additional notifications when `length > 12`
  - Live CoreBluetooth validation on connected BSK V3 X HS:
    confirmed writable `05 82` threshold path and writable `10 85/10 05` 1-byte setting path
  - Additional live mapping: `05 81` raw battery (`0xF2` ~= 94.9%) matches Battery Service 94%
  - `05 80` identified as a companion 1-byte status flag (observed `0x01`)
  - `05 84` stable 16-bit scalar (`0x012C`); tested `10 03` writes returned status `0x05`
  - Confirmed DPI stage write path from existing pcap:
    `0B 04 01 00` + 38-byte payload (20+18) successfully updates slot DPI
  - Verified live by changing stage0 4400->4450 and reading back via `0B 84 01 00`,
    then restoring to 4400
  - Added concrete request/response examples (serial and staged response cases)
  - Updated BLE capability table: frame transport now known; command mapping still partial
  - Replaced "decode write format" next-step item with command-key mapping work
- **2026-03-07**: Analysis of Windows BLE GATT capture (`fitleredcap.pcapng`):
  - Confirmed GATT handle numbers: 0x3D (write/0x1524), 0x3F (notify/0x1525), 0x40 (CCCD)
  - Revised "lighting-only" conclusion — vendor GATT IS used for all BLE config (DPI, serial, etc.)
  - Confirmed all writes are single ATT Write Requests (0x12), no fragmentation via Write Commands
  - TxnID implicit over BLE (GATT request-response ordering), not sent in payload
  - DPI format confirmed identical to USB: big-endian uint16 (example: 0x079E = 1950 DPI)
  - Serial number format confirmed: 22 ASCII bytes, example `632602H30204897`
  - Documented Synapse handshake sequence: CCCD subscribe → Get Serial → config queries
  - Stats: 217 write requests, 242 notifications (~1.11:1 ratio), all to/from vendor GATT handles
  - Payload size ~16-20 bytes (not 90 bytes) — exact format not yet decoded
- **2026-03-06**: Added Windows BLE driver architecture:
  - Documented full driver stack (RzDev_00ba.sys filter driver, RZCONTROL virtual bus, HidOverGatt)
  - Mapped all 6 GATT services with handles from Windows device enumeration
  - Analyzed BLE HID Report Descriptor (254 bytes, 6 report IDs, all Input-only)
  - Identified that Razer protocol uses GATT Feature Report characteristics not advertised in Report Map
  - Added concrete "What We Need To Uncover Next" section with actionable steps
- **2026-03-06**: Comprehensive BLE vendor GATT protocol documentation:
  - Confirmed 4 working modes (10/03 lighting, 10/04 dangerous, 10/05 unknown, 10/06 unknown)
  - Documented session state/recovery behavior (BT power cycle required)
  - Exhaustive DPI write testing across all modes and payload formats — DPI is NOT configurable via vendor GATT
  - Documented HID report limitations (no Feature/Output reports over BLE)
  - Added init byte strictness (only 0x13/0x0a works), payload validation behavior
  - Updated capabilities table with definitive status
- **2026-03-06**: Added BLE protocol section (Battery Service, vendor GATT service, passive HID reports)
- **2024-03-05**: Initial documentation based on OpenRazer and testing with Basilisk V3 X HyperSpeed
