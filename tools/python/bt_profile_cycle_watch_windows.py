#!/usr/bin/env python3
"""Watch Basilisk V3 Pro BT profile-cycle HID hints on Windows.

This probe is intentionally event-driven: it does not poll the current profile.
It listens for passive HID profile-cycle reports and performs one BLE vendor
read of the hardware-active DPI surface after each debounced hint.
"""

import argparse
import asyncio
import json
import re
import subprocess
import sys
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Optional

import hid
from bleak import BleakClient
from bleak.backends.device import BLEDevice


BT_VID = 0x068E
V3_PRO_BT_PID = 0x00AC
VENDOR_SERVICE_UUID = "52401523-f97c-7f90-0e7f-6c6f4e36db1c"
VENDOR_WRITE_UUID = "52401524-f97c-7f90-0e7f-6c6f4e36db1c"
VENDOR_NOTIFY_UUID = "52401525-f97c-7f90-0e7f-6c6f4e36db1c"
LIVE_PROJECTION_DPI_TABLE_KEY = bytes([0x0B, 0x84, 0x01, 0x00])
ACTIVE_DPI_SCALAR_KEY = bytes([0x0B, 0x81, 0x00, 0x00])
ACTIVE_DPI_STAGES_KEY = bytes([0x0B, 0x82, 0x00, 0x00])
ACTIVE_DPI_STAGE_TOKEN_KEY = bytes([0x0B, 0x83, 0x00, 0x00])
BUTTON_SLOT4_GET_KEY = bytes([0x08, 0x84, 0x01, 0x04])


@dataclass
class HidReport:
    at: float
    usage_page: int
    usage: int
    data: bytes


def paired_address_from_pnp(name: str, pid: int) -> Optional[str]:
    pattern = re.compile(r"BTHLE\\DEV_([0-9A-Fa-f]{12})\\")
    cmd = [
        "powershell",
        "-NoProfile",
        "-Command",
        (
            "Get-PnpDevice -Class Bluetooth -PresentOnly | "
            f"Where-Object {{ $_.FriendlyName -like '*{name}*' -or $_.InstanceId -like '*PID&{pid:04X}*' }} | "
            "Select-Object -ExpandProperty InstanceId"
        ),
    ]
    try:
        output = subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL)
    except Exception:
        return None
    for line in output.splitlines():
        match = pattern.search(line)
        if match:
            raw = match.group(1).upper()
            return ":".join(raw[i : i + 2] for i in range(0, 12, 2))
    return None


def bt_hid_paths(pid: int) -> list[dict]:
    paths = []
    for entry in hid.enumerate(BT_VID, pid):
        name = entry.get("product_string") or ""
        usage_page = int(entry.get("usage_page") or 0)
        usage = int(entry.get("usage") or 0)
        # Ignore pointer and keyboard collections; profile hints arrived on
        # usage_page 0x01 / usage 0x00 in the capture-backed Windows sniff.
        if usage_page == 0x01 and usage in (0x02, 0x06):
            continue
        if "BSK" in name.upper() or pid == int(entry.get("product_id") or 0):
            paths.append(entry)
    return paths


def parse_dpi_table(blob: bytes) -> Optional[dict]:
    if len(blob) < 9:
        return None
    active_raw = blob[0]
    count = max(1, min(5, blob[1]))
    stages = []
    stage_ids = []
    pairs = []
    for index in range(count):
        offset = 2 + index * 7
        if offset + 4 >= len(blob):
            break
        stage_id = blob[offset]
        x = blob[offset + 1] | (blob[offset + 2] << 8)
        y = blob[offset + 3] | (blob[offset + 4] << 8)
        stage_ids.append(stage_id)
        stages.append(x)
        pairs.append([x, y])
    if not stages:
        return None
    try:
        active = stage_ids.index(active_raw)
    except ValueError:
        active = max(0, min(count - 1, active_raw - 1 if active_raw else 0))
    return {
        "active_raw": active_raw,
        "active_index": active,
        "count": count,
        "stages": stages,
        "pairs": pairs,
        "stage_ids": stage_ids,
        "raw": blob.hex(),
    }


def parse_dpi_six_byte_values(blob: bytes) -> Optional[list[int]]:
    if len(blob) not in (6, 30):
        return None
    values = []
    for offset in range(0, len(blob), 6):
        if offset + 1 < len(blob):
            values.append(blob[offset] | (blob[offset + 1] << 8))
    return values


