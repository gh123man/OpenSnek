#!/usr/bin/env python3
"""
Diff two runbook JSON artifacts (e.g. baseline vs dpi_800_to_1600) to find
candidate BLE write payloads that correlate with a setting change.

Usage:
  python diff_artifacts.py artifacts/baseline.json artifacts/dpi_800_to_1600.json
"""
import argparse
import json
import sys
from collections import Counter


def load_artifact(path):
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data.get("records", []), data.get("meta", {})


def key(r):
    """Stable key for grouping writes (ignore time)."""
    return (
        r.get("op"),
        r.get("char_uuid") or "",
        r.get("ioctl") or "",
        r.get("value_hex", "")[:64],
    )


def key_full(r):
    """Full key including value for exact match."""
    return (
        r.get("op"),
        r.get("char_uuid") or "",
        r.get("ioctl") or "",
        r.get("value_hex", ""),
    )


def main():
    ap = argparse.ArgumentParser(description="Diff runbook JSON artifacts")
    ap.add_argument("baseline_json", help="Baseline artifact (e.g. artifacts/baseline.json)")
    ap.add_argument("changed_json", help="One-change artifact (e.g. artifacts/dpi_800_to_1600.json)")
    ap.add_argument(
        "--min-len",
        type=int,
        default=4,
        help="Min value_hex length to consider (default 4)",
    )
    args = ap.parse_args()

    base_recs, base_meta = load_artifact(args.baseline_json)
    chg_recs, chg_meta = load_artifact(args.changed_json)

    base_writes = [r for r in base_recs if r.get("op") == "write" and len((r.get("value_hex") or "")) >= args.min_len]
    chg_writes = [r for r in chg_recs if r.get("op") == "write" and len((r.get("value_hex") or "")) >= args.min_len]

    base_by_key = Counter(key(r) for r in base_writes)
    chg_by_key = Counter(key(r) for r in chg_writes)
    base_full = set(key_full(r) for r in base_writes)
    chg_full_set = set(key_full(r) for r in chg_writes)

    print("Baseline: %s  writes=%d" % (args.baseline_json, len(base_writes)))
    print("Changed:  %s  writes=%d" % (args.changed_json, len(chg_writes)))
    print()

    # New payloads in changed (exact value not seen in baseline)
    new_payloads = [r for r in chg_writes if key_full(r) not in base_full]
    if new_payloads:
        print("Candidate NEW write payloads (not in baseline):")
        seen = set()
        for r in new_payloads:
            k = (r.get("char_uuid"), r.get("ioctl"), r.get("value_hex"))
            if k in seen:
                continue
            seen.add(k)
            print("  char_uuid=%s ioctl=%s handle=%s" % (r.get("char_uuid") or "", r.get("ioctl") or "", r.get("handle")))
            print("    value_hex=%s" % (r.get("value_hex") or ""))
            print()
    else:
        print("No new unique payloads (may be frequency diff only).")

    # Frequency increase: same key, more often in changed
    print()
    print("Write frequency change (key -> baseline count, changed count):")
    all_keys = set(base_by_key) | set(chg_by_key)
    deltas = [(k, base_by_key[k], chg_by_key[k], chg_by_key[k] - base_by_key[k]) for k in all_keys]
    deltas.sort(key=lambda x: -abs(x[3]))
    for k, b, c, d in deltas[:15]:
        if d == 0:
            continue
        op, cu, io, val = k
        print("  delta=%+d  base=%d chg=%d  char_uuid=%s ioctl=%s value_prefix=%s" % (
            d, b, c, cu or "-", io or "-", (val[:24] + "..") if len(val) > 24 else val,
        ))

    # DPI heuristic: look for 0x0320 (800) / 0x0640 (1600) in hex
    print()
    print("Payloads containing possible DPI-like bytes (0x0320=800, 0x0640=1600):")
    for r in chg_writes:
        h = (r.get("value_hex") or "").lower()
        if "0320" in h or "0640" in h:
            print("  %s" % (r.get("value_hex") or ""))

    return 0


if __name__ == "__main__":
    sys.exit(main())
