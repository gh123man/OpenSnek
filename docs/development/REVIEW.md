# Pinned Review Packets

Use this when delegating a committed-range review, especially to a read-only reviewer that
cannot run git. Do not assume an uncommitted/watchdog diff contains branch commits.

## Prepare

Commit the intended changes and verify the checkout is clean. Pin the base explicitly; creating
or updating a PR still requires fetching and reconciling its base as described in `AGENTS.md`.

```bash
python3 OpenSnek/scripts/review_packet.py \
  --base origin/main --head HEAD \
  --spec docs/development/ADDING_DEVICE_SUPPORT.md \
  --output /tmp/opensnek-review-packet
```

The output directory must be new and outside the checkout. The packet includes:

- Resolved base/head/merge-base SHAs, not moving symbolic refs.
- Exact committed diff, changed-file list, and commit subjects (no author emails).
- Snapshots of `AGENTS.md`, `CODING_STANDARDS.md`, and supplied spec files.
- A short review brief describing the range and read-only scope.

Existing directories, dirty checkouts, invalid refs, absent specs, and empty ranges fail rather
than silently producing a stale or incomplete packet. Validation results are separate evidence;
attach the commands, actual results/skips, and head they describe.

## Delegate

For a routine review, provide the packet path, relevant spec snapshots, precise review angle,
authority (read-only), expected finding format, and validation limits. Read-only tools are enough
to inspect the diff; there is no need to grant shell/write access merely to discover the range.

Use distinct angles only when they earn their cost: behavior/regressions versus standards/support
claims, for example. A short docs-only correction can be checked directly. Do not preload every
orchestration reference or run multiple reviewers for a trivial change.

Review surrounding source at the pinned head. If the checkout has moved, obtain source via git
at that SHA or ask for a pinned snapshot rather than treating new working files as the reviewed
version. Return actionable findings with file/line evidence and a clear verdict. The parent owns
fixes, acceptance, and publication; reviewer output alone never authorizes a push or merge.

## Validate once, publish safely

`pre_push_checks.sh` runs fresh checks by default and records success only if source contents
remain unchanged. The installed pre-push hook uses `--reuse`: for up to one hour it can reuse an
identical source/toolchain/relevant-environment result. Tracked and untracked nonignored files,
file modes, symlink targets/content, tooling/config, and `OPEN_SNEK_*` settings participate.
Missing/stale receipts, edits, or toolchain/environment changes run the checks again. A fresh
run invalidates any earlier success before checking, so a failure cannot fall back to an older pass. Receipts
live in the checkout's git directory, not a committed report. CI and hardware runs never reuse.

```bash
./OpenSnek/scripts/pre_push_checks.sh           # fresh, authoritative local run
./OpenSnek/scripts/pre_push_checks.sh --fresh   # explicitly ignore any receipt
# Commit with the same validated content, then push; the hook checks reuse eligibility itself.
```

A receipt does not prove unchanged hardware, app preferences, or external service state. Do not
use it as a substitute for a requested manual/hardware repro, and do not bypass a failed hook.
