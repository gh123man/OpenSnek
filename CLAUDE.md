# Claude Code Instructions

This file provides context and instructions for Claude Code when working on this project.

## Project Overview

This is a **Razer Mouse macOS Configuration Tool** - a Python-based utility that communicates with Razer mice via USB HID to configure settings without Razer Synapse.

### Key Files

| File | Purpose |
|------|---------|
| `razer_poc.py` | Main CLI tool for configuring mice |
| `explore_ble.py` | BLE exploration script (experimental) |
| `PROTOCOL.md` | **USB protocol documentation - ALWAYS REFERENCE THIS** |
| `README.md` | User-facing documentation |
| `requirements.txt` | Python dependencies |

## Important: Protocol Documentation

**ALWAYS read `PROTOCOL.md` before making protocol-related changes.**

This file documents:
- The 90-byte USB HID report structure
- All known command classes and command IDs
- Device-specific transaction IDs
- What IS and IS NOT implemented
- References to OpenRazer for deeper research

### When to Update PROTOCOL.md

Update the protocol documentation when:
1. **New commands are discovered** via USB capture or testing
2. **New devices are tested** with different transaction IDs or behaviors
3. **Bugs are found** in the documented protocol
4. **OpenRazer adds new features** that we should track

## Architecture

```
┌─────────────────┐
│  razer_poc.py   │  CLI interface
├─────────────────┤
│   RazerMouse    │  Device abstraction class
│   - get_dpi()   │
│   - set_dpi()   │
│   - etc.        │
├─────────────────┤
│  _send_command  │  USB HID communication via hidapi
│  _create_report │  90-byte report construction
└─────────────────┘
```

## Current Capabilities

### Implemented ✅
- DPI read/write
- DPI stages read/write (1-5 presets)
- Poll rate read/write (125/500/1000 Hz)
- Battery level read
- Device enumeration

### Not Implemented ❌
- Button remapping (protocol partially known, needs USB capture)
- RGB lighting control (documented in OpenRazer)
- Profile/onboard memory management (undocumented)
- Macro support (undocumented)

## Development Guidelines

### Adding New Commands

1. **Research**: Check `PROTOCOL.md` and OpenRazer source
2. **Document**: Add command to `PROTOCOL.md` BEFORE implementing
3. **Implement**: Add method to `RazerMouse` class
4. **Test**: Verify with actual hardware
5. **Update docs**: Mark as implemented in `PROTOCOL.md`

### Testing

```bash
cd /Users/brian/dev/razer-macos-poc
source venv/bin/activate
python razer_poc.py           # Show current settings
python razer_poc.py --help    # Show all options
```

### USB Capture for Reverse Engineering

To discover new commands:
1. Set up Windows VM with Razer Synapse
2. Use Wireshark with USBPcap
3. Capture while using Synapse features
4. Analyze 90-byte feature reports
5. Document findings in `PROTOCOL.md`

## Key Technical Details

### Transaction IDs
- Basilisk V3 X HyperSpeed: `0x1F`
- Most modern mice: `0x1F` or `0x3F`
- Older devices: `0xFF`

### Bluetooth Limitation
Bluetooth HID does NOT support the configuration protocol. USB dongle or cable required.

### Storage Modes
- `NOSTORE (0x00)`: Apply immediately, don't persist
- `VARSTORE (0x01)`: Apply and save to device memory

## Related Resources

- [OpenRazer](https://github.com/openrazer/openrazer) - Linux driver, protocol reference
- [OpenRazer Wiki](https://github.com/openrazer/openrazer/wiki/Reverse-Engineering-USB-Protocol)
- [razer-macos](https://github.com/1kc/razer-macos) - macOS RGB tool using IOKit

## Contact

This project was created with assistance from Claude (Anthropic). The protocol documentation is based on OpenRazer's reverse engineering work.
