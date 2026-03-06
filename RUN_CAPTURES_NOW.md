# Run captures now

Do this in **PowerShell or Command Prompt** on your Windows machine (where Synapse and the mouse are). Use a terminal where `python --version` works.

## One-shot (all three steps)

**Option A – batch file (no execution policy needed):**
```cmd
cd c:\Users\gh123\dev\open-snek
run_captures.bat
```

**Option B – PowerShell script** (if scripts are allowed):
```powershell
cd c:\Users\gh123\dev\open-snek
.\run_captures.ps1
```

- **Step 1:** Don’t touch any settings for 30 seconds (baseline).
- **Step 2:** When it says to change one setting, in Synapse change **only** DPI (e.g. 800 → 1600) **once**.
- **Step 3:** Script runs the diff and prints candidate payloads.

---

## Or run each step yourself

```powershell
cd c:\Users\gh123\dev\open-snek
```

**1. Baseline (30 s, no changes)**  
`python run_frida_capture.py --run baseline --duration 30`

**2. DPI capture (change DPI once when prompted)**  
`python run_frida_capture.py --run dpi_800_to_1600`

**3. Diff**  
`python diff_artifacts.py artifacts\baseline.json artifacts\dpi_800_to_1600.json`

---

If you see “Python was not found”: install Python from https://www.python.org/downloads/ and tick **“Add python.exe to PATH”**, then open a **new** terminal and run again.

If Frida can’t attach: run PowerShell **as Administrator** and run the same commands (or run `.\run_captures.ps1`).
