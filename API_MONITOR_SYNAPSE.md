# Using API Monitor to Capture Razer Synapse BLE Traffic

**Note:** In practice, hooking Razer Synapse or RazerAppEngine with API Monitor did **not** capture the actual BLE settings writes – only mouse click/input events. For recovering the config write protocol, see **[APPROACH_BT_ALTERNATIVES.md](APPROACH_BT_ALTERNATIVES.md)** (OTA BLE sniffing, driver-level capture, or BLE discovery + trial writes).

The instructions below are kept for reference if you want to retry or target a different process.

---

## 1. Download and install

- **64-bit (use this for RazerAppEngine):**  
  [API Monitor v2 Alpha-r13 x64](http://www.rohitab.com/download/api-monitor-v2r13-setup-x64.exe)
- **Portable (no install):**  
  [API Monitor v2 Alpha-r13 Portable (x86 + x64)](http://www.rohitab.com/download/api-monitor-v2r13-x86-x64.zip)

**Or use the installer already in this repo (if present):**
```powershell
# From project root
.\tools\apimonitor-v2r13-setup-x64.exe
```
**From PowerShell (if you need to download again):**
```powershell
cd $env:USERPROFILE\Downloads
Invoke-WebRequest -Uri "http://www.rohitab.com/download/api-monitor-v2r13-setup-x64.exe" -OutFile "apimonitor-setup-x64.exe" -UseBasicParsing
Start-Process .\apimonitor-setup-x64.exe
```
Then complete the installer. If you use the portable ZIP from rohitab.com, extract it and run `apimonitor.exe` (64-bit) from the extracted folder.

---

## 2. Run API Monitor as Administrator

Right‑click **API Monitor** → **Run as administrator**. (Needed to hook processes like RazerAppEngine.)

---

## 3. Choose what to monitor

1. Open the **API Capture Filter** (left or top panel).
2. Expand **Kernel32.dll** (or **Kernelbase.dll**).
3. Expand **File Management** or **I/O** (or similar).
4. Enable:
   - **DeviceIoControl** – to see IOCTL codes and input/output buffers (where BLE GATT writes often show up).
   - Optionally **CreateFileW** – to see when BLE device paths are opened (e.g. `\?\BTH...`).
5. If there is a **Bluetooth** or **Devices** category, enable any **BluetoothGATT*** or **DeviceIoControl**-related APIs there as well.
6. (Optional) Use **External DLL Filter** to add `Windows.Devices.Bluetooth.dll` and select any GATT/write-related APIs if listed.

---

## 4. Monitor **one** RazerAppEngine at a time (you can't hook all at once) (don’t guess which one does BLE)

Razer spawns many processes from the same binary; only one (or a few) do the actual Bluetooth communication. We don’t know which in advance.

1. In the **Running Processes** list, find every **RazerAppEngine.exe**.
2. **Hook every RazerAppEngine.exe** (right‑click → **Hook Process** on each, or double‑click each).  
   If API Monitor won’t hook some, note their PIDs and continue with the rest.
3. Confirm they appear under **Hooked Processes**.  
4. When you change DPI (step 5), the **process that shows the DeviceIoControl (or CreateFileW) call in the log is the one doing BLE** – no need to guess.

**Optional – see which process has the BLE DLL (run as Admin):**
```powershell
python list_razer_processes.py
```
With admin rights this lists which RazerAppEngine PIDs have `Windows.Devices.Bluetooth.dll` loaded (“BLE candidates”). Without admin, all show “no access” (and Frida can only attach to a subset).

---

## 5. Capture a DPI change

1. Click **Start** (or enable monitoring) so that new API calls are logged.
2. In **Razer Synapse**, change **one** setting (e.g. DPI from 800 → 1600).  
   Make sure the mouse is connected over **Bluetooth** and the change is applied.
3. Wait a few seconds, then click **Stop** (or disable monitoring).
4. In the **Output** / **Summary** view, look for:
   - **DeviceIoControl** – note **dwIoControlCode** (ioctl) and **lpInBuffer** / **nInBufferSize** (and buffer content in **Hex Buffer** or **Parameters**).
   - **CreateFileW** – note **lpFileName** for paths containing `BTH` or `bluetooth`.

---

## 6. Save and export

1. **File → Save Capture** (or similar) and save as e.g. `dpi.apmx64` (native format).
2. **To get payloads for the runbook** you can either:
   - **From API Monitor:** Re-open the saved capture, filter the log for **DeviceIoControl**, find the call that happened when you changed DPI (small input buffer, e.g. 8–128 bytes). Copy or note **dwIoControlCode** (ioctl) and the **lpInBuffer** hex. Paste into a text file (one line per call) so `parse_capture_log.py` can parse it, or fill `artifacts/DELIVERABLES_TEMPLATE.md` manually.
   - **From .apmx64 only:** Run the project parser (finds 05 05 02 / 06 40 / 03 20 in the binary):  
     `python parse_apmx64.py dpi.apmx64 -o artifacts/dpi_candidates.json`  
     Then inspect `artifacts/dpi_candidates.json` for `context_hex` that looks like a DPI payload.

---

## 7. What to record for the runbook

For each captured DPI (or other) change, note:

- **DeviceIoControl:**  
  `ioctl` (hex), `inLen`, and **inHex** (full input buffer in hex).  
  For BLE GATT-style writes we often see small buffers (e.g. 8–128 bytes) and ioctls that are Bluetooth-related.
- **CreateFileW:**  
  Any path containing `BTH` or `bluetooth` (device path used for BLE).
- **Time** of the change (relative to start of capture is enough).

Example line for the runbook:

```text
DeviceIoControl  ioctl=0xXXXX  inLen=20  inHex=050502064006400000...
```

---

## Troubleshooting

- **“Failed to hook” / no effect:**  
  Run API Monitor as Administrator. Try hooking a different **RazerAppEngine.exe** instance.
- **Too much noise:**  
  After capture, use **Display Filter** to show only **DeviceIoControl** (and optionally **CreateFileW**). Filter by **nInBufferSize** (e.g. 4–256) if the UI allows.
- **No Bluetooth-related calls:**  
  Hook **all** RazerAppEngine.exe processes (see step 4), then change DPI once; the process that appears in the log for DeviceIoControl/CreateFileW is the one doing BLE. If you only hooked one, you may have hooked the wrong process.

---

## Link in runbook

The main runbook points here for the API Monitor (fallback) method:  
**RUNBOOK_WINDOWS_BT_RE.md** → “API Monitor (fallback)” → this file.