class VendorReader:
    def __init__(self, address: str, name: str, quiet: bool = False):
        self.address = address
        self.name = name
        self.quiet = quiet
        self.req = 0x60

    def _next_req(self) -> int:
        req = self.req
        self.req = (self.req + 1) & 0xFF
        if self.req == 0:
            self.req = 1
        return req

    async def read_blob(self, key: bytes) -> dict:
        req = self._next_req()
        notifies: list[bytes] = []
        device = BLEDevice(self.address, self.name, details=None)
        async with BleakClient(
            device,
            timeout=12.0,
            services=[VENDOR_SERVICE_UUID],
        ) as client:
            def on_notify(_, data):
                notifies.append(bytes(data))

            await client.start_notify(VENDOR_NOTIFY_UUID, on_notify)
            await asyncio.sleep(0.12)
            await client.write_gatt_char(
                VENDOR_WRITE_UUID,
                bytes([req, 0x00, 0x00, 0x00]) + key,
                response=True,
            )
            await asyncio.sleep(0.75)
            await client.stop_notify(VENDOR_NOTIFY_UUID)

        header_index = None
        expected = 0
        status = None
        for index, frame in enumerate(notifies):
            if len(frame) >= 8 and frame[0] == req and frame[7] in (0x02, 0x03, 0x05):
                header_index = index
                expected = frame[1]
                status = frame[7]
                break
        payload = b""
        if status == 0x02 and header_index is not None:
            for frame in notifies[header_index + 1 :]:
                if frame:
                    payload += frame
            if expected:
                payload = payload[:expected]
        return {
            "req": req,
            "key": key.hex(),
            "status": status,
            "notifies": [frame.hex() for frame in notifies],
            "payload": payload.hex(),
        }

    async def read_fingerprint(self, include_button: bool) -> dict:
        active_scalar = await self.read_blob(ACTIVE_DPI_SCALAR_KEY)
        active_stages = await self.read_blob(ACTIVE_DPI_STAGES_KEY)
        active_token = await self.read_blob(ACTIVE_DPI_STAGE_TOKEN_KEY)
        live_projection = await self.read_blob(LIVE_PROJECTION_DPI_TABLE_KEY)
        out = {
            "active_dpi_scalar_read": active_scalar,
            "active_dpi_scalar": parse_dpi_six_byte_values(bytes.fromhex(active_scalar["payload"])),
            "active_dpi_stages_read": active_stages,
            "active_dpi_stages": parse_dpi_six_byte_values(bytes.fromhex(active_stages["payload"])),
            "active_dpi_stage_token_read": active_token,
            "active_dpi_stage_token": int(active_token["payload"], 16) if active_token["payload"] else None,
            "live_projection_dpi_read": live_projection,
            "live_projection_dpi": parse_dpi_table(bytes.fromhex(live_projection["payload"])),
        }
        if include_button:
            out["button_slot4_read"] = await self.read_blob(BUTTON_SLOT4_GET_KEY)
        return out


def hid_reader(path: bytes, usage_page: int, usage: int, start: float, stop: threading.Event, out: list[HidReport]):
    dev = None
    try:
        dev = hid.device()
        dev.open_path(path)
        dev.set_nonblocking(True)
        while not stop.is_set():
            raw = dev.read(64, timeout_ms=80)
            if raw:
                out.append(HidReport(time.time() - start, usage_page, usage, bytes(raw)))
            else:
                time.sleep(0.01)
    except Exception as exc:
        out.append(HidReport(time.time() - start, usage_page, usage, f"ERROR:{type(exc).__name__}:{exc}".encode()))
    finally:
        if dev is not None:
            try:
                dev.close()
            except Exception:
                pass


def is_profile_hint(data: bytes) -> bool:
    return data.startswith(bytes([0x04, 0x04])) or data.startswith(bytes([0x05, 0x05, 0x39]))


