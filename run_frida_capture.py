#!/usr/bin/env python3
"""
Run the Frida GATT capture script attached to ALL RazerAppEngine processes.
Writes structured JSON to artifacts/<run>.json (runbook format) and optional raw log.

Usage:
  python run_frida_capture.py --run baseline --duration 30
  python run_frida_capture.py --run dpi_800_to_1600
  python run_frida_capture.py --run poll_1000_to_500 --duration 20
"""
import argparse
import json
import os
import sys
import time

import frida

ARTIFACTS_DIR = "artifacts"
LOG_PATH = "capture.log"


def get_razer_pids():
    try:
        device = frida.get_local_device()
        processes = device.enumerate_processes()
        return [p.pid for p in processes if p.name and "RazerAppEngine" in p.name]
    except Exception:
        return []


def normalize_record(raw, pid):
    """Convert Frida payload to runbook artifact record schema."""
    rec = {
        "time": raw.get("time"),
        "op": raw.get("op", "write"),
        "service_uuid": raw.get("service_uuid", ""),
        "char_uuid": raw.get("char_uuid", ""),
        "handle": raw.get("handle"),
        "write_mode": raw.get("write_mode", ""),
        "value_hex": raw.get("value_hex", ""),
        "pid": pid,
    }
    if raw.get("ioctl"):
        rec["ioctl"] = raw["ioctl"]
    if raw.get("path"):
        rec["path"] = raw["path"]
    # Coerce handle for JSON (int or empty string)
    if rec.get("handle") == "":
        rec["handle"] = None
    return rec


def main():
    ap = argparse.ArgumentParser(description="Frida capture for Synapse BLE GATT to runbook artifacts")
    ap.add_argument(
        "--run",
        default="capture",
        help="Run name for artifact file (e.g. baseline, dpi_800_to_1600). Output: artifacts/<run>.json",
    )
    ap.add_argument(
        "--duration",
        type=int,
        default=None,
        help="Capture duration in seconds (default: 30 for 'baseline', else 15)",
    )
    ap.add_argument(
        "--no-json",
        action="store_true",
        help="Only write raw log, do not write artifacts/<run>.json",
    )
    args = ap.parse_args()

    duration = args.duration
    if duration is None:
        duration = 30 if args.run == "baseline" else 15

    pids = get_razer_pids()
    if not pids:
        print("No RazerAppEngine processes found. Is Synapse running?")
        sys.exit(1)
    print("Attaching to PIDs: %s" % pids)

    os.makedirs(ARTIFACTS_DIR, exist_ok=True)
    records = []
    log_path = os.path.join(ARTIFACTS_DIR, "capture_%s.log" % args.run)
    json_path = None if args.no_json else os.path.join(ARTIFACTS_DIR, "%s.json" % args.run)

    with open(log_path, "w", encoding="utf-8") as log:
        def make_on_message(pid):
            def on_message(message, data):
                payload = message.get("payload")
                if message.get("type") == "send" and isinstance(payload, dict) and payload.get("type") == "gatt_record":
                    records.append(normalize_record(payload.get("payload", payload), pid))
                # Log line
                if isinstance(payload, list):
                    pline = " ".join(str(p) for p in payload)
                elif isinstance(payload, dict):
                    pline = json.dumps(payload)
                elif payload is None:
                    pline = str(message)
                else:
                    pline = str(payload)
                if message["type"] == "send":
                    line = "[PID %s] %s\n" % (pid, pline)
                else:
                    line = "[PID %s] [%s] %s\n" % (pid, message.get("type", ""), pline)
                log.write(line)
                log.flush()
                print(line, end="")
            return on_message

        with open("frida_synapse_gatt.js", "r", encoding="utf-8") as f:
            script_code = f.read()

        sessions = []
        for pid in pids:
            try:
                session = frida.attach(pid)
                script = session.create_script(script_code)
                script.on("message", make_on_message(pid))
                script.load()
                sessions.append((pid, session))
            except Exception as e:
                log.write("Failed to attach to %s: %s\n" % (pid, e))
                print("Failed to attach to %s: %s" % (pid, e))

        if not sessions:
            print("Could not attach to any process.")
            sys.exit(1)

        hint = "Do not change any settings." if args.run == "baseline" else "Change ONE setting in Synapse (e.g. DPI 800->1600)."
        log.write("Capturing for %d seconds. %s\n" % (duration, hint))
        log.flush()
        print("Capturing for %d seconds (%d processes). %s" % (duration, len(sessions), hint))

        try:
            time.sleep(duration)
        except KeyboardInterrupt:
            pass

        for _pid, session in sessions:
            try:
                session.detach()
            except Exception:
                pass

        log.write("Capture ended. Records: %d. PIDs: %s\n" % (len(records), [p for p, _ in sessions]))
        print("Capture ended. Records: %d. Raw log: %s" % (len(records), log_path))

    if json_path and records:
        meta = {
            "run": args.run,
            "duration_sec": duration,
            "pids": [p for p, _ in sessions],
        }
        out = {"meta": meta, "records": records}
        with open(json_path, "w", encoding="utf-8") as f:
            json.dump(out, f, indent=2)
        print("Artifact written: %s" % json_path)
    elif json_path and not args.no_json:
        meta = {"run": args.run, "duration_sec": duration, "pids": [p for p, _ in sessions]}
        out = {"meta": meta, "records": []}
        with open(json_path, "w", encoding="utf-8") as f:
            json.dump(out, f, indent=2)
        print("No GATT records captured. Empty artifact: %s" % json_path)


if __name__ == "__main__":
    main()
