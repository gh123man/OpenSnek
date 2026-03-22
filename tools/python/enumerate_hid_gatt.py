#!/usr/bin/env python3
"""
Enumerate BLE HID report characteristics on Windows.

This is primarily for mapping HID Report / Report Reference handles back to
captured ATT notify handles such as 0x0027, 0x002b, and 0x002f.
"""
import asyncio
import argparse
import sys

try:
    from bleak import BleakClient, BleakScanner
except ImportError:
    print("Install bleak: pip install bleak")
    sys.exit(1)

# Standard BLE HID UUIDs
HID_SERVICE        = "00001812-0000-1000-8000-00805f9b34fb"
REPORT_MAP_CHAR    = "00002a4b-0000-1000-8000-00805f9b34fb"  # HID Report Map
REPORT_CHAR        = "00002a4d-0000-1000-8000-00805f9b34fb"  # HID Report
HID_INFO_CHAR      = "00002a4a-0000-1000-8000-00805f9b34fb"  # HID Information
HID_CTRL_CHAR      = "00002a4c-0000-1000-8000-00805f9b34fb"  # HID Control Point
PROTOCOL_MODE_CHAR = "00002a4e-0000-1000-8000-00805f9b34fb"  # Protocol Mode
REPORT_REF_DESC    = "00002908-0000-1000-8000-00805f9b34fb"  # Report Reference descriptor
CCCD_DESC          = "00002902-0000-1000-8000-00805f9b34fb"  # Client Characteristic Config

# Also enumerate vendor service for completeness
VENDOR_SERVICE     = "52401523-f97c-7f90-0e7f-6c6f4e36db1c"

REPORT_TYPES = {1: "Input", 2: "Output", 3: "Feature"}
RAZER_NAME_KEYWORDS = ("razer", "basilisk", "bsk", "deathadder", "viper")


def build_args():
    parser = argparse.ArgumentParser(
        description="Enumerate BLE HID report characteristics on Windows."
    )
    parser.add_argument(
        "address",
        nargs="?",
        help="Bluetooth address of the mouse. If omitted, scan by name."
    )
    parser.add_argument(
        "--name",
        default="BSK V3 X",
        help="Case-insensitive device-name substring to match during scan."
    )
    parser.add_argument(
        "--scan-timeout",
        type=float,
        default=8.0,
        help="Seconds to scan when address is not provided."
    )
    return parser.parse_args()


async def resolve_address(address: str | None, name_hint: str, scan_timeout: float) -> str:
    if address:
        return address

    print(f"Scanning for BLE devices for up to {scan_timeout:.1f}s...")
    devices = await BleakScanner.discover(timeout=scan_timeout)
    name_hint_lower = name_hint.lower()
    candidates = []
    for device in devices:
        name = device.name or ""
        lowered = name.lower()
        if name_hint_lower in lowered or any(keyword in lowered for keyword in RAZER_NAME_KEYWORDS):
            candidates.append(device)

    if not candidates:
        print("No matching BLE devices found.")
        print("Try re-running with the explicit Bluetooth address:")
        print("  python tools/python/enumerate_hid_gatt.py XX:XX:XX:XX:XX:XX")
        sys.exit(1)

    chosen = candidates[0]
    print(f"Using {chosen.name or '(unnamed)'} at {chosen.address}")
    return chosen.address


def descriptor_handle(characteristic, descriptor_uuid: str) -> int | None:
    for desc in characteristic.descriptors:
        if str(desc.uuid).lower() == descriptor_uuid:
            return desc.handle
    return None


async def read_descriptor_if_present(client: BleakClient, characteristic, descriptor_uuid: str) -> bytes | None:
    handle = descriptor_handle(characteristic, descriptor_uuid)
    if handle is None:
        return None
    try:
        return await client.read_gatt_descriptor(handle)
    except Exception:
        return None


