---
name: release
description: Use this skill when the user wants to cut an OpenSnek release, push a new semantic version tag, or trigger the tag-driven GitHub release workflow. It follows the repo's release script and docs instead of hand-rolling git and tag commands.
---

# Release

## Overview

Use this skill to cut a tagged OpenSnek release from `main` and trigger the GitHub Actions DMG release workflow.

Prefer the repo's existing `./OpenSnek/scripts/cut_release.sh --version <semver>` entrypoint over manual tagging.

## Workflow

1. Start from the repository root and inspect the current git state with `git status --short --branch`.
2. Confirm the requested version is bare semver without a leading `v`.
3. Use `./OpenSnek/scripts/cut_release.sh --version <semver>` as the default release command.
4. Let the script handle the preflight: clean worktree check, fetch/fast-forward of `main`, full `swift test --package-path OpenSnek`, annotated `v<semver>` tag creation, and push of both `main` and the tag.
5. Report the pushed tag and remind the user that `.github/workflows/release-dmg.yml` publishes the release from that tag.

## Guardrails

- Do not cut a release from a dirty worktree.
- Do not add the `v` prefix to the script argument; the script adds it when creating the tag.
- Do not use `--skip-tests` unless the user explicitly asks for it.
- Do not bypass `cut_release.sh` with raw `git tag` commands unless the user explicitly asks for a manual flow.
- If the command fails, summarize the exact failing step and stop before retrying anything destructive.
