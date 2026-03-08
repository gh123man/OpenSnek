# Capture Corpus

This directory stores BLE protocol captures used to derive and validate `razer_ble.py` behavior.

## Layout

- `ble/filteredcap.pcapng`
  - First broad Synapse BLE capture.
  - Established vendor write/notify framing:
    - write handle `0x003d` (`...1524`)
    - notify handle `0x003f` (`...1525`)
    - request-id echo and status-byte ACK model.
  - Source for generic read/write framing and key-byte model (`byte4..7`).

- `ble/power-lighting.pcapng`
  - Focused capture for scalar settings.
  - Confirms raw power/sleep/lighting key pairs and payload sizes:
    - power timeout: `05 84` / `05 04` (u16)
    - sleep timeout: `05 82` / `05 02` (u8)
    - lighting value: `10 85` / `10 05` (u8)
    - lighting frame stream: `10 04` with 8-byte payload `04 00 00 00 [M][R][G][B]`
  - Confirms two-stage scalar read response pattern:
    - notify header (length/status), then
    - payload notify carrying scalar bytes.

- `ble/all-lighting-modes.pcapng`
  - Full Synapse lighting-mode walkthrough (effects + color changes).
  - Confirms:
    - dominant frame stream key `10 04` with `04 00 00 00 [M][R][G][B]`
    - mode selector write key `10 03` with payload `08 00 00 00`
  - Used to add BT frame-color and mode-raw APIs in `razer_ble.py`.

- `ble/all-key-binding-functions.pcapng`
  - Attempted full single-button binding walkthrough in Synapse.
  - Observed repeated writes for slots `0x05` and `0x04` only:
    - header: `08 04 01 <slot>`, len `0x0a`
    - payload: `01 <slot> 01 00 0000 0000 0000`
  - This adds capture-backed evidence for layer-specific clear/default entries (`layer=0x01`, `action=0x00`).
  - No distinct turbo/media/macro payload variants were present in this trace.

- `ble/basic-rebind.pcapng`
  - Button remap workflow across multiple slots.
  - Confirms two-step write flow:
    - header select `op=0x0a`, key `08 04 01 <slot>`
    - 10-byte action payload write.

- `ble/right-click-bind.pcapng`
  - Focused slot `0x02` (right-click) transitions.
  - Confirms payloads for left-click remap, keyboard remap, and explicit right-click restore.

- `ble/vendor-key-sweeps-2026-03-08.md`
  - In-session automated BLE vendor key sweep report.
  - Documents confirmed mappings, candidate keys, and safety findings from read/writeback probing.

## Notes

- Captures are intentionally action-scoped for faster diffing.
- Keep new captures in `captures/ble/` and add an entry here with what changed and what was validated.


## Capture guide

install btvs
run btvs (will open wireshark)
paste in filter `btatt && btatt.handle != 0x002b && btatt.handle != 0x001b` to filter out all HID traffic
open synapse 
perform actions
file -> exprot specified packets
