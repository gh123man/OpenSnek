@echo off
cd /d "%~dp0"

echo.
echo === 1/3 Baseline (30s). Do NOT change any settings. ===
python run_frida_capture.py --run baseline --duration 30
if errorlevel 1 (echo Baseline failed. Is Synapse running? & exit /b 1)

echo.
echo === 2/3 DPI capture. Change DPI 800 -^> 1600 ONCE in Synapse when ready. ===
python run_frida_capture.py --run dpi_800_to_1600
if errorlevel 1 (echo DPI capture failed. & exit /b 1)

echo.
echo === 3/3 Diff baseline vs dpi_800_to_1600 ===
if not exist artifacts\baseline.json (echo Missing artifacts\baseline.json & exit /b 1)
if not exist artifacts\dpi_800_to_1600.json (echo Missing artifacts\dpi_800_to_1600.json & exit /b 1)
python diff_artifacts.py artifacts\baseline.json artifacts\dpi_800_to_1600.json

echo.
echo Done. Check artifacts\ for .json and .log files.
pause
