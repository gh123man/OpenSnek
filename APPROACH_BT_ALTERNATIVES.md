# Alternative approaches: BT config write protocol

API-layer capture (Frida + API Monitor on Razer Synapse / RazerAppEngine) **did not work** – we only saw mouse input, not settings writes. This doc outlines other ways to recover the BLE write protocol.

---

## 1. OTA BLE sniffing (over-the-air)

Capture BLE packets between the PC and the mouse when Synapse changes a setting. You see the actual GATT write/notify on the radio.

**Pros:** No dependency on Synapse process; works regardless of which process does the write.  
**Cons:** Link may be encrypted after pairing (LE Secure Connections); if so, payload bytes are opaque without the key. Still gives timing, handle/opcode, and packet length.

### Option A: nRF Sniffer (Nordic)

- **Hardware:** nRF52840 Dongle (or similar Nordic DK with sniffer firmware), ~$10–20.
- **Software:** [nRF Sniffer for Bluetooth LE](https://www.nordicsemi.com/Products/Development-tools/nRF-Sniffer-for-Bluetooth-LE) – Wireshark plugin + firmware.
- **Flow:** Flash dongle with sniffer firmware, capture in Wireshark, change DPI in Synapse, filter for ATT (GATT) write/notify. Look for write requests to a characteristic and the payload (if unencrypted).
- **Encryption:** If connection uses LE Secure Connections, ATT payload is encrypted; you’d need to correlate by handle/length or try to obtain the key (out of scope for typical RE).

### Option B: Wireshark + Windows (Npcap / USBPcap)

- **Walkthrough:** See **[WIRESHARK_BLE_WALKTHROUGH.md](WIRESHARK_BLE_WALKTHROUGH.md)** for step-by-step instructions.
- **Setup:** Npcap + Wireshark; optionally USBPcap to capture the Bluetooth adapter's USB (HCI) traffic.
- **Limitation:** Windows often doesn’t expose raw BLE/ATT to usermode capture; you may only see HCI or nothing. Worth trying to see what interfaces appear.
- **Flow:** Start capture → change DPI in Synapse → stop; filter for `btatt` or `bthci_*`.

### Option C: Ubertooth One

- **Hardware:** Ubertooth One (~$120) – generic 2.4 GHz sniffer.
- **Software:** [Ubertooth host tools](https://github.com/greatscottgadgets/ubertooth), Wireshark integration.
- **Use case:** If nRF Sniffer isn’t available or you want a second setup; similar workflow (sniff, change setting, find ATT writes).

---

## 2. Lower-level / driver capture (Windows)

Synapse may talk to the mouse via a path that doesn’t show up in the app process (e.g. system BLE service, driver, or another process).

### Option A: Hook or trace the BLE service / driver

- **Targets:** e.g. `BthLEEnum.sys`, Windows BLE stack, or the process that hosts the GATT client (could be a system service, not RazerAppEngine).
- **Tools:** ETW (Event Tracing for Windows) for Bluetooth/BTH stack if providers exist; or kernel-mode debugging / driver hook (advanced, requires driver dev experience).
- **Practical first step:** Check whether Windows has BTH/BLE ETW providers and if they log GATT operations; enable them and capture while changing DPI.

### Option B: Monitor all DeviceIoControl to BTH handles

- **Idea:** Use a system-wide hook or filter that logs **all** `DeviceIoControl` calls whose handle is a Bluetooth LE device (e.g. from `CreateFileW` on `\?\BTH...`). That would catch the writer regardless of process.
- **Tools:** API Monitor (or similar) with a **global** or **system-wide** hook, not just RazerAppEngine; or a small kernel/usermode filter driver. Not all tools support this; may need custom code.

---

## 3. USB protocol → BLE mapping (macOS or Linux)

We already have the **USB HID protocol** (see `PROTOCOL.md`): 90-byte reports, command classes, transaction IDs. Razer may reuse the same payload structure over BLE (e.g. same bytes in a GATT write).

### Option A: BLE GATT discovery + trial writes (macOS)

- **Tool:** `explore_ble.py` / `ble_write_runner.py` on a Mac with the mouse in **Bluetooth** mode.
- **Flow:**
  1. List GATT services/characteristics (`ble_write_runner.py --target <device> --list`).
  2. Note writable characteristics (and optionally notify).
  3. Build a 90-byte (or shorter) payload that matches the USB DPI set command (see PROTOCOL.md) and try writing it to each writable characteristic (with and without response).
  4. If the device accepts the same format over BLE, the mouse DPI should change; then we know the char and payload format without Windows capture.
- **Benefit:** No need to capture Synapse; direct trial on a platform where we control BLE.

### Option B: OpenRazer / Linux

- OpenRazer may support this mouse over USB; check if it has any BLE or “wireless” code path. If yes, that code might reveal GATT handles and payload layout.

---

## 4. Recommended order

1. **OTA BLE sniffing (nRF Sniffer)** – If you can get the hardware, this is the most direct way to see which GATT handle gets the write and what the payload looks like (if unencrypted).
2. **macOS BLE discovery + USB-style writes** – No extra hardware; use `ble_write_runner.py` and PROTOCOL.md to try USB-like commands on each writable characteristic.
3. **Windows driver/ETW** – If you have Windows RE experience, enable BTH ETW or system-wide DeviceIoControl monitoring to see which component performs the write.
4. **Ubertooth / other OTA** – If nRF isn’t an option, use another sniffer to at least get handle/length/timing.

---

## 5. Summary

| Approach              | Hardware / env     | Difficulty | Likely outcome                          |
|----------------------|--------------------|------------|------------------------------------------|
| nRF Sniffer + Wireshark | nRF dongle       | Medium     | ATT write handle + payload (if not encrypted) |
| ble_write_runner + USB payloads | Mac + mouse over BT | Low    | Either working DPI write or narrow list of chars to try |
| BTH ETW / system hook | Windows           | Medium–High | Process/driver that does the write      |
| Ubertooth            | Ubertooth One     | Medium     | Same as nRF, different hardware          |

Once we have a candidate characteristic and payload (from OTA or from a successful trial write), use `ble_write_runner.py` to confirm and document the replay recipe in `artifacts/DELIVERABLES_TEMPLATE.md`.
