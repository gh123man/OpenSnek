# Windows BT RE experiment checklist

Use this when following **RUNBOOK_WINDOWS_BT_RE.md**. Do each step on the **Windows** machine where Synapse and the mouse are running.

---

## Before you start

- [ ] Mouse paired over **Bluetooth** (not USB).
- [ ] Razer Synapse open and able to change settings (e.g. DPI).
- [ ] Python 3 and RE tools installed: `pip install -r requirements-re.txt` (see SETUP_WINDOWS_RE.md).
- [ ] Optional: run `python list_razer_processes.py` (as Admin) to see which RazerAppEngine PIDs load the BLE DLL.

---

## 1. Baseline capture (~30 s)

**You:** Start capture. Do **not** change any settings for 30 seconds.

```powershell
cd c:\Users\gh123\dev\open-snek
python run_frida_capture.py --run baseline --duration 30
```

**Observe:** Console shows “Capturing for 30 seconds… Do not change any settings.” Let it run; then check `artifacts\baseline.json` and `artifacts\capture_baseline.log`.

---

## 2. DPI change capture (Test A)

**You:** Start capture, then in Synapse change **only** DPI from 800 → 1600 (or one clear step). Wait for the script to finish.

```powershell
python run_frida_capture.py --run dpi_800_to_1600
```

**Observe:** When you see “Change ONE setting…”, change DPI once. After ~15 s, check `artifacts\dpi_800_to_1600.json` and the log.

---

## 3. Poll rate capture (Test B, optional)

**You:** Start capture, then change **only** poll rate (e.g. 1000 → 500 Hz).

```powershell
python run_frida_capture.py --run poll_1000_to_500
```

**Observe:** Change poll rate once when prompted; then check `artifacts\poll_1000_to_500.json`.

---

## 4. Diff and replay

**You:** Run the diff (on this repo, any machine):

```powershell
python diff_artifacts.py artifacts\baseline.json artifacts\dpi_800_to_1600.json
```

**Observe:** Note any “Candidate NEW write payloads” and `value_hex`. Use `ble_write_runner.py` on a machine where BLE GATT is available (e.g. macOS with the mouse in BT mode):

```bash
python ble_write_runner.py --target "<device-id>" --write-char "<char-uuid>" --payload "<hex>" --response
```

---

## If Frida doesn’t capture BLE

Use **API Monitor** (see API_MONITOR_SYNAPSE.md):

1. Run API Monitor as Administrator.
2. Hook **all** RazerAppEngine.exe processes.
3. Enable **DeviceIoControl** (and optionally CreateFileW).
4. Start capture, change DPI once in Synapse, stop.
5. Export/save the capture; copy DeviceIoControl lines (ioctl, inLen, inHex) into a file and run:

```powershell
python parse_capture_log.py path\to\saved_log.txt -o artifacts\dpi_800_to_1600.json --run dpi_800_to_1600
```

(You may need to trim the log to the relevant lines so the parser recognizes `[DeviceIoControl]`-style lines.)

---

## When to prompt the user

- **Change settings:** Steps 2 and 3 say when to change DPI or poll rate.
- **Observe:** After each capture, confirm `artifacts\*.json` and logs look correct; after diff, confirm candidate payloads before replay.
