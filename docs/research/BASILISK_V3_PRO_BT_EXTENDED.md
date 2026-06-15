# Basilisk V3 Pro Bluetooth Extended Reverse-Engineering Notes

## Objective

Capture and decode the Basilisk V3 Pro (`BT PID 0x00AC`) Bluetooth traffic that Synapse uses for missing onboard-profile features:

- profile enumeration
- active-profile switching
- profile-local storage semantics
- profile button (`0x6A`) behavior on BLE

This doc is intentionally V3 Pro-specific. The validated Basilisk V3 X HyperSpeed Bluetooth path does not appear to expose the same profile surface area.

## Current Ground Truth

Canonical implemented BLE behavior still lives in:

- `docs/protocol/BLE_PROTOCOL.md`
- `OpenSnek/Sources/OpenSnekProtocols/BLEVendorProtocol.swift`
- `OpenSnek/Sources/OpenSnekHardware/BLEVendorTransportClient.swift`

What is already validated on the V3 Pro Bluetooth path:

- the same vendor GATT service/characteristics as the V3 X path
- the V3 Pro-specific short 8-byte notify header
- DPI stage read/write
- per-zone brightness and static color
- battery reads
- button-write ACKs on the shared primary slots plus wheel tilt

What is still missing:

- hardware profile summary/state on BLE
- active-profile switching
- profile create/rename/select semantics
- shipped support for BLE clutch/profile-button remap or restore

## Live Probe Findings (2026-06-15)

Observed locally on the connected `BSK V3 PRO` BLE device from `OpenSnekProbe`:

- `05 81 00 01` read succeeded and returned battery raw `b8`
- `00 87 00 00` returned status `0x05` on Bluetooth, so the USB profile-summary key does not appear to carry over directly to the V3 Pro BLE path
- `08 84 01 34` returned a 16-byte payload that collapses to the validated wheel-tilt function block `0e 03 68 00 14 00 00`
- `08 84 01 0f` returned a 16-byte payload that collapses to the clutch default block `06 05 05 01 90 01 90`
- `08 84 01 6a` returned a 16-byte payload that collapses to the profile-button default block `12 01 01 00 00 00 00`

### V3 Pro BLE Button-Read Format

On the V3 Pro Bluetooth path, button reads from `08 84 01 <slot>` can return a 16-byte packed payload:

```text
[slot][00][b0][b0][b1][b1][b2][b2][b3][b3][b4][b4][b5][b5][b6][b6]
```

To recover the normal 7-byte function block, keep every other byte starting at offset `2`.

Examples:

- `34 00 0e 0e 03 03 68 68 00 00 14 14 00 00 00 00` -> `0e 03 68 00 14 00 00`
- `0f 00 06 06 05 05 05 05 01 01 90 90 01 01 90 90` -> `06 05 05 01 90 01 90`
- `6a 00 12 12 01 01 01 01 00 00 00 00 00 00 00 00` -> `12 01 01 00 00 00 00`

`OpenSnekProbe bt-raw-read` now prints this decoded function block automatically for `08 84 01 <slot>` reads.

## Working Theory

- The BLE profile button slot `0x6A` is a button-binding surface, not proof of actual onboard-profile switching support by itself.
- The old USB profile-summary candidate `00 87 00 00` is not a working BLE summary getter on this V3 Pro path.
- The missing profile feature set is therefore likely on one or more V3 Pro-specific BLE keys that have not been captured yet, not just on the shared Basilisk button-binding family.

## Synapse Log Capture Findings (2026-06-15)

Live capture from Synapse's product middleware / UI / mapping logs on the same macOS host exposed more of the V3 Pro BLE profile model than raw HCI access did.

### Profile Create Path

Creating a second profile and making it active produced a clear onboard-memory workflow:

- `obmEngine.addProfile()` reported `maxProfilesSupported: 5`, `profileIdList: [1,2]`, `numOfProfiles: 2`
- the new profile was created as:
  - slot `2`
  - GUID `cbb11d67-38cd-46db-bc16-a95424aaee61`
  - name `OPENSNEK_CAPTURE_1`
- Synapse wrote the profile metadata structure in four chunks:
  - offset `0`, size `76`
  - offset `76`, size `76`
  - offset `152`, size `76`
  - offset `228`, size `22`
- those chunks used a `fa 00 <offset_le16> ...` body and included:
  - the profile GUID
  - the ASCII profile name
  - the profile owner hash
- Synapse then followed with per-profile setup work such as:
  - DPI stage initialization
  - polling-rate setup
  - smart-reel state

This is strong evidence that the V3 Pro BLE profile surface is not the older V3 X HyperSpeed BLE model reused verbatim.

### Synapse's Stored Profile Model

The same capture showed a useful software-side profile model in Synapse local state:

- profile `Brian's MacBook Pro (2)-Default`
  - had a profile-local `mappings` entry for `Button4 -> KEY_F12`
  - reported `obmSlotId: []`
- profile `OPENSNEK_CAPTURE_1`
  - had no per-profile `mappings`
  - reported `obmSlotId: [2]`

Observed related local-storage details:

