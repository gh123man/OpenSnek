# Python Tooling

These scripts remain supported, but they are secondary to the macOS app in `OpenSnek/`.

## Setup

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r tools/python/requirements.txt
```

## Main Entry Points

```bash
# Auto transport
python3 tools/python/razer_poc.py

# Force transport
python3 tools/python/razer_poc.py --force-usb
python3 tools/python/razer_poc.py --force-ble
```

## Direct Tool Examples

```bash
python3 tools/python/razer_usb.py --dpi 1600
python3 tools/python/razer_ble.py --single-dpi 1600
python3 tools/python/discover_bt_vendor_keys.py
```

## Related Docs

- Protocol index: `docs/protocol/PROTOCOL.md`
- BLE reverse-engineering notes: `docs/research/BLE_REVERSE_ENGINEERING.md`
