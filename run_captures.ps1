# Run runbook captures: baseline, then DPI change. Run this in PowerShell from project root.
# Prereqs: Synapse open, mouse paired over Bluetooth, pip install -r requirements-re.txt

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$py = $null
foreach ($p in @("python", "py", "python3")) {
    try {
        $v = & $p --version 2>&1
        if ($LASTEXITCODE -eq 0 -and $v -match "Python") { $py = $p; break }
    } catch {}
}
if (-not $py) { Write-Host "Python not found. Install from python.org and add to PATH, then run this script again." -ForegroundColor Red; exit 1 }

Write-Host "Using: $py" -ForegroundColor Cyan
Write-Host ""

# 1. Baseline
Write-Host "=== 1/3 Baseline (30s). Do NOT change any settings. ===" -ForegroundColor Yellow
& $py run_frida_capture.py --run baseline --duration 30
if ($LASTEXITCODE -ne 0) { Write-Host "Baseline failed. Is Synapse running?" -ForegroundColor Red; exit $LASTEXITCODE }
Write-Host ""

# 2. DPI change
Write-Host "=== 2/3 DPI capture. When you see the message, change DPI 800 -> 1600 ONCE in Synapse. ===" -ForegroundColor Yellow
& $py run_frida_capture.py --run dpi_800_to_1600
if ($LASTEXITCODE -ne 0) { Write-Host "DPI capture failed." -ForegroundColor Red; exit $LASTEXITCODE }
Write-Host ""

# 3. Diff
Write-Host "=== 3/3 Diff baseline vs dpi_800_to_1600 ===" -ForegroundColor Yellow
if (-not (Test-Path artifacts\baseline.json) -or -not (Test-Path artifacts\dpi_800_to_1600.json)) {
    Write-Host "Missing artifact JSONs. Run captures first." -ForegroundColor Red
    exit 1
}
& $py diff_artifacts.py artifacts\baseline.json artifacts\dpi_800_to_1600.json
Write-Host ""
Write-Host "Done. Check artifacts\ for .json and .log. Use ble_write_runner.py to replay candidate payloads." -ForegroundColor Green
