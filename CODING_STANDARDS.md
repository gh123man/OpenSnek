# Review Standards

Review these judgement calls against the requested scope and surrounding code. Mechanical
formatting, lint, and declaration comments belong to the existing
checks, not repeated reviewer instructions. Run the focused checks listed in
[Validation](docs/development/VALIDATION.md); use the pinned packet workflow in
[Review](docs/development/REVIEW.md).

## Swift design

- Compiler-time warnings are review signals. Investigate reproducible slowdowns; do not split
  trivial methods merely to satisfy runner-dependent timing. Build errors, lint/format errors,
  and test failures remain blocking.

- Keep each method/closure focused. Split phases and validation branches into meaningful helpers
  rather than accumulating setup, nested conditionals, or local lint suppressions.
- Group related parameters into domain-specific request/result/snapshot types when the same
  shape crosses callers or test seams. Avoid an abstraction with only hypothetical consumers.
- Give shared device case sets one semantic owner: a profile capability, enum property, or
  protocol helper. Device-specific facts belong in profiles, not repeated raw-PID checks in UI.
- Prefer early guards and domain names. Keep number/byte sets named where their meaning is not
  self-descriptive. Comments should explain a protocol or UX constraint, not narrate syntax.
- Preserve per-device and per-zone semantics across view, editor, apply patch, and wire encoding.
  A regression test should exercise the user action chain and observable result, not just the
  setter that happened to contain the last fix.

## Evidence and device support

- Read the [device bring-up checklist](docs/development/ADDING_DEVICE_SUPPORT.md) when reviewing
  a new device/transport. Check app and probe consumers, merge and serialization clamps, raw
  button defaults, telemetry expectations, and lighting read/write addressing together.
- ACK is transport evidence, not authoritative proof of changed device state or rendering.
  Use readback and, where needed, physical confirmation. Separate finite checks from reliability
  guarantees, shared slot layout from physical press validation, and per-setting persistence
  from universal power-cycle persistence.
- The validation manifest checks tracked identities/capabilities/evidence paths. It does not
  interpret capture contents or prove every profile is validated. Compare human-facing support
  prose and parity notes with the scoped evidence; retain explicit unsupported/untested limits.
- Hardware restore failures must remain failures, with the original journal retained. Avoid
  silent `try?` restoration, factory-reset shortcuts, or writes to an unselected device.

## Changelog and release notes

- Update `CHANGELOG.md` for functional app/probe/tool changes. Put research-only findings and
  capture notes in protocol/research docs instead.
- Use `Fixed` for defects present on `main`; fold fixes to an unmerged feature into that
  feature's net `Added`/`Changed` entry.
- GitHub release notes start with the released version header and summarize features/notable
  fixes. Omit internal-only formatting, lint, CI/release automation, dependencies, docs, and
  refactors unless they directly change user-facing behavior.
