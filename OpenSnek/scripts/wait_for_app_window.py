#!/usr/bin/env python3
"""Verify the app's own visible-main-window receipt; no Accessibility permission needed."""
import argparse
import json
import os
from pathlib import Path
import sys
import time


def verify(receipt, bundle):
    if receipt.get("schemaVersion") != 1 or receipt.get("role") != "app":
        raise ValueError("Receipt is not from a supported foreground app")
    if Path(receipt.get("bundlePath", "")).resolve() != bundle.resolve():
        raise ValueError("Receipt came from a different app bundle")
    if not isinstance(receipt.get("visibleWindowCount"), int) or receipt["visibleWindowCount"] < 1:
        raise ValueError("Receipt contains no visible main window")
    pid = receipt.get("pid")
    if not isinstance(pid, int) or pid <= 0:
        raise ValueError("Receipt contains an invalid PID")
    os.kill(pid, 0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("receipt", type=Path)
    parser.add_argument("bundle", type=Path)
    parser.add_argument("--timeout", type=float, default=15)
    args = parser.parse_args()
    deadline = time.monotonic() + args.timeout
    while True:
        if args.receipt.exists():
            try:
                receipt = json.loads(args.receipt.read_text())
                verify(receipt, args.bundle)
            except (ValueError, OSError, TypeError) as error:
                print(f"[open-snek] Window verification failed: {error}", file=sys.stderr)
                return 1
            print(f"[open-snek] Verified foreground app pid={receipt['pid']} visible-main-windows={receipt['visibleWindowCount']}")
            return 0
        if time.monotonic() >= deadline:
            print("[open-snek] No visible-window acknowledgment. The app may have failed to open; process presence alone is not success.", file=sys.stderr)
            return 1
        time.sleep(0.1)


if __name__ == "__main__":
    sys.exit(main())