async def enumerate_device(address: str):
    print(f"Connecting to {address}...")

    async with BleakClient(address) as client:
        print(f"Connected: {client.is_connected}")
        print(f"MTU: {client.mtu_size if hasattr(client, 'mtu_size') else 'unknown'}")
        print()

        # --- Enumerate ALL services ---
        print("=" * 70)
        print("ALL GATT SERVICES")
        print("=" * 70)
        for svc in client.services:
            print(f"\nService: {svc.uuid} (handle {svc.handle})")
            print(f"  Description: {svc.description}")
            for char in svc.characteristics:
                props = ", ".join(char.properties)
                print(f"  Char: {char.uuid} (handle {char.handle}) [{props}]")
                print(f"    Description: {char.description}")

                # Read descriptors
                for desc in char.descriptors:
                    print(f"    Desc: {desc.uuid} (handle {desc.handle})")
                    try:
                        val = await client.read_gatt_descriptor(desc.handle)
                        print(f"      Value: {val.hex()} ({list(val)})")

                        # Decode Report Reference
                        if str(desc.uuid) == REPORT_REF_DESC and len(val) >= 2:
                            report_id = val[0]
                            report_type = REPORT_TYPES.get(val[1], f"Unknown({val[1]})")
                            print(f"      → Report ID: {report_id}, Type: {report_type}")
                    except Exception as e:
                        print(f"      (read error: {e})")

        # --- Focus on HID Service ---
        print()
        print("=" * 70)
        print("HID SERVICE DETAIL")
        print("=" * 70)

        hid_svc = None
        for svc in client.services:
            if svc.uuid == HID_SERVICE:
                hid_svc = svc
                break

        if not hid_svc:
            print("HID service not found!")
            return

        report_map_char = None
        feature_reports = []
        output_reports = []
        input_reports = []
        unknown_reports = []

        for char in hid_svc.characteristics:
            if char.uuid == REPORT_MAP_CHAR:
                report_map_char = char
            elif char.uuid == REPORT_CHAR:
                report_ref = await read_descriptor_if_present(client, char, REPORT_REF_DESC)
                cccd_handle = descriptor_handle(char, CCCD_DESC)
                entry = {
                    "char": char,
                    "props": list(char.properties),
                    "report_ref_handle": descriptor_handle(char, REPORT_REF_DESC),
                    "cccd_handle": cccd_handle,
                }
                if report_ref and len(report_ref) >= 2:
                    entry["report_id"] = report_ref[0]
                    entry["report_type"] = report_ref[1]
                    entry["type_name"] = REPORT_TYPES.get(report_ref[1], f"Unknown({report_ref[1]})")
                else:
                    entry["report_id"] = None
                    entry["report_type"] = None
                    entry["type_name"] = "Unknown"

                if entry["report_type"] == 1:
                    input_reports.append(entry)
                elif entry["report_type"] == 2:
                    output_reports.append(entry)
                elif entry["report_type"] == 3:
                    feature_reports.append(entry)
                else:
                    unknown_reports.append(entry)

        def print_report_group(title: str, reports):
            print(f"\n{title} ({len(reports)}):")
            for report in reports:
                report_id = "?" if report["report_id"] is None else str(report["report_id"])
                report_type = report["type_name"]
                handle = report["char"].handle
                report_ref_handle = report["report_ref_handle"]
                cccd_handle = report["cccd_handle"]
                print(
                    f"  Report ID {report_id:>3} | Type {report_type:<7} | "
                    f"CharHandle 0x{handle:04x} | ReportRef "
                    f"{'0x%04x' % report_ref_handle if report_ref_handle is not None else '-'} | "
                    f"CCCD {'0x%04x' % cccd_handle if cccd_handle is not None else '-'} | "
                    f"Props {report['props']}"
                )

        print_report_group("Input Reports", input_reports)
        print_report_group("Output Reports", output_reports)
        print_report_group("Feature Reports", feature_reports)
        print_report_group("Unknown Report Entries", unknown_reports)

        print("\nTarget capture handles to compare against:")
        print("  Hypershift press/release notify: 0x0027")
        print("  Passive DPI / heartbeat notify: 0x002b")
        print("  Nearby zeroed notify seen during first release: 0x002f")

        # Read Report Map
        if report_map_char:
            print(f"\nReport Map (handle {report_map_char.handle}):")
            try:
                report_map = await client.read_gatt_char(report_map_char)
                print(f"  Size: {len(report_map)} bytes")
                # Print hex dump
                for i in range(0, len(report_map), 16):
                    chunk = report_map[i:i+16]
                    hex_str = " ".join(f"{b:02X}" for b in chunk)
                    print(f"  {i:04X}: {hex_str}")
            except Exception as e:
                print(f"  Error reading Report Map: {e}")

        # --- Try reading Feature Reports ---
        if feature_reports:
            print()
            print("=" * 70)
            print("READING FEATURE REPORTS")
            print("=" * 70)
            for r in feature_reports:
                print(f"\nReport ID {r['report_id']} (handle {r['char'].handle}):")
                try:
                    val = await client.read_gatt_char(r['char'])
                    print(f"  Value ({len(val)} bytes): {val.hex()}")
                except Exception as e:
                    print(f"  Error: {e}")

        # --- Try writing Razer 90-byte protocol to Feature Reports ---
        if feature_reports:
            print()
            print("=" * 70)
            print("TESTING RAZER PROTOCOL ON FEATURE REPORTS")
            print("=" * 70)

            # Build a simple Razer "get serial" command (read-only, safe)
            # Transaction ID 0x1F, status 0x00, remaining 0x00, protocol 0x00
            # data_size 0x16, command_class 0x00, command_id 0x82 (get serial)
            razer_cmd = bytearray(90)
            razer_cmd[0] = 0x00   # status
            razer_cmd[1] = 0x1F   # transaction ID
            razer_cmd[2] = 0x00   # remaining packets
            razer_cmd[3] = 0x00   # protocol type
            razer_cmd[4] = 0x00   # data_size
            razer_cmd[5] = 0x00   # command_class
            razer_cmd[6] = 0x82   # command_id (get serial)
            # Calculate CRC (XOR of bytes 2-87)
            crc = 0
            for i in range(2, 88):
                crc ^= razer_cmd[i]
            razer_cmd[88] = crc
            razer_cmd[89] = 0x00  # reserved

            for r in feature_reports:
                if "write" in r['props'] or "write-without-response" in r['props']:
                    report_id = "?" if r["report_id"] is None else r["report_id"]
                    print(f"\n  Writing to Feature Report ID {report_id} (handle {r['char'].handle})...")
                    print(f"  Payload: {razer_cmd[:10].hex()}...{razer_cmd[88:].hex()}")
                    try:
                        await client.write_gatt_char(r['char'], bytes(razer_cmd), response=True)
                        print("  Write OK!")

                        # Try reading back
                        await asyncio.sleep(0.1)
                        try:
                            val = await client.read_gatt_char(r['char'])
                            print(f"  Response ({len(val)} bytes): {val.hex()}")
                            if len(val) >= 7:
                                print(f"    Status: 0x{val[0]:02x}, TxID: 0x{val[1]:02x}, Class: 0x{val[5]:02x}, CmdID: 0x{val[6]:02x}")
                        except Exception as e:
                            print(f"  Read-back error: {e}")
                    except Exception as e:
                        print(f"  Write error: {e}")

        # --- Summary ---
        print()
        print("=" * 70)
        print("SUMMARY")
        print("=" * 70)
        print(f"HID Service handle range: {hid_svc.handle} - ?")
        print(f"Total characteristics in HID service: {len(hid_svc.characteristics)}")
        print(f"Input Reports:   {len(input_reports)}")
        print(f"Output Reports:  {len(output_reports)}")
        print(f"Feature Reports: {len(feature_reports)}")
        print(f"Unknown Reports: {len(unknown_reports)}")

        if feature_reports:
            print("\n*** FEATURE REPORTS FOUND - Razer protocol likely goes here! ***")
            for r in feature_reports:
                writable = "write" in r['props'] or "write-without-response" in r['props']
                readable = "read" in r['props']
                report_id = "?" if r["report_id"] is None else r["report_id"]
                print(f"  ID {report_id}: {'W' if writable else '-'}{'R' if readable else '-'} handle={r['char'].handle}")
        else:
            print("\nNo Feature Reports found in HID service.")
            print("The Razer driver may inject them at the Windows driver level,")
            print("or commands may go through Output Reports.")

        if output_reports:
            print(f"\nOutput Reports found ({len(output_reports)}) - could also carry commands:")
            for r in output_reports:
                report_id = "?" if r["report_id"] is None else r["report_id"]
                print(f"  ID {report_id}: handle={r['char'].handle} props={r['props']}")


if __name__ == "__main__":
    args = build_args()
    target_address = asyncio.run(resolve_address(args.address, args.name, args.scan_timeout))
    asyncio.run(enumerate_device(target_address))
