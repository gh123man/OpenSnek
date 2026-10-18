# Add a Device or Transport

Use this checklist for agent-guided or manual bring-up. Device support is transport-specific:
complete a row for wired USB, receiver, and Bluetooth rather than assuming shared identities or
capabilities. An untested row remains unclaimed.

## 1. Identify before writing

Record marketing name/edition, firmware when readable, transport, VID/PID, Bluetooth name, and
installed side plate. Use macOS System Information/`ioreg` and the existing probe's read-only
commands. `usb-info` prints the selected USB identity; `bt-profile-hid-watch --name "NAME"
--duration 1` prints candidate HID IDs. Do not publish serials or personal profile metadata.

Build only the probe initially:

```bash
swift build --package-path OpenSnek --product OpenSnekProbe
swift run --skip-build --package-path OpenSnek OpenSnekProbe support-catalog > /tmp/support-catalog.json
```

`support-catalog` is offline: it exports canonical Swift profile IDs, transport/product IDs, and
effective capability flags without opening HID or Bluetooth. It is metadata, not validation.

For Bluetooth vendor probes, stop both app and service first after saving UI edits. The probe
fails before an exchange if either is running or another probe owns the per-user BLE probe
session. It never kills processes or retries a rejected command automatically. This conservative
preflight covers all bundled OpenSnek instances/probes for the user, not arbitrary third-party
Bluetooth clients. See [Validation](VALIDATION.md) for permissions and recovery.

## 2. Build an evidence matrix

For each transport/feature record **read**, **changed write**, **authoritative readback**,
**exact restore**, and **physical confirmation** separately. ACK alone is insufficient.

| Feature | Questions to resolve |
|---|---|
| DPI | Stage IDs/active token, X/Y pairs, published ceiling, merge **and** wire-builder clamps, active-stage-only edits |
| Buttons | Device inventory when available, live/stored read layout, factory blocks, changed write and Default, printed-label order for every available plate |
| Lighting | Actual LED zones, separate brightness read/write targets, effect-body format, per-zone versus All Zones semantics, rendering |
| Battery/power | Raw scale even below 100, trustworthy charging source, sleep timeout, unsupported telemetry omitted |
| Profiles | Metadata reads, assigned/unassigned targets, guarded CRUD prelude; never infer writable CRUD from inventory alone |
| Lifecycle | Unplug/offline/sleep **and** replug/wake/recover; windowed and service presentation |
| Persistence | Power-cycle with app/service stopped so auto-restore cannot mask reset; characterize each setting/target, not the whole device |

Use original snapshots, not factory defaults. Read all affected targets before writing; journal
them before the first mutation. Restore persistent state before live state when persistent writes
project into live, then verify all originals. A failure leaves the recovery journal intact. The
scoped hardware helpers and recovery commands are in [Validation](VALIDATION.md#safe-hardware-validation).

Store focused commands/transcripts and a concise result/limits README under `captures/usb/` or
`captures/ble/`. Follow [capture organization](../../captures/README.md). For Windows reverse
engineering prefer the automated BTVS/Synapse workflow; wheel-mode or other unmapped controls may
need a known-good official-app capture instead of blind command probing.

## 3. Map the smallest supported surface

Start in `OpenSnek/Sources/OpenSnekCore/{DeviceSupport.swift,Models.swift,ButtonBindingSupport.swift}`.
Keep protocol parsing/building in `OpenSnekProtocols` and transport behavior in `OpenSnekHardware`.
Inspect both app bridge **and** probe consumers when adding a protocol variant; do not assume a
profile registration alone updates lighting, battery interpretation, defaults, or DPI encoding.

Hide unproven features. Use `Contributor validated` with a credited source for contributor
hardware, `Validated` only for maintainer/local hardware, and distinguish mapped/untested/unsupported.
Use profile capabilities/shared semantic helpers rather than scattered raw-PID conditions.

## 4. Record machine-checkable claims

Add an entry to [device-validation.json](device-validation.json) for each newly validated transport.
This manifest is **incremental**, not a backfilled claim that every legacy profile/feature has
captured hardware validation. The seeded contributor record is a real example, not a template
whose status/source should be copied blindly.

Each entry contains `profile_id`, `transport`, observed `product_ids` (integers or `0x` strings),
`features`, and `limitations`. Feature names come from `support-catalog` capabilities. Each feature
has one status:

- `maintainer_validated` / `contributor_validated`: require `source` and nonempty repo-relative
  `evidence` file paths. Contributor-only profiles cannot claim maintainer validation.
- `mapped`: shipped by code, but no hardware-validation claim.
- `not_tested`: explicitly unverified; does not imply support or rejection.
- `unsupported`: must agree with a disabled effective code capability.

The checker rejects unregistered identities, unsupported claimed capabilities, unknown statuses,
missing credit/evidence, and evidence paths escaping the checkout. It checks mechanics, not whether
a transcript genuinely proves a claim; that remains a review responsibility.

```bash
./OpenSnek/scripts/check_device_validation.sh
```

Keep `docs/DEVICE_SUPPORT.md`, affected protocol docs, and the root README aligned. Open
`docs/protocol/PARITY.md` when shipped support/parity changes. Built-in firmware effects and custom
software-frame streaming are different capabilities. Never turn a finite idle test into an
unbounded reliability claim.

## 5. Test and publish

Write regression coverage at observable seams: profile resolution, protocol bytes, or the complete
editor-action-to-device-patch path. In particular, test transitions—not just independent setters.
Start with the focused checks in [Validation](VALIDATION.md), then run the full guard before
publishing. An actual hardware result is explicitly `pass`, `fail`, or `skipped` with scope/reason.

For protocol/functional app/probe/tool changes, update `CHANGELOG.md`; capture/research-only work
belongs in evidence docs. Review and release conventions live in [CODING_STANDARDS.md](../../CODING_STANDARDS.md).
Prepare a pinned, self-contained [review packet](REVIEW.md) instead of assuming reviewers can run
git. Fetch/reconcile the base before updating the PR. Include evidence, test results, and remaining
limits; do not claim unsupported transports merely because related hardware shares a profile.

For an issue or agent handoff, provide the exact model/edition, connected transport, known IDs,
features of interest, and whether the hardware owner can perform physical steps. A useful prompt is:

> Add support for this device using the device bring-up checklist. Start with read-only discovery,
> propose safe scoped tests, and preserve/restore my current settings. Credit contributor validation
> accurately and keep untested controls hidden.
