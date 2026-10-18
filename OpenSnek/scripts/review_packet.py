#!/usr/bin/env python3
"""Create a self-contained, pinned review packet outside the checkout."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], stderr=subprocess.PIPE,
        env={key: value for key, value in os.environ.items() if not key.startswith("GIT_")})


def create_packet(root, base, head, output, specs):
    root = Path(git(root, "rev-parse", "--show-toplevel").decode().strip()).resolve()
    output = output.resolve()
    if output == root or root in output.parents:
        raise ValueError("Review packets belong outside the checkout")
    if git(root, "status", "--porcelain").strip():
        raise ValueError("Commit or stash changes first; review packets pin committed state only")
    base_sha = git(root, "rev-parse", "--verify", base + "^{commit}").decode().strip()
    head_sha = git(root, "rev-parse", "--verify", head + "^{commit}").decode().strip()
    merge_base = git(root, "merge-base", base_sha, head_sha).decode().strip()
    patch = git(root, "diff", "--no-ext-diff", "--no-textconv", merge_base, head_sha)
    if not patch:
        raise ValueError("The selected committed range has no diff")
    spec_data = []
    for spec in specs:
        path = Path(spec)
        path = path if path.is_absolute() else root / path
        spec_data.append((str(path), path.read_bytes()))
    output.mkdir(parents=True, exist_ok=False)
    (output / "changes.diff").write_bytes(patch)
    (output / "commits.txt").write_bytes(git(root, "log", "--format=%h %s", base_sha + ".." + head_sha))
    (output / "files.txt").write_bytes(git(root, "diff", "--name-status", merge_base, head_sha))
    root_files = git(root, "ls-tree", "--name-only", head_sha).decode().splitlines()
    for name in ["AGENTS.md", "CODING_STANDARDS.md"]:
        if name in root_files:
            (output / name).write_bytes(git(root, "show", head_sha + ":" + name))
    spec_paths = []
    for index, (original, data) in enumerate(spec_data):
        name = f"spec-{index + 1}.md"
        (output / name).write_bytes(data)
        spec_paths.append({"source": original, "snapshot": name})
    metadata = {"schema_version": 1, "repository": str(root), "base_sha": base_sha,
                "head_sha": head_sha, "merge_base": merge_base, "specs": spec_paths}
    (output / "review.json").write_text(json.dumps(metadata, indent=2) + "\n")
    (output / "README.md").write_text(
        f"# Read-only review packet\n\nRepository: `{root}`\n\n"
        f"Pinned head: `{head_sha}`\n\nPinned baseline: `{base_sha}`\n\n"
        "Read `changes.diff`, `files.txt`, the snapshotted standards, and any `spec-*.md` files. "
        "Do not use an uncommitted watchdog diff as a substitute for this range. "
        "Read surrounding source only from the pinned head (check the checkout before using it). "
        "Report evidence-backed findings with file/line references; do not edit files. "
        "The packet contains no validation claim: attach exact-head command results separately.\n")
    return metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", required=True)
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--spec", action="append", default=[])
    args = parser.parse_args()
    try:
        metadata = create_packet(Path.cwd(), args.base, args.head, args.output, args.spec)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Review packet failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps({"packet": str(args.output.resolve()), **metadata}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
