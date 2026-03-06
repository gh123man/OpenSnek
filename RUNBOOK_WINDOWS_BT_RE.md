# Windows Bluetooth Reverse Engineering Runbook (Razer Basilisk V3 X HS)

## Objective
Recover the Bluetooth write protocol used by Razer Synapse so we can implement configuration writes outside Synapse.

Current known facts from macOS work:
- Device over BT HID reports:
  - Heartbeat/status: `05 05 10 00 00 00 00 00 00`
  - DPI state report: `05 05 02 XX YY XX YY 00 00` (big-endian), observed DPI values: `400/800/1600/3200/6400`
- We can read DPI passively from BT HID reports.
- We cannot currently write settings over BT on macOS using HID feature/output reports.
- Therefore, Synapse likely uses a separate BLE GATT control channel (or a transport not exposed in current macOS path).

## Success Criteria
You must produce:
1. Characteristic UUID(s) Synapse writes to for BT config.
2. Hex payloads for at least one setting change (DPI preferred).
3. Any response/notify payload correlated to that write.
4. Minimal replay recipe that can be tested outside Synapse.

## Recommended Strategy (in order)
1. API-layer capture on Windows (best first step).
2. Optional OTA BLE sniffing (only if API capture is insufficient).
3. Diff one-change experiments.
4. Replay validation.

## Environment Setup
On Windows machine:
- Pair mouse in Bluetooth mode and confirm Synapse can modify settings.
- Disable all unrelated BT devices if possible (reduce noise).
- Keep one mouse profile active and stable.

Suggested tools:
- Frida (preferred) for runtime API hooks.
- API Monitor (fallback).
- Wireshark + Npcap (optional OTA/supporting evidence).
- nRF Sniffer/Ubertooth only if needed.

## Experiment Design
Run only one change per capture:
- Baseline: open Synapse, no setting changes for 30s.
- Test A: DPI `800 -> 1600`.
- Test B: Poll rate change.
- Test C: DPI stage active index change.

Record for each run:
- Timestamp start/end.
- Exact setting changed.
- Before/after value.

## Capture Method A: API-layer (preferred)
Goal: log plain payloads before BLE encryption.

Target APIs to hook/observe:
- `GattCharacteristic.WriteValueAsync`
- `GattCharacteristic.WriteClientCharacteristicConfigurationDescriptorAsync`
- `GattCharacteristic.ValueChanged` callbacks (notifications)

Also capture:
- Characteristic UUID
- Service UUID
- Write type (`with response` vs `without response`)
- Payload hex
- Timestamp

### Frida Outline
Attach to Synapse processes and log:
- function entry args
- resolved UUID objects
- byte buffers passed to write calls

Do not overfit to one binary name; Synapse may split into multiple helper processes.

## Capture Method B: OTA BLE (optional)
Use only if API-level capture fails.

Notes:
- BLE traffic may be encrypted after pairing.
- If encrypted, OTA alone may not expose payload bytes.
- OTA still useful for packet timing and handle correlation.

## Artifact Export Requirements
Export structured files (JSON/CSV preferred):
- `baseline.json`
- `dpi_800_to_1600.json`
- `poll_1000_to_500.json` (or equivalent)

Each record should include:
- `time`
- `op` (`write`, `notify`, `indicate`)
- `service_uuid`
- `char_uuid`
- `handle` (if available)
- `write_mode`
- `value_hex`

## Diff Procedure
1. Compare baseline vs one-change capture.
2. Identify new/changed write payload(s).
3. Correlate subsequent notify payload(s).
4. Confirm payload fields that vary with the changed setting.

Heuristics:
- For DPI change, expect two-byte big-endian values (e.g. `0x0320`=800, `0x0640`=1600) somewhere in payload.
- Look for framing bytes/opcodes that remain constant while value bytes change.

## Replay Procedure
Replay candidate write outside Synapse:
- Same device mode (Bluetooth).
- Same characteristic UUID.
- Same write mode (response/no-response).

Use repo helper script (on environment where GATT is reachable):
- `ble_write_runner.py`

Example:
```bash
python ble_write_runner.py \
  --target "<device-id>" \
  --write-char "<char-uuid>" \
  --payload "<hex>" \
  --response
```

If notify char is known:
```bash
python ble_write_runner.py \
  --target "<device-id>" \
  --notify-char "<notify-uuid>" \
  --notify-seconds 5 \
  --write-char "<char-uuid>" \
  --payload "<hex>"
```

## Validation Checklist
After replay:
- DPI changed physically/observably.
- Passive DPI report reflects expected value.
- No device disconnects/crashes.
- Repeatable across at least 3 attempts.

## Deliverables for macOS Agent Session
Provide:
1. `service_uuid`, `write_char_uuid`, `notify_char_uuid` (if any)
2. A table of known commands:
   - operation
   - payload template
   - variable bytes
   - checksum rules (if discovered)
3. One confirmed working payload for DPI write.
4. Optional raw logs/CSV for independent verification.

## Safety / Guardrails
- Avoid fuzzing random writes on production profile.
- Make one controlled change at a time.
- Keep a recovery path: Synapse restore/default profile.

## Fast Start for Next AI Agent (copy/paste prompt)
Use this exact brief in the Windows AI session:

```
You are reverse engineering Razer Synapse Bluetooth writes for Basilisk V3 X HS.
Goal: identify BLE GATT characteristic UUID(s) and payload format for at least DPI write.

Known from macOS:
- Passive BT HID DPI report exists: 05 05 02 XX YY XX YY 00 00
- Heartbeat: 05 05 10 00 00 00 00 00 00
- macOS cannot write settings via HID reports.

Tasks:
1) Instrument Synapse API calls (GattCharacteristic.WriteValueAsync and notify handlers).
2) Capture baseline + one-change traces (DPI 800->1600).
3) Export logs as structured JSON/CSV with UUIDs + payload hex + timestamp + write mode.
4) Produce candidate write payload(s) and response payload(s).
5) Validate by replaying once outside Synapse if possible.
```

