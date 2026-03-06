#!/usr/bin/env python3
"""
Try to extract DeviceIoControl / BLE-related payloads from an API Monitor .apmx64 capture.

The .apmx64 format is proprietary binary. This script:
1. Scans for the DPI report byte pattern 05 05 02 (and 03 20 / 06 40 for 800/1600).
2. Scans for short buffers (8-128 bytes) that could be GATT writes.
3. Dumps any findings as candidate payloads for the runbook.

Usage:
  python parse_apmx64.py dpi.apmx64
  python parse_apmx64.py dpi.apmx64 -o artifacts/dpi_candidates.json
"""
import argparse
import json
import sys
from pathlib import Path


def find_sequence(data: bytes, seq: bytes, max_results: int = 50):
    """Yield (offset, context_bytes) for each occurrence of seq in data."""
    i = 0
    n = 0
    while n < max_results and i < len(data) - len(seq):
        pos = data.find(seq, i)
        if pos == -1:
            break
        start = max(0, pos - 2)
        end = min(len(data), pos + len(seq) + 8)
        yield pos, data[start:end].hex()
        i = pos + 1
        n += 1


def find_dpi_like(data: bytes):
    """Look for 05 05 02 XX YY XX YY (DPI report style) or 06 40 / 03 20 in plausible contexts."""
    results = []
    # DPI report prefix from runbook: 05 05 02 then two 2-byte big-endian values
    for offset, ctx in find_sequence(data, bytes([0x05, 0x05, 0x02]), max_results=20):
        if len(ctx) >= 16:  # at least 8 bytes of context
            results.append({"offset": offset, "pattern": "05_05_02", "context_hex": ctx})
    # 06 40 = 1600 in big-endian (DPI value)
    for offset, ctx in find_sequence(data, bytes([0x06, 0x40]), max_results=30):
        results.append({"offset": offset, "pattern": "06_40_1600", "context_hex": ctx})
    # 03 20 = 800 in big-endian
    for offset, ctx in find_sequence(data, bytes([0x03, 0x20]), max_results=30):
        results.append({"offset": offset, "pattern": "03_20_800", "context_hex": ctx})
    return results


def extract_ascii_strings(data: bytes, min_len: int = 8):
    """Extract printable ASCII strings that might be API names or hex."""
    current = []
    strings = []
    for b in data:
        if 32 <= b <= 126:
            current.append(chr(b))
        else:
            if len(current) >= min_len:
                s = "".join(current)
                if "DeviceIoControl" in s or "lpInBuffer" in s or "IoControl" in s:
                    strings.append(s[:200])
            current = []
    if len(current) >= min_len:
        strings.append("".join(current)[:200])
    return strings


def main():
    ap = argparse.ArgumentParser(description="Extract candidate BLE/DPI payloads from .apmx64 capture")
    ap.add_argument("apmx64_file", help="Path to .apmx64 capture file")
    ap.add_argument("-o", "--output", help="Write findings to JSON file")
    ap.add_argument("--strings", action="store_true", help="Also dump API-related ASCII strings")
    args = ap.parse_args()

    path = Path(args.apmx64_file)
    if not path.is_file():
        print("File not found:", path, file=sys.stderr)
        return 1

    data = path.read_bytes()
    print(f"Read {len(data)} bytes from {path.name}")

    findings = find_dpi_like(data)
    print(f"\nFound {len(findings)} pattern matches (05 05 02, 06 40, 03 20):")
    for i, f in enumerate(findings[:15]):
        print(f"  [{i}] {f['pattern']} @ offset {f['offset']}: {f['context_hex']}")

    if args.strings:
        strings = extract_ascii_strings(data)
        print(f"\nAPI-related strings: {len(strings)}")
        for s in strings[:10]:
            print(f"  {s[:100]}...")

    out = {
        "source": str(path),
        "file_size": len(data),
        "candidates": findings,
    }
    if args.output:
        out_path = Path(args.output)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(out, f, indent=2)
        print(f"\nWrote {len(findings)} candidates to {out_path}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
