#!/usr/bin/env python3
"""Safe BLE vendor-key discovery for open-snek.

Read-probes likely key ranges and optionally performs same-value write/readback
for 1-2 byte scalar keys.
"""

import argparse
import json
from typing import Dict, List, Optional, Tuple

import razer_ble


def _parse_hex_byte_list(value: str) -> List[int]:
    out: List[int] = []
    for part in value.split(","):
        p = part.strip().lower()
        if not p:
            continue
        out.append(int(p, 16))
    return out


def _parse_tail_list(value: str) -> List[bytes]:
    out: List[bytes] = []
    for part in value.split(","):
        p = part.strip().lower().replace(" ", "")
        if not p:
            continue
        if len(p) != 4:
            raise ValueError(f"tail must be 2 bytes hex (4 chars), got: {part!r}")
        out.append(bytes.fromhex(p))
    return out


def _vendor_read_raw(mouse: razer_ble.RazerMouse, key4: bytes, timeout_s: float = 1.8) -> Dict:
    req = mouse._next_bt_req()  # pylint: disable=protected-access
    cmd = bytes([req, 0x00, 0x00, 0x00]) + key4
    notifs = mouse._bt_vendor_exchange([cmd], timeout_s=timeout_s)  # pylint: disable=protected-access
    if not notifs:
        return {"ok": False, "status": None, "payload": b"", "error": "no_notify"}

    header_idx = -1
    header = None
    for i, n in enumerate(notifs):
        if len(n) == 20 and n[0] == req and n[7] in (0x02, 0x03, 0x05):
            header_idx = i
            header = n
            break
    if header is None:
        return {"ok": False, "status": None, "payload": b"", "error": "no_header"}

    expected_len = int(header[1])
    status = int(header[7])
    payload = b"".join(bytes(n) for n in notifs[header_idx + 1:] if len(n) == 20)
    if expected_len > 0:
        payload = payload[:expected_len]
    return {"ok": status == 0x02, "status": status, "payload": payload, "error": None}


def _vendor_write_scalar(
    mouse: razer_ble.RazerMouse,
    key4: bytes,
    op: int,
    value: int,
    size: int,
    timeout_s: float = 1.8,
) -> bool:
    req = mouse._next_bt_req()  # pylint: disable=protected-access
    header = bytes([req, op & 0xFF, 0x00, 0x00]) + key4
    payload = int(value).to_bytes(size, "little", signed=False)
    notifs = mouse._bt_vendor_exchange([header, payload], timeout_s=timeout_s)  # pylint: disable=protected-access
    if not notifs:
        return False
    for n in notifs:
        if len(n) == 20 and n[0] == req and n[7] == 0x02:
            return True
    return False


def _infer_set_candidates(get_key: bytes) -> List[bytes]:
    k0, k1, k2, k3 = get_key
    out = [bytes([k0, k1 & 0x7F, k2, k3])]
    if k3 != 0:
        out.append(bytes([k0, k1 & 0x7F, k2, 0x00]))
    # de-dup preserve order
    uniq: List[bytes] = []
    seen = set()
    for k in out:
        if k not in seen:
            seen.add(k)
            uniq.append(k)
    return uniq


def discover(
    mouse: razer_ble.RazerMouse,
    prefixes: List[int],
    get_codes: List[int],
    tails: List[bytes],
    verify_writeback: bool,
) -> List[Dict]:
    rows: List[Dict] = []
    for pfx in prefixes:
        for code in get_codes:
            for tail in tails:
                key = bytes([pfx & 0xFF, code & 0xFF]) + tail
                rd = _vendor_read_raw(mouse, key)
                row: Dict = {
                    "key": key.hex(),
                    "status": rd["status"],
                    "ok": rd["ok"],
                    "payload_len": len(rd["payload"]),
                    "payload_hex": rd["payload"].hex(),
                }

                if verify_writeback and rd["ok"] and len(rd["payload"]) in (1, 2):
                    size = len(rd["payload"])
                    value = int.from_bytes(rd["payload"], "little")
                    op = 0x01 if size == 1 else 0x02
                    attempts = []
                    for sk in _infer_set_candidates(key):
                        write_ok = _vendor_write_scalar(mouse, sk, op, value, size)
                        after = _vendor_read_raw(mouse, key)
                        same = bool(after["ok"] and after["payload"] == rd["payload"])
                        attempts.append(
                            {
                                "set_key": sk.hex(),
                                "write_ok": write_ok,
                                "readback_ok": after["ok"],
                                "readback_same": same,
                                "readback_hex": after["payload"].hex(),
                            }
                        )
                        if write_ok and same:
                            break
                    row["writeback"] = attempts
                rows.append(row)
    return rows


def main() -> int:
    p = argparse.ArgumentParser(description="Discover BLE vendor keys (safe read-first probing)")
    p.add_argument("--prefixes", default="00,01,02,03,04,05,07,08,0b,10")
    p.add_argument("--get-codes", default="80,81,82,83,84,85,86,87,90,91,92,93,94,95,96,97")
    p.add_argument("--tails", default="0000,0001,0100,0101")
    p.add_argument("--verify-writeback", action="store_true",
                   help="Try same-value write/readback for 1-2 byte readable keys")
    p.add_argument("--disable-vendor-gatt", action="store_true")
    p.add_argument("--output-json", default="", metavar="PATH")
    p.add_argument("--debug-hid", action="store_true")
    args = p.parse_args()

    prefixes = _parse_hex_byte_list(args.prefixes)
    get_codes = _parse_hex_byte_list(args.get_codes)
    tails = _parse_tail_list(args.tails)

    mouse = razer_ble.find_razer_mouse(
        debug_hid=args.debug_hid,
        enable_vendor_gatt=not args.disable_vendor_gatt,
    )
    if mouse is None:
        print("No Bluetooth Razer mouse found")
        return 1

    rows = discover(
        mouse,
        prefixes=prefixes,
        get_codes=get_codes,
        tails=tails,
        verify_writeback=args.verify_writeback,
    )

    supported = [r for r in rows if r.get("ok")]
    print(f"Scanned {len(rows)} keys; {len(supported)} returned success.")
    for r in supported:
        print(f"- {r['key']} len={r['payload_len']} payload={r['payload_hex']}")

    if args.output_json:
        with open(args.output_json, "w", encoding="utf-8") as f:
            json.dump(rows, f, indent=2)
        print(f"Wrote: {args.output_json}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
