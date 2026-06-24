#!/usr/bin/env python3

import argparse
import pathlib
import re
import sys
from typing import Optional


SECTION_PATTERN = re.compile(r"^## \[(.+)\]\s*$", re.MULTILINE)


def normalize_version(version: str) -> str:
    return version[1:] if version.startswith("v") else version


def extract_latest_section(markdown: str, expected_version: Optional[str] = None) -> str:
    matches = list(SECTION_PATTERN.finditer(markdown))
    if not matches:
        raise ValueError("No top-level changelog sections found")

    first = matches[0]
    section_version = first.group(1)
    if expected_version is not None:
        normalized_expected = normalize_version(expected_version)
        if section_version != normalized_expected:
            raise ValueError(
                "Latest changelog section "
                f"[{section_version}] does not match release version [{normalized_expected}]"
            )

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
    parser.add_argument(
        "--version",
        help="Expected release version, with or without a leading v",
    )
    args = parser.parse_args()

    changelog_path = pathlib.Path(args.changelog)
    markdown = changelog_path.read_text(encoding="utf-8")
    try:
        section = extract_latest_section(markdown, expected_version=args.version)
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    sys.stdout.write(section)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
