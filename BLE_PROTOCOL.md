# Razer BLE Protocol Specification

## 1. Scope

- Transport: BLE vendor GATT protocol used by Razer Basilisk V3 X HyperSpeed (BT PID `0x00BA`)
- Vendor IDs seen over BLE HID enumeration: `VID=0x068E`, `PID=0x00BA`
- This document is normative for implemented features in `razer_ble.py`

## 2. GATT Endpoints

| Item | UUID | Handle (Windows capture) | Access |
|---|---|---:|---|
| Vendor Service | `52401523-F97C-7F90-0E7F-6C6F4E36DB1C` | `0x003B` service decl area | Service |
| Vendor Write Characteristic | `52401524-F97C-7F90-0E7F-6C6F4E36DB1C` | `0x003D` | Write Request (with response) |
| Vendor Notify Characteristic | `52401525-F97C-7F90-0E7F-6C6F4E36DB1C` | `0x003F` | Notify |
| CCCD for notify | `0x2902` | `0x0040` | Write `0x0100` to enable notify |

## 3. Session Rules

- Enable notifications on `0x003F` before sending commands.
- Writes are ATT Write Request (`0x12`) to the write characteristic.
- Requests are correlated by request id (`req`) in byte 0.
- A command is successful when a notify header is received with matching `req` and status `0x02`.

## 4. Frame Formats

### 4.1 Request Header (8 bytes)

```
byte0  req_id
byte1  op
byte2  0x00
byte3  0x00
byte4  key0
byte5  key1
byte6  key2
byte7  key3
```

### 4.2 Notify Header (20 bytes)

```
byte0   req_id echo
byte1   payload_length
byte2-6 reserved
byte7   status (0x02 success, 0x03 error, 0x05 param error)
byte8-19 session/aux bytes
```

### 4.3 Continuation Payload Notify (20 bytes)

- Follow-up notify frames carry response payload bytes.
- Multi-part responses are concatenated in arrival order.

## 5. Operations

### 5.1 Generic Read (scalar)

- Header: `[req, 0x00, 0x00, 0x00, key0, key1, key2, key3]`
- Response: notify header + continuation payload

### 5.2 Generic Write (scalar)

- Header: `[req, op, 0x00, 0x00, key0, key1, key2, key3]`
- Then payload write containing scalar bytes (u8/u16 LE)
- Success criterion: notify header with same `req`, status `0x02`

### 5.3 Button Binding Write

Two-write sequence:
1. Header select: `[req, 0x0A, 0x00, 0x00, 0x08, 0x04, 0x01, slot]`
2. 10-byte binding payload

### 5.4 DPI Stage Table Read/Write

- Get header: `[req, 0x00, 0x00, 0x00, 0x0B, 0x84, 0x01, 0x00]`
- Set header: `[req, 0x26, 0x00, 0x00, 0x0B, 0x04, 0x01, 0x00]`
- Set payload: 38 bytes sent as two writes (20 + 18)

## 6. Command Key Map (Implemented)

| Feature | Get header key (`byte4..7`) | Set header key (`byte4..7`) | Set `op` | Payload |
|---|---|---|---:|---|
| DPI stage table | `0B 84 01 00` | `0B 04 01 00` | `0x26` | 38 bytes |
| Power timeout (raw) | `05 84 00 00` | `05 04 00 00` | `0x02` | u16 LE |
| Sleep timeout/value (raw) | `05 82 00 00` | `05 02 00 00` | `0x01` | u8 |
| Lighting value (raw) | `10 85 01 01` | `10 05 01 00` | `0x01` | u8 |
| Button binding (slot) | n/a (write path) | `08 04 01 <slot>` | `0x0A` | 10 bytes |

Additional read keys observed:
- Battery raw: `05 81 00 01` (u8)
- Status flag: `05 80 00 01` (u8)
- Serial read key: `01 83 00 00` (ASCII payload)

## 7. Payload Specifications

### 7.1 DPI Stage Set Payload (38 bytes)

```
[active][count]
repeat 5x:
  [stage_id][dpi_x_le16][dpi_y_le16][0x00][marker]
[tail]
```

Observed conventions:
- `stage_id`: `0..4`
- `marker`: `0x00` for stages 0..3, `0x03` for stage 4
- `tail`: `0x00`

### 7.2 Button Binding Payload (10 bytes)

```
[profile=0x01][slot][layer=0x00][action_type][p0_le16][p1_le16][p2_le16]
```

Action families observed:
- `action_type=0x01` mouse-button action
- `action_type=0x02` keyboard simple action
- `action_type=0x0D` extended action

Observed mouse-button encodings (`action_type=0x01`):
- `p0=0x0101` left click
- `p0=0x0201` right click
- `p1=0x0000`, `p2=0x0000`

Observed keyboard simple encoding (`action_type=0x02`):
- `p0=0x0002`
- `p1=<hid_key_u16>`
- `p2=0x0000`

## 8. Slot and Feature Coverage

- DPI stages: 5 slots writable and readable.
- Button rebinding confirmed slots: `0x02`, `0x03`, `0x04`, `0x05`.
- Slot `0x02` right-click default restore is explicit mouse-button payload (`p0=0x0201`).

## 9. Error Codes

| Status | Meaning |
|---:|---|
| `0x02` | Success |
| `0x03` | Error |
| `0x05` | Parameter error / unsupported parameter |

## 10. Missing or Partial Areas

- Full semantic mapping of all command keys (`byte4..7`) outside implemented set.
- Full parsing spec for long continuation payload framing in every response type.
- Complete action catalog for button rebinding (`action_type`, `p0/p1/p2` matrix).
- Formal mapping from raw power/sleep/lighting scalars to Synapse UI enums/units.
