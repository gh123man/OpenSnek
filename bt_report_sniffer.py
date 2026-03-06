#!/usr/bin/env python3
"""
Bluetooth HID report sniffer for Razer mice on macOS.

This captures raw input reports and applies best-effort decoding for known
9-byte report formats observed on BLE Razer mice.
"""

import argparse
import csv
import sys
import time
from collections import Counter
from datetime import datetime
from typing import Dict, List, Optional, Tuple

import hid


DEFAULT_VID = 0x068E
DEFAULT_PID = 0x00BA


def fmt_hex(data: bytes) -> str:
    return data.hex()


def int16_le(lo: int, hi: int) -> int:
    v = (hi << 8) | lo
    if v & 0x8000:
        return v - 0x10000
    return v


def decode_report(data: bytes) -> str:
    if not data:
        return "empty"

    rid = data[0]

    # Common 9-byte mouse report we observed on this device:
    # [0]=report_id, [1]=buttons, [2..4]=unknown/reserved?, [5..6]=x, [7..8]=y
    if rid == 0x01 and len(data) >= 9:
        buttons = data[1]
        dx = int16_le(data[5], data[6])
        dy = int16_le(data[7], data[8])
        return (
            f"rid=0x01 buttons=0x{buttons:02x} "
            f"dx={dx:+d} dy={dy:+d} "
            f"u2=0x{data[2]:02x} u3=0x{data[3]:02x} u4=0x{data[4]:02x}"
        )

    # Common status frame on this BT mouse.
    if rid == 0x05 and len(data) >= 7:
        if data[2] == 0x02:
            dpi_x = (data[3] << 8) | data[4]
            dpi_y = (data[5] << 8) | data[6]
            if 100 <= dpi_x <= 30000 and 100 <= dpi_y <= 30000:
                return f"rid=0x05 dpi_report dpi_x={dpi_x} dpi_y={dpi_y}"

    if rid == 0x05 and len(data) >= 3:
        return (
            f"rid=0x05 status? b1=0x{data[1]:02x} b2=0x{data[2]:02x} "
            f"tail={fmt_hex(data[3:])}"
        )

    return f"rid=0x{rid:02x} len={len(data)}"


def find_device_path(vid: int, pid: int) -> Optional[bytes]:
    devices = hid.enumerate(vid, pid)
    if not devices:
        return None
    return devices[0]["path"]


def build_guided_steps(step_seconds: float) -> List[Tuple[str, str, float]]:
    return [
        ("idle_1", "Stay idle (baseline)", step_seconds),
        ("move", "Move the mouse in circles", step_seconds),
        ("left_click", "Click left and right buttons", step_seconds),
        ("scroll", "Scroll wheel up/down quickly", step_seconds),
        ("dpi_button", "Press the DPI button repeatedly", step_seconds),
        ("idle_2", "Stay idle again", step_seconds),
    ]


def guided_phase_at(elapsed: float, steps: List[Tuple[str, str, float]]) -> str:
    t = 0.0
    for name, _hint, dur in steps:
        if elapsed < (t + dur):
            return name
        t += dur
    return "post"


