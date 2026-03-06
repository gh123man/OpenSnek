#!/usr/bin/env python3
"""
List all RazerAppEngine.exe processes and show which ones have
Windows.Devices.Bluetooth.dll loaded (likely doing BLE) and which
we can/cannot access (Frida can only attach to some).

Run as Administrator to see modules for more processes.
"""
import sys

try:
    import psutil
except ImportError:
    print("Install psutil: pip install psutil")
    sys.exit(1)

# Windows-only: enumerate loaded modules
def get_process_modules(pid):
    """Return list of loaded module base names (e.g. 'Windows.Devices.Bluetooth.dll') or None if access denied."""
    if sys.platform != "win32":
        return None
    try:
        import ctypes
        from ctypes import wintypes
        kernel32 = ctypes.windll.kernel32
        psapi = ctypes.windll.psapi
        PROCESS_QUERY_INFORMATION = 0x0400
        PROCESS_VM_READ = 0x0010
        h = kernel32.OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, False, pid)
        if not h:
            return None  # access denied
        try:
            buf = (ctypes.c_void_p * 1024)()
            cb = ctypes.sizeof(buf)
            needed = wintypes.DWORD()
            if not psapi.EnumProcessModules(h, buf, cb, ctypes.byref(needed)):
                return []
            mods = []
            path_buf = ctypes.create_unicode_buffer(260)
            for i in range(1024):
                if not buf[i]:
                    break
                if psapi.GetModuleFileNameExW(h, buf[i], path_buf, 260):
                    name = path_buf.value.split("\\")[-1]
                    mods.append(name)
            return mods
        finally:
            kernel32.CloseHandle(h)
    except Exception:
        return None

def main():
    razers = [p for p in psutil.process_iter(attrs=["pid", "name", "cmdline"]) if p.info.get("name") == "RazerAppEngine.exe"]
    if not razers:
        print("No RazerAppEngine.exe processes found. Is Synapse running?")
        return
    print("RazerAppEngine.exe processes (which load BLE DLL / which we can read):\n")
    print("%-8s %-12s %-50s" % ("PID", "Has BLE DLL?", "Cmdline (first 50 chars)"))
    print("-" * 72)
    ble_pids = []
    no_access_pids = []
    for p in razers:
        pid = p.info["pid"]
        cmdline = p.info.get("cmdline") or []
        cmd_str = " ".join(cmdline)[:50] if cmdline else ""
        mods = get_process_modules(pid)
        if mods is None:
            has_ble = "no access"
            no_access_pids.append(pid)
        else:
            ble_dlls = [m for m in mods if "Bluetooth" in m and "Devices" in m]
            has_ble = "YES" if ble_dlls else "no"
            if ble_dlls:
                ble_pids.append(pid)
        print("%-8s %-12s %s" % (pid, has_ble, cmd_str))
    print()
    if ble_pids:
        print("Processes with Windows.Devices.Bluetooth*.dll loaded (BLE candidates): %s" % ble_pids)
    if no_access_pids:
        print("Processes we could not read (run as Admin to see; may be the BLE process): %s" % no_access_pids)
    print("\nFor API Monitor: hook ALL RazerAppEngine processes, then change DPI once; the one that shows DeviceIoControl in the log is doing BLE.")
    print("For Frida: we can only attach to processes we can read; the BLE process might be one that refused (no access).")

if __name__ == "__main__":
    main()