- `activeProfile` is tracked by GUID
- per-device metadata stores `activeProfileGuid`
- `profiles[*].appEngine.mappings` and `profiles[*].mappings` can diverge from the currently projected live OBM state

Treat this as a strong hint that Synapse distinguishes:

- a selected software profile GUID
- one or more stored OBM slots
- a separate live apply target used when the selected profile changes

### Profile Switch / Projection Behavior

Switching between the default profile and `OPENSNEK_CAPTURE_1` did not expose a simple BLE `set active profile register` style transaction in the logs.

Instead, the capture showed:

- Synapse changing `activeProfileGuid` / `selectedProfileGuid`
- runtime reloads for DPI / effects / mappings
- a live remap apply when moving onto the profile without the `F12` override:
  - `mappingsToBeReset` contained the default-profile `Button4 -> KEY_F12` override
  - Synapse then logged:
    - `setSingleButtonMapping profileId: 1`
    - `setSingleButtonAssignment 1, 4, 0, 1, 1 4,0,0,0,0`
    - `set OBM result ... params.mapping = Button4 -> Previous, obmSlotIds:[1]`

That sequence matters:

- the selected profile became `OPENSNEK_CAPTURE_1`
- the applied button write targeted `obmSlotIds:[1]`
- the written function block was the default `Button4 -> Previous` block, not the `KEY_F12` override

This suggests the current best theory for V3 Pro BLE profile switching is:

- Synapse may not be switching a hardware-selected active profile number directly
- instead, it may be projecting the selected profile's stored content into a live slot/layer, likely slot `1` on this path

That theory matches the direct probe behavior observed in the same session:

- while `OPENSNEK_CAPTURE_1` was active, a live BLE read of slot `0x04` returned the default `Button4 -> Previous` function block
- immediately after switching back, repeated raw BLE reads became transient / timed out, so the reverse direction still needs cleaner confirmation

### Practical Implementation Meaning

For OpenSnek, this capture shifts the near-term goal:

- do not assume the V3 Pro BLE path has a single writable active-profile selector equivalent to the older USB profile-summary assumptions
- expect at least two layers of state:
  - stored profile records / metadata
  - live projected button state
- profile support likely needs:
  - profile metadata decode
  - stored-slot identification
  - live-slot readback validation after profile changes
  - careful separation between "selected profile in software" and "current live button state on the mouse"

## Best Capture Strategy

Capture on the same machine and radio that is actually running Synapse. The goal is not a general BLE dump; it is a narrow, action-labeled trace where only one profile-related control changes at a time.

Record these capture sets separately:

1. Active profile switch only
2. Profile rename only
3. Create/delete/copy profile only
4. One-slot button change on profile 1 vs profile 2
5. Profile button remap only

For each set:

- start from a known baseline
- change one thing in Synapse
- wait for all BLE traffic to settle
- restore the original state before ending the capture
- write down the exact UI action timeline while recording

## Suggested Synapse Experiments

Use obviously different values so the wire diffs are easy to spot:

1. Set profile 1 slot `0x04` to `Back`
2. Set profile 2 slot `0x04` to `Keyboard F13` or another unusual binding
3. Switch between profile 1 and profile 2 without changing anything else
4. Rename profile 2 to a distinctive label
5. Rebind the profile button `0x6A` to a normal mouse action, then restore default

This lets us separate:

- profile metadata traffic
- active-profile traffic
- slot-storage addressing
- profile-button traffic

## Local Decode / Validation Loop

After capturing Synapse traffic:

1. Identify candidate read/write keys and payload lengths from the profile-related action window.
2. Re-run those keys locally with `OpenSnekProbe` against the paired V3 Pro.
3. Confirm readback stability before adding any Swift support.
4. Only ship UI once the app can represent the mouse honestly across reconnects and profile changes.

Useful local commands:

```bash
swift run --package-path OpenSnek OpenSnekProbe bt-raw-read --name "BSK V3 PRO" --key 0884016a --timeout-ms 1200
swift run --package-path OpenSnek OpenSnekProbe bt-raw-read --name "BSK V3 PRO" --key 0884010f --timeout-ms 1200
swift run --package-path OpenSnek OpenSnekProbe bt-raw-read --name "BSK V3 PRO" --key 00870000 --timeout-ms 1200
```

If a newly captured write key looks safe and deterministic, validate it with:

```bash
swift run --package-path OpenSnek OpenSnekProbe bt-raw-write --name "BSK V3 PRO" --key <KEY> --payload <HEX> --timeout-ms 1200
```

## Implementation Bar For Shipping

Do not ship BLE profile support on the V3 Pro until all of the following are true:

- active profile can be read reliably
- active profile can be changed reliably or is clearly read-only
- button-profile storage semantics are understood across reconnects
- profile button behavior is stable enough for restore/remap UX
- docs and parity notes reflect the final BLE-specific model instead of the older USB assumptions

## References

- `docs/protocol/BLE_PROTOCOL.md`
- `docs/protocol/PARITY.md`
- `docs/research/BLE_REVERSE_ENGINEERING.md`
- `OpenSnek/Sources/OpenSnekProbe/main.swift`
