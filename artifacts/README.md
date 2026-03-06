# Runbook capture artifacts

This folder holds structured JSON and logs from the Windows BT RE runbook.

- **baseline.json** – Capture with Synapse open, no setting changes (~30 s).
- **dpi_800_to_1600.json** – One change: DPI 800 → 1600.
- **poll_1000_to_500.json** – One change: poll rate (or equivalent).
- **capture_*.log** – Raw Frida/API Monitor log for each run.

Generate with:
```powershell
python run_frida_capture.py --run baseline --duration 30
python run_frida_capture.py --run dpi_800_to_1600
```

Convert raw log to JSON:
```powershell
python parse_capture_log.py capture.log -o artifacts/dpi_800_to_1600.json --run dpi_800_to_1600
```

Diff baseline vs one-change:
```powershell
python diff_artifacts.py artifacts/baseline.json artifacts/dpi_800_to_1600.json
```
