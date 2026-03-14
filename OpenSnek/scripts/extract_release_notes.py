#!/usr/bin/env python3

import argparse
import pathlib
import re
import sys


SECTION_PATTERN = re.compile(r"^## \[(.+)\]\s*$", re.MULTILINE)


def extract_latest_section(markdown: str) -> str:
    matches = list(SECTION_PATTERN.finditer(markdown))
    if not matches:
        raise ValueError("No top-level changelog sections found")

    first = matches[0]
    end = matches[1].start() if len(matches) > 1 else len(markdown)
    section = markdown[first.start():end].strip()
    if not section:
        raise ValueError("Latest changelog section is empty")
    return section


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Extract the latest top-level section from CHANGELOG.md for GitHub Release notes."
    )
    parser.add_argument(
        "changelog",
        nargs="?",
        default="CHANGELOG.md",
        help="Path to CHANGELOG.md",
    )
    args = parser.parse_args()

    changelog_path = pathlib.Path(args.changelog)
    markdown = changelog_path.read_text(encoding="utf-8")
    try:
        section = extract_latest_section(markdown)
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    sys.stdout.write(section)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
