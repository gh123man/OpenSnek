#!/usr/bin/env python3
"""Report advisory compiler-time diagnostics while retaining them in build logs."""
import re
import sys
from pathlib import Path


def compiler_time_diagnostics(text):
    plain = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", text)
    return [line for line in plain.splitlines()
            if re.search(r"warning:.*took \d+(?:\.\d+)?ms to type-check \(limit: \d+ms\)", line)]


def main():
    if len(sys.argv) != 2:
        print("Usage: check_swift_diagnostics.py BUILD_LOG", file=sys.stderr)
        return 2
    try:
        diagnostics = compiler_time_diagnostics(Path(sys.argv[1]).read_text(errors="replace"))
    except OSError as error:
        print(error, file=sys.stderr)
        return 2
    if diagnostics:
        print("[open-snek] Advisory Swift compiler-time warnings (investigate reproducible slowdowns):", file=sys.stderr)
        print("\n".join(diagnostics), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
