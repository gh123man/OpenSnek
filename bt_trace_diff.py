#!/usr/bin/env python3
"""
Diff two Wireshark CSV exports to isolate BLE ATT write/notify payloads.

Expected input:
- CSV exported from Wireshark with at least some of:
  frame.time_relative, btatt.opcode, btatt.handle, btatt.uuid16, btatt.value
- field names vary by Wireshark profile; this script tries multiple aliases.
"""

import argparse
import csv
from collections import Counter
from dataclasses import dataclass
from typing import Dict, Iterable, List, Optional


FIELD_ALIASES = {
    "time": ["frame.time_relative", "Time", "time", "frame_time_relative"],
    "opcode": ["btatt.opcode", "ATT Opcode", "opcode", "btatt_opcode"],
    "handle": ["btatt.handle", "Handle", "handle", "btatt_handle"],
    "uuid16": ["btatt.uuid16", "UUID16", "uuid16"],
    "value": ["btatt.value", "Value", "value", "btatt_value"],
    "info": ["_ws.col.Info", "Info", "info"],
}


@dataclass(frozen=True)
class Row:
    opcode: str
    handle: str
    uuid16: str
    value: str
    info: str
    time: float


def pick(row: Dict[str, str], aliases: Iterable[str]) -> str:
    for k in aliases:
        if k in row and row[k] is not None:
            return str(row[k]).strip()
    return ""


def parse_time(s: str) -> float:
    try:
        return float(s)
    except Exception:
        return 0.0


def load_rows(path: str) -> List[Row]:
    out: List[Row] = []
    with open(path, newline="", encoding="utf-8") as f:
        r = csv.DictReader(f)
        for raw in r:
            row = Row(
                opcode=pick(raw, FIELD_ALIASES["opcode"]).lower(),
                handle=pick(raw, FIELD_ALIASES["handle"]).lower(),
                uuid16=pick(raw, FIELD_ALIASES["uuid16"]).lower(),
                value=pick(raw, FIELD_ALIASES["value"]).lower().replace(":", "").replace(" ", ""),
                info=pick(raw, FIELD_ALIASES["info"]).lower(),
                time=parse_time(pick(raw, FIELD_ALIASES["time"])),
            )
            if not any([row.opcode, row.handle, row.uuid16, row.value, row.info]):
                continue
            out.append(row)
    return out


def is_write(row: Row) -> bool:
    t = f"{row.opcode} {row.info}"
    return ("0x12" in t) or ("0x52" in t) or ("write request" in t) or ("write command" in t)


def is_notify(row: Row) -> bool:
    t = f"{row.opcode} {row.info}"
    return ("0x1b" in t) or ("0x1d" in t) or ("notification" in t) or ("indication" in t)


def key_for(row: Row) -> str:
    # Primary grouping by handle + value.
    return f"h={row.handle or '?'}|u={row.uuid16 or '?'}|v={row.value or '?'}"


def summarize(rows: List[Row], title: str) -> None:
    writes = [r for r in rows if is_write(r)]
    notifs = [r for r in rows if is_notify(r)]
    print(f"\n{title}")
    print(f"  total rows: {len(rows)}")
    print(f"  write-like rows: {len(writes)}")
    print(f"  notify-like rows: {len(notifs)}")

    wc = Counter(key_for(r) for r in writes)
    nc = Counter(key_for(r) for r in notifs)
    if wc:
        print("  top writes:")
        for k, n in wc.most_common(8):
            print(f"    {n:4d}  {k}")
    if nc:
        print("  top notifies:")
        for k, n in nc.most_common(8):
            print(f"    {n:4d}  {k}")


def diff(before: List[Row], after: List[Row]) -> None:
    bw = Counter(key_for(r) for r in before if is_write(r))
    aw = Counter(key_for(r) for r in after if is_write(r))
    bn = Counter(key_for(r) for r in before if is_notify(r))
    an = Counter(key_for(r) for r in after if is_notify(r))

    print("\nCandidate NEW writes in AFTER:")
    new_w = [(k, aw[k]) for k in aw if bw[k] == 0]
    if not new_w:
        print("  none")
    else:
        for k, n in sorted(new_w, key=lambda x: x[1], reverse=True)[:20]:
            print(f"  {n:4d}  {k}")

    print("\nCandidate CHANGED write frequencies:")
    deltas = []
    for k in set(aw) | set(bw):
        d = aw[k] - bw[k]
        if d != 0:
            deltas.append((k, d, bw[k], aw[k]))
    if not deltas:
        print("  none")
    else:
        for k, d, b, a in sorted(deltas, key=lambda x: abs(x[1]), reverse=True)[:20]:
            print(f"  delta={d:+4d} before={b:4d} after={a:4d}  {k}")

    print("\nCandidate NEW notifications in AFTER:")
    new_n = [(k, an[k]) for k in an if bn[k] == 0]
    if not new_n:
        print("  none")
    else:
        for k, n in sorted(new_n, key=lambda x: x[1], reverse=True)[:20]:
            print(f"  {n:4d}  {k}")


def main() -> int:
    p = argparse.ArgumentParser(description="Diff BLE ATT traces from Wireshark CSV exports")
    p.add_argument("before_csv", help="Baseline trace CSV")
    p.add_argument("after_csv", help="Changed-setting trace CSV")
    args = p.parse_args()

    before = load_rows(args.before_csv)
    after = load_rows(args.after_csv)
    summarize(before, "BEFORE")
    summarize(after, "AFTER")
    diff(before, after)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
