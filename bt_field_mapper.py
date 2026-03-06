#!/usr/bin/env python3
"""
Analyze Bluetooth HID capture CSV from bt_report_sniffer.py.

Goal:
- map stable field behavior in RID 0x05 packets
- decode known DPI-bearing packets
- surface candidate unknown fields (battery/mode/etc.)
"""

import argparse
import csv
from collections import Counter, defaultdict
from statistics import mean
from typing import Dict, List, Tuple


def parse_hex(h: str) -> bytes:
    return bytes.fromhex(h.strip())


def fmt_set(vals: List[int]) -> str:
    if not vals:
        return "-"
    vals = sorted(vals)
    if len(vals) <= 8:
        return ",".join(f"0x{x:02x}" for x in vals)
    return f"0x{vals[0]:02x}..0x{vals[-1]:02x} (n={len(vals)})"


def load_csv(path: str) -> List[Tuple[float, bytes]]:
    rows: List[Tuple[float, bytes]] = []
    with open(path, newline="", encoding="utf-8") as f:
        r = csv.DictReader(f)
        for row in r:
            hx = row.get("hex", "")
            if not hx:
                continue
            try:
                data = parse_hex(hx)
            except Exception:
                continue
            if not data:
                continue
            try:
                t = float(row.get("ts_rel_s", "0"))
            except Exception:
                t = 0.0
            rows.append((t, data))
    return rows


def analyze_rid05(rows: List[Tuple[float, bytes]]) -> None:
    rid05 = [(t, d) for (t, d) in rows if d[0] == 0x05 and len(d) >= 9]
    if not rid05:
        print("No RID 0x05 packets found.")
        return

    print(f"RID 0x05 packets: {len(rid05)}")
    b2_counts = Counter(d[2] for _t, d in rid05)
    print("Subtype byte b2 counts:")
    for b2, n in sorted(b2_counts.items(), key=lambda x: x[0]):
        print(f"  0x{b2:02x}: {n}")

    payload_counts = Counter(d.hex() for _t, d in rid05)
    print("Top RID 0x05 payloads:")
    for h, n in payload_counts.most_common(12):
        print(f"  {n:5d}  {h}")

    dpi_packets = []
    heartbeat_packets = []
    for t, d in rid05:
        if d[2] == 0x02:
            dx = (d[3] << 8) | d[4]
            dy = (d[5] << 8) | d[6]
            dpi_packets.append((t, dx, dy, d))
        elif d[2] == 0x10:
            heartbeat_packets.append((t, d))

    if dpi_packets:
        dpi_vals = sorted({dx for _t, dx, dy, _d in dpi_packets if dx == dy})
        print("Decoded DPI values from b2=0x02 packets:")
        print("  " + ", ".join(str(v) for v in dpi_vals))

        intervals = []
        prev_t = None
        for t, _dx, _dy, _d in dpi_packets:
            if prev_t is not None:
                intervals.append(t - prev_t)
            prev_t = t
        if intervals:
            print(f"DPI packet mean inter-arrival: {mean(intervals):.3f}s")

    if heartbeat_packets:
        cols: Dict[int, set] = defaultdict(set)
        for _t, d in heartbeat_packets:
            for i in range(len(d)):
                cols[i].add(d[i])

        print("Heartbeat (b2=0x10) per-byte variability:")
        for i in range(9):
            vals = sorted(cols.get(i, set()))
            print(f"  b{i}: {fmt_set(vals)}")

    # Candidate "state bytes": bytes that vary in b2=0x02 packets and not in b2=0x10.
    if dpi_packets and heartbeat_packets:
        dpi_cols: Dict[int, set] = defaultdict(set)
        hb_cols: Dict[int, set] = defaultdict(set)
        for _t, _dx, _dy, d in dpi_packets:
            for i in range(len(d)):
                dpi_cols[i].add(d[i])
        for _t, d in heartbeat_packets:
            for i in range(len(d)):
                hb_cols[i].add(d[i])

        print("Candidate semantic bytes (vary in b2=0x02 more than b2=0x10):")
        for i in range(9):
            if len(dpi_cols[i]) > len(hb_cols[i]):
                print(
                    f"  b{i}: dpi={fmt_set(sorted(dpi_cols[i]))} "
                    f"heartbeat={fmt_set(sorted(hb_cols[i]))}"
                )

    # Candidate battery bytes:
    # heuristic: in heartbeats, values that are low-cardinality but non-constant.
    if heartbeat_packets:
        print("Battery candidates from heartbeat packets (heuristic):")
        found = False
        for i in range(3, 9):
            vals = sorted({d[i] for _t, d in heartbeat_packets})
            if 1 < len(vals) <= 6:
                found = True
                print(f"  b{i}: {fmt_set(vals)}")
        if not found:
            print("  none in this capture")


def main() -> int:
    p = argparse.ArgumentParser(description="Analyze BT HID capture CSV and map report fields.")
    p.add_argument("csv_path", help="Path to CSV produced by bt_report_sniffer.py --csv")
    args = p.parse_args()

    rows = load_csv(args.csv_path)
    if not rows:
        print("No rows loaded.")
        return 1

    print(f"Loaded rows: {len(rows)}")
    analyze_rid05(rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