async def run(args: argparse.Namespace) -> int:
    address = args.address or paired_address_from_pnp(args.name, args.pid)
    if not address:
        print("Could not resolve paired BLE address; pass --address FA:2E:1F:48:66:38", file=sys.stderr)
        return 2

    paths = bt_hid_paths(args.pid)
    if not paths:
        print("No matching Bluetooth HID paths found", file=sys.stderr)
        return 2

    output_path = Path(args.output) if args.output else None
    events = []
    reports: list[HidReport] = []
    stop = threading.Event()
    start = time.time()
    threads = []
    for entry in paths:
        thread = threading.Thread(
            target=hid_reader,
            args=(
                entry["path"],
                int(entry.get("usage_page") or 0),
                int(entry.get("usage") or 0),
                start,
                stop,
                reports,
            ),
            daemon=True,
        )
        threads.append(thread)
        thread.start()
        print(f"opened usage_page=0x{int(entry.get('usage_page') or 0):02x} usage=0x{int(entry.get('usage') or 0):02x}")

    reader = VendorReader(address, args.name)
    print(f"watching {args.seconds:.1f}s address={address}; press the profile button now")
    baseline = await reader.read_fingerprint(include_button=args.button_slot4)
    print("baseline", json.dumps({
        "active_dpi_scalar": baseline["active_dpi_scalar"],
        "active_dpi_stages": baseline["active_dpi_stages"],
        "active_dpi_stage_token": baseline["active_dpi_stage_token"],
        "live_projection_dpi": baseline["live_projection_dpi"],
        "button_slot4": baseline.get("button_slot4_read", {}).get("payload"),
    }, separators=(",", ":")))
    events.append({"type": "baseline", "at": 0.0, "read": baseline})

    last_hint_at = -999.0
    handled_report_count = 0
    deadline = start + args.seconds
    try:
        while time.time() < deadline:
            while handled_report_count < len(reports):
                report = reports[handled_report_count]
                handled_report_count += 1
                event = {
                    "type": "hid",
                    "at": report.at,
                    "usage_page": report.usage_page,
                    "usage": report.usage,
                    "hex": report.data.hex(),
                }
                events.append(event)
                if args.verbose or is_profile_hint(report.data):
                    print(
                        f"{report.at:7.3f}s hid usage_page=0x{report.usage_page:02x} "
                        f"usage=0x{report.usage:02x} {report.data.hex()}"
                    )
                if is_profile_hint(report.data) and report.at - last_hint_at >= args.debounce:
                    last_hint_at = report.at
                    if args.read_delay > 0:
                        await asyncio.sleep(args.read_delay)
                    read_start = time.time()
                    read = await reader.read_fingerprint(include_button=args.button_slot4)
                    elapsed = time.time() - read_start
                    read_event = {
                        "type": "dpi-read-after-hint",
                        "at": time.time() - start,
                        "trigger": report.data.hex(),
                        "elapsed": elapsed,
                        "read": read,
                    }
                    events.append(read_event)
                    print(
                        f"{time.time() - start:7.3f}s one-shot active-dpi-read "
                        f"elapsed={elapsed:.3f}s trigger={report.data.hex()} "
                        f"active_stages={read['active_dpi_stages']} "
                        f"active_scalar={read['active_dpi_scalar']} "
                        f"active_token={read['active_dpi_stage_token']} "
                        f"live_projection={json.dumps(read['live_projection_dpi'], separators=(',', ':'))} "
                        f"button_slot4={read.get('button_slot4_read', {}).get('payload')}"
                    )
            await asyncio.sleep(0.03)
    finally:
        stop.set()
        for thread in threads:
            thread.join(timeout=0.5)

    result = {
        "address": address,
        "name": args.name,
        "seconds": args.seconds,
        "debounce": args.debounce,
        "events": events,
    }
    if output_path:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
        print(f"wrote {output_path}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", default="BSK V3 PRO")
    parser.add_argument("--pid", type=lambda s: int(s, 0), default=V3_PRO_BT_PID)
    parser.add_argument("--address", help="Paired BLE address, e.g. FA:2E:1F:48:66:38")
    parser.add_argument("--seconds", type=float, default=60.0)
    parser.add_argument("--debounce", type=float, default=0.65)
    parser.add_argument("--read-delay", type=float, default=0.0, help="Delay after a HID hint before the one-shot read")
    parser.add_argument("--button-slot4", action="store_true", help="Also read button slot 0x04 as a fingerprint axis")
    parser.add_argument("--output", help="Write JSON event log")
    parser.add_argument("--verbose", action="store_true", help="Print all HID reports, not only profile hints")
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
