# Windows BLE Traffic Capture Runbook

Capture the raw GATT writes that Razer Synapse sends when changing mouse settings over Bluetooth. We know the driver stack (see PROTOCOL.md) — these methods target specific layers.

## Prerequisites

- Windows 10/11 PC with Razer mouse connected via **Bluetooth** (not USB dongle)
- Razer Synapse installed and working
- Admin PowerShell

## Method 1: BLE GATT ETW Tracing (easiest, try first)

Windows has a built-in ETW provider that logs all BLE GATT read/write/notify operations.

### Start capture

```powershell
# Open admin PowerShell
# Start the trace
logman create trace blegatt -p "Microsoft-Windows-Bluetooth-BtGatt" 0xFFFFFFFF 0xFF -o C:\temp\blegatt.etl -ets
```

### Trigger the action

1. Open Razer Synapse
2. Change DPI from 800 → 1600 (or any clear change)
3. Wait 2 seconds
4. Change DPI back to 800
5. Wait 2 seconds

### Stop capture

```powershell
logman stop blegatt -ets
```

### Convert to readable text

```powershell
# Decode the ETL file
tracerpt C:\temp\blegatt.etl -o C:\temp\blegatt.xml -of XML
# Also dump as CSV for easier grep
tracerpt C:\temp\blegatt.etl -o C:\temp\blegatt.csv -of CSV
```

### What to look for

The XML/CSV will contain GATT Write events with handle numbers and payloads. We know from the Windows device dump:
- HID service starts at GATT handle **23**
- Vendor service starts at GATT handle **59**
- Any writes to handles **23-58** are HID service (likely the config protocol)
- Any writes to handles **59+** are vendor service (lighting)

Look for write events near your DPI change timestamps containing 90-byte payloads.

---

## Method 2: Razer Driver WPP Tracing

The Razer driver (`RzDev_00ba.sys`) has WPP tracing compiled in. We found its TraceGuid in the registry.

### Start capture

```powershell
# Open admin PowerShell
# Start WPP trace on the Razer driver
logman create trace razertrace -p "{ff1e9f02-f708-4330-b7e1-dc82e8310b94}" 0xFFFFFFFF 0xFF -o C:\temp\razertrace.etl -ets
```

### Trigger the action

Same as Method 1 — change a setting in Synapse.

### Stop capture

```powershell
logman stop razertrace -ets
```

### Convert to text

```powershell
tracerpt C:\temp\razertrace.etl -o C:\temp\razertrace.xml -of XML
tracerpt C:\temp\razertrace.etl -o C:\temp\razertrace.csv -of CSV
```

### Notes

WPP trace output may be hard to read without the TMF (trace message format) files from Razer's PDB. But the raw event data often contains hex payloads that are still useful. Even if the text is garbled, look for 90-byte hex blobs.

If the output is empty, the GUID may only be active at higher verbosity or the driver may not emit traces in release builds. Move on to Method 3.

---

## Method 3: General Bluetooth ETW (wider net)

Capture from multiple Bluetooth ETW providers at once.

### Start capture

```powershell
# Create trace with multiple BT providers
logman create trace btall -o C:\temp\btall.etl -ets

# Add providers
logman update trace btall -p "Microsoft-Windows-Bluetooth-BtGatt" 0xFFFFFFFF 0xFF -ets
logman update trace btall -p "Microsoft-Windows-Bluetooth-Bthmini" 0xFFFFFFFF 0xFF -ets
logman update trace btall -p "{8a1f9517-3a8c-4a9e-a018-4f17a200f277}" 0xFFFFFFFF 0xFF -ets

# Also try the Razer driver
logman update trace btall -p "{ff1e9f02-f708-4330-b7e1-dc82e8310b94}" 0xFFFFFFFF 0xFF -ets
```

### Trigger the action

Change DPI in Synapse, wait, change back.

### Stop and convert

```powershell
logman stop btall -ets
tracerpt C:\temp\btall.etl -o C:\temp\btall.xml -of XML
tracerpt C:\temp\btall.etl -o C:\temp\btall.csv -of CSV
```

---

## Method 4: Hook WUDFHost (HidOverGatt is user-mode)

HidOverGatt is a UMDF (user-mode) driver running inside a `WUDFHost.exe` process. We can attach to it with Frida.

### Find the right WUDFHost process

```powershell
# List WUDFHost processes and their loaded DLLs
Get-Process WUDFHost | ForEach-Object {
    $pid = $_.Id
    $dlls = (Get-Process -Id $pid -Module -ErrorAction SilentlyContinue).ModuleName
    if ($dlls -match "HidOverGatt|BthLEEnum|Wudfrd") {
        Write-Host "PID $pid - likely BLE HID host"
        $dlls | Where-Object { $_ -match "Hid|Bth|Gatt|Rz" }
    }
}
```

### Attach with Frida (if installed)

```bash
# pip install frida-tools
frida -p <WUDFHOST_PID> -l capture_wudf.js
```

This is more complex — only try if Methods 1-3 don't produce useful output.

---

## Collecting Results

After running any method above, copy these files back to the repo:

```
C:\temp\blegatt.etl
C:\temp\blegatt.xml
C:\temp\blegatt.csv
C:\temp\razertrace.etl
C:\temp\razertrace.xml
C:\temp\razertrace.csv
C:\temp\btall.etl
C:\temp\btall.xml
C:\temp\btall.csv
```

The XML/CSV files are most useful. Push them or share them for analysis.

### Quick sanity check

Before copying everything, grep for write events:

```powershell
# Check if there's anything useful in the GATT trace
Select-String -Path C:\temp\blegatt.csv -Pattern "Write" | Select-Object -First 20
```

```powershell
# Check for any data in the Razer trace
(Get-Item C:\temp\razertrace.etl).Length
Select-String -Path C:\temp\razertrace.csv -Pattern "." | Measure-Object
```

If the CSVs have write events with hex data, we're in business. If they're empty, that provider didn't capture anything useful.

---

## What Success Looks Like

We're looking for a 90-byte payload written to a GATT handle in the HID service range (23-58) that matches the Razer protocol format:

```
00 1F 00 00 XX CC II [args...] CRC 00
      ^^^^       ^^ ^^
      size      class cmd
```

Where:
- Byte 0 = `0x00` (new command)
- Byte 1 = `0x1F` (transaction ID)
- Byte 5 = data size
- Byte 6 = command class (`0x04` for DPI)
- Byte 7 = command ID (`0x05` for set DPI, `0x85` for get DPI)
- Byte 88 = CRC (XOR of bytes 2-87)

If we see this, we know exactly which GATT handle carries the protocol, and we can write to it directly from Linux (and potentially find a macOS workaround).
