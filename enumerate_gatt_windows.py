"""
Enumerate all GATT services/characteristics on the Razer mouse from Windows.
Runbook Method 4: Before capturing Synapse, check what GATT services Windows exposes.

Usage:
  python enumerate_gatt_windows.py              # Scan for Razer (may miss paired HID)
  python enumerate_gatt_windows.py <address>   # Connect by address (e.g. CE:BF:9B:2A:EF:80)
"""
import asyncio
import sys
from bleak import BleakScanner, BleakClient

def normalize_address(addr: str) -> str:
    """Convert cebf9b2aef80 to CE:BF:9B:2A:EF:80 for Bleak."""
    s = addr.replace(":", "").replace("-", "").strip().upper()
    if len(s) == 12 and s.isalnum():
        return ":".join(s[i:i+2] for i in range(0, 12, 2))
    return addr

async def main():
    razer = None
    if len(sys.argv) > 1:
        address = normalize_address(sys.argv[1])
        print(f"Using address: {address}")
        # BleakClient accepts address string on Windows
        razer = address
    else:
        print("Scanning for Razer BLE devices...")
        devices = await BleakScanner.discover(timeout=10.0)
        for d in devices:
            name = d.name or ""
            if any(kw in name.lower() for kw in ['razer', 'basilisk', 'bsk']):
                razer = d
                print(f"Found: {d.name} ({d.address})")
                break

    if not razer:
        print("No Razer in scan. Get BT address from: Get-PnpDeviceProperty (DEVPKEY_Bluetooth_DeviceAddress)")
        print("Then: python enumerate_gatt_windows.py cebf9b2aef80")
        return

    # razer is either a BLEDevice (from scan) or address string
    async with BleakClient(razer) as client:
        print(f"\nConnected: {client.is_connected}")
        print(f"\nGATT Services:")
        for service in client.services:
            print(f"\n  Service: {service.uuid} — {service.description}")
            for char in service.characteristics:
                props = ", ".join(char.properties)
                print(f"    Char: {char.uuid} [{props}]")
                if "read" in char.properties:
                    try:
                        val = await client.read_gatt_char(char)
                        print(f"      Value: {val.hex()}")
                    except Exception as e:
                        print(f"      Read error: {e}")

asyncio.run(main())
