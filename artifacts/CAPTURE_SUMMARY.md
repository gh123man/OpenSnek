# Capture summary

## Outcome: API-layer capture not viable

- **Frida:** Only 2 of 11 RazerAppEngine processes accepted attachment; those 2 produced no BLE/DeviceIoControl traffic.
- **API Monitor:** Hooking Synapse/RazerAppEngine captured only mouse input (clicks, etc.), not settings writes to the device.

**Next:** See [APPROACH_BT_ALTERNATIVES.md](../APPROACH_BT_ALTERNATIVES.md) for OTA BLE sniffing, driver-level capture, and BLE discovery + trial writes.

---

## Frida run results (reference)

| Run | PIDs attached | Records |
|-----|----------------|---------|
| baseline | 17724, 13420 | 0 |
| dpi_800_to_1600 | 17724, 13420 | 0 |

- **9** RazerAppEngine processes **refused** Frida injection (or exited during inject). We only hooked 2 processes.
- The 2 we hooked produced **no** `[GATT WRITE]`, `[DeviceIoControl]`, or `[CreateFileW BLE]` events during the capture window.

**Conclusion:** The process that talks BLE to the mouse is almost certainly one of the 9 we couldn’t attach to. Frida can’t see that traffic.

---

## Next step: API Monitor (recommended)

API Monitor does **not** inject into the process; it hooks APIs from outside. So it can see BLE traffic from the process that does the actual DeviceIoControl/CreateFileW calls.

1. **Install** API Monitor (see [API_MONITOR_SYNAPSE.md](../API_MONITOR_SYNAPSE.md)). Run it **as Administrator**.
2. **Hook all** RazerAppEngine.exe processes (right‑click each → Hook Process).
3. Enable **DeviceIoControl** (and optionally CreateFileW) under Kernel32/Kernelbase.
4. Click **Start**, then in Synapse change **only** DPI (e.g. 800 → 1600) **once**.
5. Click **Stop**, then **File → Save Capture**.
6. In the log, filter for **DeviceIoControl** and find the process that shows a call when you changed DPI. Note **dwIoControlCode** and **lpInBuffer** (hex).
7. Export or copy those lines to a text file, then run:
   ```cmd
   python parse_capture_log.py path\to\saved_log.txt -o artifacts\dpi_800_to_1600_apimon.json --run dpi_800_to_1600
   ```
   (If the log format doesn’t match, paste a few sample lines and we can adjust the parser.)

After you have a JSON or a log with `ioctl` + `inHex` for the DPI change, we can pull out the candidate write payload and replay it with `ble_write_runner.py`.
