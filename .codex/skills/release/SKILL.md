---
name: release
description: Use this skill when the user wants to cut an OpenSnek release, push a new semantic version tag, or trigger the tag-driven GitHub release workflow. It follows the repo's release script and docs instead of hand-rolling git and tag commands.
---

# Release

## Overview

Use this skill to cut a tagged OpenSnek release from `main` and trigger the GitHub Actions DMG release workflow.

Prefer the repo's existing `./OpenSnek/scripts/cut_release.sh --version <semver>` entrypoint over manual tagging. For beta builds, use a bare semantic version with a prerelease suffix, such as `1.2.0-beta.1`; the workflow publishes suffix tags as GitHub prereleases with `latest=false`, so they do not trigger OpenSnek's stable update banner.

If the user does not provide an exact target version, inspect the latest tag plus the newest changelog entries, recommend a `major`, `minor`, or `patch` bump with a short rationale, then ask the user which bump they want before resolving the concrete semver. If the user asks for a beta without an exact version, resolve the target core version from that bump and use the next `-beta.N` suffix for that core version.

## Workflow

1. Start from the repository root and inspect the current git state with `git status --short --branch`.
2. Inspect the current release context before choosing a version:
   - read the latest tag with `git tag --sort=-v:refname | head`
   - inspect the newest relevant `CHANGELOG.md` section(s)
3. If the user already provided an exact version, confirm it is bare semver without a leading `v`. Stable versions look like `1.2.3`; beta/prerelease versions look like `1.2.3-beta.1`. Skip the bump prompt.
4. If the user did not provide an exact version:
   - suggest `major`, `minor`, or `patch` based on the changelog and explain the recommendation in one short sentence
   - use these heuristics unless the changelog clearly points elsewhere:
     - `patch`: fixes, polish, internal reliability, tooling, and backward-compatible corrections
     - `minor`: backward-compatible user-facing features, new supported hardware, new commands, or meaningful capability additions
     - `major`: breaking or intentionally incompatible changes to user workflows, APIs, protocols, or packaging expectations
   - if the changelog is ambiguous, say so and default to the smallest defensible bump
   - ask the user which bump they want: `major`, `minor`, or `patch`
   - compute the concrete bare semver from the latest tag after the user answers
5. Use `./OpenSnek/scripts/cut_release.sh --version <semver>` as the default release command. For beta builds, pass the full prerelease version, for example `./OpenSnek/scripts/cut_release.sh --version 1.2.0-beta.1`.
6. Let the script handle the preflight: clean worktree check, fetch/fast-forward of `main`, full `swift test --package-path OpenSnek`, annotated `v<semver>` tag creation, and push of both `main` and the tag.
7. Report the pushed tag and remind the user that `.github/workflows/release-dmg.yml` publishes the release from that tag. For prerelease tags, remind them the GitHub Release is marked prerelease and not latest.

## Guardrails

- Do not cut a release from a dirty worktree.
- Do not add the `v` prefix to the script argument; the script adds it when creating the tag.
- Do not publish beta builds from a stable-looking version. Use a prerelease suffix such as `-beta.1` so GitHub's latest full-release endpoint ignores it.
- Do not invent a version before checking the latest tag.
- Do not skip the bump recommendation and `major`/`minor`/`patch` prompt when the user has not already supplied an exact semver.
- Do not use `--skip-tests` unless the user explicitly asks for it.
- Do not bypass `cut_release.sh` with raw `git tag` commands unless the user explicitly asks for a manual flow.
- If the command fails, summarize the exact failing step and stop before retrying anything destructive.
