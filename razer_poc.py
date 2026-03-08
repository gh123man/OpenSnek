#!/usr/bin/env python3
"""
Compatibility wrapper for transport-specific Razer tools.

Dispatches to:
  - razer_usb.py (USB / 2.4GHz dongle)
  - razer_ble.py (Bluetooth)
"""

import os
import sys

import hid

USB_VENDOR_ID_RAZER = 0x1532
BT_VENDOR_ID_RAZER = 0x068E


def detect_transport() -> str:
    """Best-effort transport detection from connected HID interfaces."""
    has_usb = False
    has_bt = False
    for d in hid.enumerate():
        vid = d.get("vendor_id")
        name = (d.get("product_string") or "").lower()
        if vid == USB_VENDOR_ID_RAZER:
            has_usb = True
        if vid == BT_VENDOR_ID_RAZER or any(k in name for k in ("razer", "basilisk", "deathadder", "viper", "bsk")):
            # BT Razer devices often expose VID 0x068e.
            if vid == BT_VENDOR_ID_RAZER:
                has_bt = True

    if has_bt and not has_usb:
        return "ble"
    if has_usb and not has_bt:
        return "usb"
    # If both are present, prefer USB for reliability.
    if has_usb:
        return "usb"
    return "ble"


def parse_overrides(argv):
    force = None
    passthrough = []
    for a in argv:
        if a == "--force-usb":
            force = "usb"
            continue
        if a == "--force-ble":
            force = "ble"
            continue
        passthrough.append(a)
    return force, passthrough


def main() -> int:
    force, passthrough = parse_overrides(sys.argv[1:])
    transport = force or detect_transport()
    target = "razer_usb.py" if transport == "usb" else "razer_ble.py"

    script_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), target)
    if not os.path.exists(script_path):
        print(f"Missing target script: {target}")
        return 1

    os.execv(sys.executable, [sys.executable, script_path, *passthrough])
    return 0


if __name__ == "__main__":
    sys.exit(main())

