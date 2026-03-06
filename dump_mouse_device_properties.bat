@echo off
cd /d "%~dp0"
echo Dumping mouse device properties to device_properties_mouse.txt ...
powershell -ExecutionPolicy Bypass -File "%~dp0dump_mouse_device_properties.ps1"
if exist device_properties_mouse.txt (
    echo Done. Open device_properties_mouse.txt
    notepad device_properties_mouse.txt
) else (
    echo No output file. Check for errors above.
)
pause