def analyze_guided(phases: Dict[str, List[bytes]]) -> None:
    print("\nGuided phase analysis")
    baseline = phases.get("idle_1", [])
    baseline_by_rid: Dict[int, List[bytes]] = {}
    for pkt in baseline:
        if not pkt:
            continue
        baseline_by_rid.setdefault(pkt[0], []).append(pkt)

    for phase_name, packets in phases.items():
        if phase_name == "post":
            continue
        print(f"\nPhase: {phase_name} packets={len(packets)}")
        if not packets:
            continue

        rid_groups: Dict[int, List[bytes]] = {}
        for pkt in packets:
            if not pkt:
                continue
            rid_groups.setdefault(pkt[0], []).append(pkt)

        for rid, vals in sorted(rid_groups.items(), key=lambda x: x[0]):
            unique_vals = set(vals)
            print(f"  RID 0x{rid:02x}: count={len(vals)} unique={len(unique_vals)}")

            # Compare this phase to idle baseline on a byte-position basis.
            base_vals = baseline_by_rid.get(rid, [])
            if not base_vals:
                continue

            max_len = max(max(len(v) for v in vals), max(len(v) for v in base_vals))
            changed_positions = []
            for idx in range(max_len):
                here = {v[idx] for v in vals if idx < len(v)}
                base = {v[idx] for v in base_vals if idx < len(v)}
                if here != base:
                    changed_positions.append((idx, sorted(base), sorted(here)))

            if changed_positions:
                print("    Byte deltas vs idle_1:")
                for idx, base_set, here_set in changed_positions[:12]:
                    def fmt_set(vals: List[int]) -> str:
                        if not vals:
                            return "-"
                        if len(vals) <= 8:
                            return ",".join(f"0x{x:02x}" for x in vals)
                        head = ",".join(f"0x{x:02x}" for x in vals[:3])
                        tail = ",".join(f"0x{x:02x}" for x in vals[-3:])
                        return f"{head}..{tail} (n={len(vals)})"

                    print(
                        f"      b{idx}: idle={fmt_set(base_set)} "
                        f"phase={fmt_set(here_set)}"
                    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Sniff BLE HID reports from a Razer mouse and decode fields."
    )
    parser.add_argument("--vid", type=lambda x: int(x, 0), default=DEFAULT_VID, help="Vendor ID (default: 0x068e)")
    parser.add_argument("--pid", type=lambda x: int(x, 0), default=DEFAULT_PID, help="Product ID (default: 0x00ba)")
    parser.add_argument("--duration", type=float, default=30.0, help="Capture duration in seconds")
    parser.add_argument("--report-len", type=int, default=64, help="Max bytes per read()")
    parser.add_argument("--timeout-ms", type=int, default=120, help="read() timeout in ms")
    parser.add_argument("--csv", type=str, default="", help="Optional CSV output path")
    parser.add_argument("--quiet", action="store_true", help="Suppress per-packet lines, print summary only")
    parser.add_argument("--guided", action="store_true", help="Run scripted action phases and print per-phase byte deltas")
    parser.add_argument("--step-seconds", type=float, default=4.0, help="Seconds per guided phase (default: 4)")
    args = parser.parse_args()

    path = find_device_path(args.vid, args.pid)
    if path is None:
        print(f"No HID device found for VID:PID 0x{args.vid:04x}:0x{args.pid:04x}")
        return 1

    print(f"Opening HID path: {path!r}")
    if args.guided:
        steps = build_guided_steps(args.step_seconds)
        total = sum(s[2] for s in steps)
        print(f"Guided mode enabled (total {total:.1f}s).")
        for i, (name, hint, dur) in enumerate(steps, start=1):
            print(f"  {i}. {name:10s} {dur:4.1f}s - {hint}")
        print("Follow the prompts below as phase names change.")
    else:
        print(
            "Suggested actions now: move mouse, left/right click, scroll wheel, "
            "press DPI button, then stay idle for a few seconds."
        )
    print()

    def open_dev() -> Optional[hid.device]:
        d = hid.device()
        try:
            d.open_path(path)
            d.set_nonblocking(True)
            return d
        except Exception:
            try:
                d.close()
            except Exception:
                pass
            return None

    dev = open_dev()
    if dev is None:
        print("Failed to open HID path")
        return 1

    csv_writer = None
    csv_file = None
    if args.csv:
        csv_file = open(args.csv, "w", newline="", encoding="utf-8")
        csv_writer = csv.writer(csv_file)
        csv_writer.writerow(["ts_iso", "ts_rel_s", "len", "hex", "decode"])

    start = time.time()
    packets = 0
    by_rid = Counter()
    top_payloads = Counter()
    phase_packets: Dict[str, List[bytes]] = {}
    last_phase = None

    read_errors = 0
    reconnects = 0
    try:
        while (time.time() - start) < args.duration:
            try:
                raw = dev.read(args.report_len, timeout_ms=args.timeout_ms)
            except OSError:
                read_errors += 1
                # Transient BLE HID read faults happen; keep capturing.
                time.sleep(0.05)
                if read_errors >= 12:
                    reconnects += 1
                    read_errors = 0
                    try:
                        dev.close()
                    except Exception:
                        pass
                    dev = open_dev()
                    if dev is None:
                        print("Too many read errors; reconnect failed, stopping capture early.")
                        break
                    print(f"Recovered from read errors by reopening HID ({reconnects}).")
                continue
            rel = time.time() - start
            if args.guided:
                phase = guided_phase_at(rel, steps)
                if phase != last_phase:
                    phase_hint = ""
                    for name, hint, _dur in steps:
                        if name == phase:
                            phase_hint = hint
                            break
                    if phase != "post":
                        print(f"[phase] {phase}: {phase_hint}")
                    last_phase = phase
            else:
                phase = "unguided"

            if not raw:
                continue

            data = bytes(raw)
            ts = datetime.now().isoformat(timespec="milliseconds")
            decoded = decode_report(data)

            packets += 1
            rid = data[0]
            by_rid[rid] += 1
            top_payloads[data] += 1
            phase_packets.setdefault(phase, []).append(data)

            if not args.quiet:
                print(f"{packets:05d} t={rel:7.3f}s len={len(data):2d} {fmt_hex(data)}  |  {decoded}")

            if csv_writer is not None:
                csv_writer.writerow([ts, f"{rel:.6f}", len(data), fmt_hex(data), decoded])
    finally:
        dev.close()
        if csv_file is not None:
            csv_file.close()

    print("\nCapture complete")
    print(f"Packets: {packets}")
    if read_errors:
        print(f"Read errors: {read_errors}")
    if reconnects:
        print(f"Reconnects: {reconnects}")
    if packets == 0:
        return 0

    print("Report ID counts:")
    for rid, count in sorted(by_rid.items(), key=lambda x: x[0]):
        print(f"  0x{rid:02x}: {count}")

    print("Top payloads:")
    for payload, count in top_payloads.most_common(10):
        print(f"  {count:5d}  {fmt_hex(payload)}")

    if args.csv:
        print(f"CSV written: {args.csv}")
    if args.guided:
        analyze_guided(phase_packets)

    return 0


if __name__ == "__main__":
    sys.exit(main())
