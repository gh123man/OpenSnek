#!/usr/bin/env python3
"""
Minimal BLE GATT write/notify runner for reverse engineering.

Use cases:
- list services/characteristics for a target device
- subscribe to notifications
- write raw hex payloads to candidate characteristics
"""

import argparse
import asyncio
from typing import Optional

from bleak import BleakClient, BleakScanner


def hex_to_bytes(s: str) -> bytes:
    s = s.strip().replace(" ", "").replace(":", "")
    if s.startswith("0x"):
        s = s[2:]
    if len(s) % 2 != 0:
        raise ValueError("hex payload length must be even")
    return bytes.fromhex(s)


async def resolve_device(target: str):
    """
    Resolve by exact address/UUID or substring match on name.
    """
    devices = await BleakScanner.discover(timeout=10.0, return_adv=True)
    target_l = target.lower()

    # Exact address/UUID match first.
    for dev, _adv in devices.values():
        if dev.address.lower() == target_l:
            return dev

    # Name contains fallback.
    for dev, adv in devices.values():
        name = (dev.name or adv.local_name or "").lower()
        if target_l in name:
            return dev
    return None


async def print_services(client: BleakClient) -> None:
    print("Services / Characteristics")
    for svc in client.services:
        print(f"\n[{svc.uuid}] {svc.description}")
        for ch in svc.characteristics:
            props = ",".join(ch.properties)
            print(f"  - {ch.uuid}  props={props}  handle={ch.handle}")


async def main() -> int:
    p = argparse.ArgumentParser(description="BLE GATT write/notify helper")
    p.add_argument("--target", required=True, help="Device address/UUID or name substring")
    p.add_argument("--list", action="store_true", help="List services and characteristics then exit")
    p.add_argument("--write-char", default="", help="Characteristic UUID to write")
    p.add_argument("--payload", default="", help="Hex payload to write, e.g. 050502064006400000")
    p.add_argument(
        "--response",
        action="store_true",
        help="Use write with response (default: write without response)",
    )
    p.add_argument(
        "--notify-char",
        default="",
        help="Characteristic UUID to subscribe for notifications",
    )
    p.add_argument("--notify-seconds", type=float, default=3.0, help="Seconds to wait for notify")
    p.add_argument("--repeat", type=int, default=1, help="Write repetitions")
    p.add_argument("--interval-ms", type=int, default=100, help="Delay between writes")
    args = p.parse_args()

    dev = await resolve_device(args.target)
    if dev is None:
        print(f"Device not found for target: {args.target}")
        return 1

    print(f"Connecting to {dev.name} ({dev.address})")
    async with BleakClient(dev) as client:
        print(f"Connected: {client.is_connected}")

        if args.list:
            await print_services(client)
            return 0

        notifications = []

        def on_notify(_sender, data: bytearray):
            b = bytes(data)
            notifications.append(b)
            print(f"notify: {b.hex()}")

        if args.notify_char:
            await client.start_notify(args.notify_char, on_notify)
            print(f"Subscribed: {args.notify_char}")

        if args.write_char and args.payload:
            payload = hex_to_bytes(args.payload)
            for i in range(args.repeat):
                await client.write_gatt_char(
                    args.write_char,
                    payload,
                    response=args.response,
                )
                print(f"write[{i+1}/{args.repeat}]: {args.write_char} <- {payload.hex()}")
                if i + 1 < args.repeat:
                    await asyncio.sleep(max(0.0, args.interval_ms / 1000.0))
        else:
            if args.write_char or args.payload:
                print("Both --write-char and --payload are required for writes")
                return 1

        if args.notify_char:
            await asyncio.sleep(max(0.0, args.notify_seconds))
            await client.stop_notify(args.notify_char)
            print(f"Notification frames: {len(notifications)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
