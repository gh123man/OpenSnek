#!/usr/bin/env python3
"""Reuse local full-check success only for identical source/toolchain/environment, for one hour."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import stat
import subprocess
import sys
import time

MAX_AGE_SECONDS = 3600


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args],
        env={key: value for key, value in os.environ.items() if not key.startswith("GIT_")})


def fingerprint(root, context):
    digest = hashlib.sha256(json.dumps(context, sort_keys=True).encode())
    paths = set(git(root, "ls-files", "--cached", "--others", "--exclude-standard", "-z").split(b"\0"))
    for name in sorted(paths - {b""}):
        path = root / os.fsdecode(name)
        digest.update(name + b"\0")
        if not path.exists() and not path.is_symlink():
            digest.update(b"deleted\0")
            continue
        digest.update(str(stat.S_IMODE(path.lstat().st_mode)).encode() + b"\0")
        if path.is_symlink():
            digest.update(os.readlink(path).encode() + b"\0")
        if not path.is_file():
            raise ValueError(f"Cannot safely fingerprint non-file input: {path}")
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
        digest.update(b"\0")
    return digest.hexdigest()


def receipt_path(root):
    path = Path(git(root, "rev-parse", "--git-path", "opensnek-validation.json").decode().strip())
    return path if path.is_absolute() else root / path


def record(root, before, context, now=None):
    if fingerprint(root, context) != before:
        raise ValueError("Checkout changed during validation; rerun before publishing")
    receipt = {"schema_version": 1, "fingerprint": before, "completed_at": time.time() if now is None else now}
    path = receipt_path(root)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(receipt) + "\n")
    temporary.replace(path)


def invalidate(root):
    receipt_path(root).unlink(missing_ok=True)


def reusable(root, context, now=None):
    try:
        receipt = json.loads(receipt_path(root).read_text())
        age = (time.time() if now is None else now) - receipt["completed_at"]
        return (receipt["schema_version"] == 1 and 0 <= age <= MAX_AGE_SECONDS
                and receipt["fingerprint"] == fingerprint(root, context))
    except (OSError, ValueError, KeyError, TypeError):
        return False


def tool_context():
    # Git prepends its exec directory when invoking hooks. Compare resolved tools rather than
    # raw PATH so that irrelevant prefix does not force an identical suite to run twice.
    keys = {"HOME", "TMPDIR", "DEVELOPER_DIR", "SDKROOT", "MACOSX_DEPLOYMENT_TARGET", "LANG", "CI"}
    environment = {key: value for key, value in os.environ.items() if key in keys or key.startswith("OPEN_SNEK_")}
    executables = {}
    for name in ["swift", "xcrun", "python3", "bash", "git", "tee", "mktemp", "dirname"]:
        path = shutil.which(name)
        if path is None:
            executables[name] = None
            continue
        details = Path(path).stat()
        # Git's bin/ and libexec/ aliases can be hard links to the same executable.
        executables[name] = [details.st_dev, details.st_ino, details.st_size, details.st_mtime_ns]
    return {"environment": environment, "executables": executables, "python": sys.version, "python_path": sys.executable,
            "host": platform.platform(), "machine": platform.machine(),
            "swift": subprocess.check_output(["swift", "--version"], text=True, stderr=subprocess.STDOUT),
            "format": subprocess.check_output(["xcrun", "swift-format", "--version"], text=True, stderr=subprocess.STDOUT)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["fingerprint", "verify", "record", "invalidate"])
    parser.add_argument("--before")
    args = parser.parse_args()
    try:
        root = Path(git(Path.cwd(), "rev-parse", "--show-toplevel").decode().strip())
        if args.action == "invalidate":
            invalidate(root)
            return 0
        context = tool_context()
        if args.action == "verify":
            # Hardware runs are never cached: a source hash says nothing about live device state.
            return 0 if not os.environ.get("CI") and os.environ.get("OPEN_SNEK_HW", "0") == "0" and reusable(root, context) else 1
        if args.action == "fingerprint":
            print(fingerprint(root, context))
        else:
            if not args.before:
                raise ValueError("record requires the fingerprint taken before the checks")
            if os.environ.get("OPEN_SNEK_HW", "0") != "0":
                return 0
            record(root, args.before, context)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Validation receipt: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
