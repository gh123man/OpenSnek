# Claude Code Instructions

## Project Overview

**open-snek** configures Razer mice without Synapse.

- USB/2.4GHz: strong coverage (`tools/python/razer_usb.py`)
- BLE: vendor GATT + HID fallback path (`tools/python/razer_ble.py`)

## Key Files

| File | Purpose |
|------|---------|
| `tools/python/razer_poc.py` | Transport wrapper CLI (auto USB/BLE selection) |
| `tools/python/razer_usb.py` | USB/2.4GHz configuration path |
| `tools/python/razer_ble.py` | BLE configuration path and helpers |
| `tools/python/ble_battery.py` | BLE Battery Service reader (macOS CoreBluetooth) |
| `tools/python/explore_ble.py` | BLE service/characteristic exploration |
| `tools/python/enumerate_hid_gatt.py` | HID-over-GATT enumeration helper |
| `tools/python/enumerate_hid_gatt_linux.py` | Linux HID-over-GATT probing helper |
| `captures/` | BLE capture corpus and index |
| `docs/protocol/PROTOCOL.md` | Protocol documentation index |
| `docs/protocol/USB_PROTOCOL.md` | USB protocol details |
| `docs/protocol/BLE_PROTOCOL.md` | BLE protocol + implementation mapping |
| `docs/research/BLE_REVERSE_ENGINEERING.md` | Reverse engineering notes and timeline |

## Important: Protocol Documentation

Read `docs/protocol/PROTOCOL.md` first for links to USB and BLE protocol specs.

## Current State

### Working
- USB: DPI read/write, stage read/write, poll rate, battery
- BLE: vendor-GATT DPI stage read/write, button bind writes, raw power/sleep/lighting writes, battery service fallback, passive DPI sniff/read

### Partial / In Progress
- BLE direct HID command path behavior varies by OS/backend (especially poll-rate and direct DPI commands)
- Full key catalog for remaining vendor commands still in progress

## Development Guidelines

1. Read `docs/protocol/PROTOCOL.md` before protocol changes.
2. Document newly decoded commands before broad API changes.
3. Validate changes on real hardware; BLE can require power-cycle recovery.
4. USB path uses 90-byte HID reports.
5. BLE vendor path uses `...1524` writes and `...1525` notifications.

## References

- [OpenRazer](https://github.com/openrazer/openrazer)
- [OpenRazer Protocol Wiki](https://github.com/openrazer/openrazer/wiki/Reverse-Engineering-USB-Protocol)
- [razer-macos](https://github.com/1kc/razer-macos)
- [RazerBlackWidowV3MiniBluetoothControllerApp](https://github.com/JiqiSun/RazerBlackWidowV3MiniBluetoothControllerApp)
