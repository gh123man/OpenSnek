# Windows setup for Bluetooth RE (runbook tools)

Use this when you have the mouse connected to **Razer Synapse over Bluetooth** and want to capture BLE GATT writes. This doc gets the tools installed with minimal manual steps.

---

## 1. Install Python (if needed)

You need a **real** Python install (the “python” in the Start menu that opens the Microsoft Store is just a stub).

**Option A – From python.org (recommended)**  
1. Open https://www.python.org/downloads/  
2. Download **Python 3.12** (or latest 3.x) for Windows.  
3. Run the installer.  
4. **Important:** check **“Add python.exe to PATH”** at the bottom, then click “Install Now”.  
5. Close and reopen PowerShell/terminal.

**Option A (one command)** – In PowerShell (Run as Administrator optional but can help):

```powershell
Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.12.7/python-3.12.7-amd64.exe" -OutFile "$env:TEMP\python-installer.exe" -UseBasicParsing; Start-Process -FilePath "$env:TEMP\python-installer.exe" -ArgumentList "/passive", "InstallAllUsers=0", "PrependPath=1" -Wait
```

Then **close and reopen PowerShell** so `python` is on PATH.

**Option B – Microsoft Store**  
1. Open Microsoft Store.  
2. Search “Python 3.12”.  
3. Install “Python 3.12” from Python Software Foundation.  
4. Reopen PowerShell.

**Check:** In a **new** PowerShell window run:

```powershell
python --version
```

You should see something like `Python 3.12.x`. If you get “not found” or a Store prompt, Python is not on PATH; use Option A and tick “Add to PATH”.

---

## 2. Install RE tools (Frida) in this project

Open PowerShell in the project folder (e.g. `c:\Users\gh123\dev\open-snek`), then:

```powershell
cd c:\Users\gh123\dev\open-snek
python -m pip install --upgrade pip
python -m pip install -r requirements-re.txt
```

This installs **Frida** and **frida-tools** (used to hook Synapse and log BLE-related API calls).

**Check:**

```powershell
frida --version
```

You should see a version number.

---

## 3. (Optional) Wireshark + Npcap for BLE/USB capture

Only needed if you want packet-level capture (e.g. when API hooking isn’t enough).

1. **Npcap** (required for capturing):  
   - https://npcap.com/#download  
   - Run the installer; use default options (WinPcap API–compatible mode is fine).

2. **Wireshark**:  
   - https://www.wireshark.org/download.html  
   - Install; when it asks, choose to use Npcap for capturing.

---

## 4. Run the Frida script (after Synapse is open)

1. Pair the mouse in Bluetooth mode and open **Razer Synapse**.  
2. Confirm Synapse can change settings (e.g. DPI).  
3. In the project folder, list Synapse-related processes:

```powershell
frida-ps | findstr -i razer
```

Note the exact process name (e.g. `Razer Synapse 3.exe` or `Razer Central.exe`).

4. Attach the script. Use the process name **RazerAppEngine** (the Synapse backend) or a PID from step 3:

```powershell
frida -l frida_synapse_gatt.js -n "RazerAppEngine"
```

Or by PID (e.g. 6148):

```powershell
frida -l frida_synapse_gatt.js -p 6148
```

**Do not use `-q`** so the script stays attached. Leave this window open.

5. In Synapse, change **one** setting (e.g. DPI 800 → 1600).  
6. Watch the Frida console for:
   - **`[GATT WRITE]`** – Win32 API path (if Synapse used it): char UUID, handles, `payload_hex`.
   - **`[DeviceIoControl]`** – WinRT path fallback: `ioctl`, `inLen`, `inHex` (likely GATT write payload).
   - **`[CreateFileW BLE]`** – BLE device path being opened.
7. To save a capture for the runbook, run with output redirected:
   ```powershell
   frida -l frida_synapse_gatt.js -n "RazerAppEngine" 2>&1 | Tee-Object -FilePath capture.log
   ```
   Then do one change (e.g. DPI 800→1600), wait a few seconds, stop with Ctrl+C. Use `capture.log` as `dpi_800_to_1600.json` content or paste into the runbook artifacts.

---

## 5. If Frida says “Failed to spawn” or “Process not found”

- Run PowerShell **as Administrator** and try again.  
- Or start Synapse **after** running:  
  `frida -l frida_synapse_gatt.js -f "C:\...\Razer Synapse 3.exe" --no-pause`  
  (use the real path to the Synapse exe from Task Manager → Open file location.)

---

## 6. Next steps (from the runbook)

- **Baseline:** Open Synapse, no changes, capture for ~30 s.  
- **Test A:** Change DPI 800 → 1600, capture.  
- **Test B/C:** Poll rate or DPI stage change, capture.  
- Save each run as `baseline.json`, `dpi_800_to_1600.json`, etc., with the fields in `RUNBOOK_WINDOWS_BT_RE.md` (time, op, service_uuid, char_uuid, value_hex, etc.).  
- Use the repo’s `ble_write_runner.py` (on a machine where BLE GATT is available) to replay candidate payloads.

---

## Quick reference

| Step              | Command / action                                      |
|-------------------|--------------------------------------------------------|
| Check Python      | `python --version`                                     |
| Install Frida     | `pip install -r requirements-re.txt`                   |
| List processes    | `frida-ps \| findstr -i razer`                        |
| Attach script     | `frida -l frida_synapse_gatt.js -n "RazerAppEngine"`            |
