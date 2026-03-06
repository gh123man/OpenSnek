#!/usr/bin/env python3
"""
Convert raw Frida capture log (or API Monitor export) to runbook JSON artifact format.

Reads a log file with lines like:
  [DeviceIoControl] ioctl=0xXXXX inLen=20 inHex=050502064006400000...
  [GATT WRITE] char_uuid=... valueHandle=... payload_hex=...
  [CreateFileW BLE] \?\BTH...

Output: JSON with records array (time, op, service_uuid, char_uuid, handle, write_mode, value_hex).
"""
import argparse
import json
import os
import re
import sys


def parse_line(line, t_sec=0.0):
    """Parse one log line; return None or a record dict."""
    line = line.strip()
    if not line or line.startswith("[*]") or line.startswith("Failed to"):
        return None
    # [PID 1234] prefix
    pid = None
    m = re.match(r"\[PID\s+(\d+)\]\s*(.*)", line)
    if m:
        try:
            pid = int(m.group(1))
        except ValueError:
            pass
        line = m.group(2)
    rec = {"time": t_sec, "pid": pid}

    if "[DeviceIoControl]" in line:
        rec["op"] = "write"
        rec["write_mode"] = "ioctl"
        rec["service_uuid"] = ""
        rec["char_uuid"] = ""
        rec["handle"] = None
        mo = re.search(r"ioctl=0x([0-9a-fA-F]+)", line)
        if mo:
            rec["ioctl"] = "0x" + mo.group(1).lower()
        mo = re.search(r"inLen=(\d+)", line)
        if mo:
            rec["inLen"] = int(mo.group(1))
        mo = re.search(r"inHex=([0-9a-fA-F]+)", line)
        if mo:
            rec["value_hex"] = mo.group(1).lower()
        return rec

    if "[GATT WRITE]" in line:
        rec["op"] = "write"
        rec["write_mode"] = "with_response"
        rec["service_uuid"] = ""
        mo = re.search(r"char_uuid=([0-9a-fA-F]+)", line)
        if mo:
            rec["char_uuid"] = mo.group(1).lower()
        mo = re.search(r"valueHandle=(\d+)", line)
        if mo:
            rec["handle"] = int(mo.group(1))
        else:
            rec["handle"] = None
        mo = re.search(r"payload_hex=([0-9a-fA-F]+)", line)
        if mo:
            rec["value_hex"] = mo.group(1).lower()
        else:
            rec["value_hex"] = ""
        return rec

    if "[CreateFileW BLE]" in line:
        rec["op"] = "open"
        rec["path"] = line.split("]", 1)[-1].strip().split("->")[0].strip()
        rec["service_uuid"] = ""
        rec["char_uuid"] = ""
        rec["handle"] = None
        rec["write_mode"] = ""
        rec["value_hex"] = ""
        return rec

    return None


def main():
    ap = argparse.ArgumentParser(description="Parse capture log to runbook JSON")
    ap.add_argument("log_file", help="Path to capture.log or similar")
    ap.add_argument(
        "-o", "--output",
        help="Output JSON path (default: artifacts/<basename>.json)",
    )
    ap.add_argument(
        "--run",
        default=None,
        help="Run name for meta (e.g. dpi_800_to_1600)",
    )
    args = ap.parse_args()

    if not os.path.isfile(args.log_file):
        print("File not found: %s" % args.log_file, file=sys.stderr)
        sys.exit(1)

    records = []
    with open(args.log_file, "r", encoding="utf-8", errors="replace") as f:
        for i, line in enumerate(f):
            r = parse_line(line, t_sec=float(i) * 0.01)
            if r is not None:
                records.append(r)

    out_path = args.output
    if not out_path:
        os.makedirs("artifacts", exist_ok=True)
        base = os.path.splitext(os.path.basename(args.log_file))[0]
        if base.startswith("capture_"):
            base = base[8:]
        out_path = os.path.join("artifacts", base + ".json")

    run_name = args.run or os.path.splitext(os.path.basename(out_path))[0]
    meta = {"run": run_name, "source_log": args.log_file, "record_count": len(records)}
    out = {"meta": meta, "records": records}

    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2)
    print("Wrote %d records to %s" % (len(records), out_path))
    return 0


if __name__ == "__main__":
    sys.exit(main())
