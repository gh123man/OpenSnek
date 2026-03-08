# USB/BLE Feature Parity

This document is the single source of truth for feature parity between the USB HID protocol and BLE protocol paths in `open-snek`.

## Scope

Target device baseline:
- Basilisk V3 X HyperSpeed (`USB PID 0x00B9`, `BT PID 0x00BA`)

Transport paths:
- USB/2.4GHz: 90-byte HID report protocol
- BLE: vendor GATT (`...1524`/`...1525`) + selective HID fallback

## Parity Matrix

Legend:
- `DONE`: implemented and documented on both paths
- `PARTIAL`: implemented but transport-dependent or not fully mapped
- `USB_ONLY`: available only on USB path
- `BLE_ONLY`: available only on BLE path
- `UNKNOWN`: protocol not fully decoded

| Feature | USB Protocol | BLE Protocol | Script Support | Status | Notes |
|---|---|---|---|---|---|
| Serial read | `00:82` | observed key `01 83 00 00` | `razer_usb.py` + `razer_ble.py` (HID path) | PARTIAL | Need stable BLE vendor mapping |
| Firmware read | `00:81` | unknown vendor key | `razer_usb.py` + `razer_ble.py` (HID path) | PARTIAL | HID over BT may fail on some stacks |
| Device mode | `00:84/04` | unknown vendor key | `razer_usb.py` + `razer_ble.py` (HID path) | PARTIAL | Mode semantics known on USB only |
| DPI XY | `04:85/05` | passive HID read, HID set fallback | both scripts | PARTIAL | BLE vendor set path not fully mapped |
| DPI stages + active stage | `04:86/06` | `0B84`/`0B04`, `op=0x26` | both scripts | DONE | Fully implemented in BLE vendor path |
| Poll rate | `00:85/05` | HID fallback only | both scripts | PARTIAL | Need BLE vendor equivalent |
| Battery level | `07:80` | Battery Service + observed vendor read | both scripts | PARTIAL | Charging-state parity still incomplete on BLE |
| Idle time | `07:83/03` | unknown vendor key | both scripts (HID path) | PARTIAL | USB clamps 60..900s |
| Low battery threshold | `07:81/01` | unknown vendor key | both scripts (HID path) | PARTIAL | USB raw clamp `0x0C..0x3F` |
| Scroll mode | `02:94/14` | unknown vendor key | both scripts (HID path) | PARTIAL | USB semantics validated via OpenRazer |
| Scroll acceleration | `02:96/16` | unknown vendor key | both scripts (HID path) | PARTIAL | BLE vendor mapping missing |
| Scroll smart reel | `02:97/17` | unknown vendor key | both scripts (HID path) | PARTIAL | BLE vendor mapping missing |
| Button remapping | class `0x02`, `0x0D/0x12` family | vendor `08 04 01 <slot>` + 10-byte payload | BLE only currently | BLE_ONLY | USB button payload model not implemented yet |
| Lighting/effects | class `0x0F` (OpenRazer documented) | raw scalar lighting (`10 85`/`10 05`) | partial BLE only | PARTIAL | No cross-transport effect abstraction yet |
| Profiles | partially documented in ecosystem | unknown | none | UNKNOWN | Needs capture-backed mapping |

## Current Priorities

1. Decode BLE vendor keys for USB-equivalent controls:
- poll rate
- idle time
- low battery threshold
- scroll mode / acceleration / smart reel
- device mode / firmware / serial

2. Implement USB button remapping path:
- class `0x02` command family (`0x0D`/`0x12`), capture-backed payloads
- align action taxonomy with BLE `10-byte` payload model

3. Build common feature abstraction:
- one logical setting model with transport-specific encoders
- predictable fallback ordering per feature

## Validation Checklist

Per feature validation should include:
1. set operation ACK/success
2. read-back value match
3. persistence check after reconnect/power-cycle (when applicable)
4. behavior verification on hardware (button/scroll/lighting effects)

## References

- `USB_PROTOCOL.md`
- `BLE_PROTOCOL.md`
- `BLE_REVERSE_ENGINEERING.md`
- OpenRazer driver protocol builders (`driver/razerchromacommon.c/.h`)
