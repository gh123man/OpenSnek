# DPI change capture attempt

**Date:** 2026-03-06  
**Action:** User changed DPI to 1600, then changed DPI again (second run).  
**Frida:** Attached to RazerAppEngine.exe PID 6148.

## Result

- **No `[DeviceIoControl]`** lines with 4–256 byte input were logged.
- **No `[CreateFileW BLE]`** lines were logged.
- **No `[GATT WRITE]`** (Win32 API not present in process).

Frida session exited after ~5 s each time (background run); may have missed the exact moment of the change, or BLE traffic may be in another process.

## Next steps

1. **Attach to multiple RazerAppEngine PIDs** and capture again (or identify which process handles the mouse).
2. **Widen hook:** log all `DeviceIoControl` calls (any input size) to see if BLE uses a different buffer size.
3. **API Monitor** (runbook fallback) to trace WinRT/COM BLE APIs.
4. **User runs Frida in a visible terminal** (not background) and keeps it open while changing DPI, then shares the log.
