#!/usr/bin/env python3
"""Fail on compiler long-body diagnostics, without promoting unrelated warnings."""
import re
import sys
from pathlib import Path


def prohibited_diagnostics(text):
    plain = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", text)
    return [line for line in plain.splitlines()
            if re.search(r"warning:.*took \d+(?:\.\d+)?ms to type-check \(limit: \d+ms\)", line)]


def main():
    if len(sys.argv) != 2:
        print("Usage: check_swift_diagnostics.py BUILD_LOG", file=sys.stderr)
        return 2
    try:
        diagnostics = prohibited_diagnostics(Path(sys.argv[1]).read_text(errors="replace"))
    except OSError as error:
        print(error, file=sys.stderr)
        return 2
    if diagnostics:
        print("[open-snek] Prohibited Swift long-body diagnostics:", file=sys.stderr)
        print("\n".join(diagnostics), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
