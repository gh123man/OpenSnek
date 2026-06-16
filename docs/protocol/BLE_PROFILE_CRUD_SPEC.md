# Basilisk V3 Pro Bluetooth Profile CRUD Draft

This is the implementation-facing working spec for Basilisk V3 Pro Bluetooth
profile support. It is capture-backed but still incomplete; use it as the place
to accumulate the CRUD model before promoting behavior into Swift.

Primary evidence:

- `captures/ble/windows/2026-06-15-195434-profile-button-cycle-focused-pass-4/`
- `captures/ble/windows/2026-06-15-202616-profile-inventory-read-path-pass-1/`

## Model

Synapse maintains profile identity by host-side GUIDs and projects profile-owned
settings onto the mouse over BLE. On the wire, profile behavior is not yet a
single decoded "set active profile slot" command. Current captures show Synapse
replaying settings into a live target after active-profile changes.

The current working model:

| Concept | Current interpretation | Evidence |
|---|---|---|
| Host profile identity | Synapse GUID and name | Synapse `newActiveProfileGUID`, `set active profile`, and `[Armory] Active profile` logs |
| Stored/profile targets | Target byte in profile-capable setting writes, observed as `2`, `3`, `4`, `5` in current corpus | Writes such as `08 04 02 04`, `08 04 03 05`, `08 04 04 0F` |
| Live projection target | Target byte `1` | Synapse repeats selected settings to `08 04 01 <slot>` and `0B 04 01 00` |
| Active profile | Host-side Synapse state plus projected live device settings | Selection and physical-cycle captures both produce projection bursts |
| Device-native profile inventory | Not decoded yet | No passive read/list command confirmed |

Important distinction: selecting a profile in Synapse is not passive inventory.
The Windows profile-inventory capture shows that UI profile selection logs
`newActiveProfileGUID` and then sends live projection writes.

## Wire Keys Seen So Far

| Key | Direction | Observed payload/response | Working role |
|---|---|---|---|
| `01 86 00 00` | read | `00 00 00` | profile/session state read candidate before projection bursts |
| `01 82 00 00` | read | `03 00` | scalar state read candidate during projection |
| `01 8C <target> 00` | read | `01` for observed targets | stored/profile target state candidate |
| `08 04 <target> <slot>` | write | 10-byte button action payload | button binding for stored/profile target or live target |
| `08 05 <target> 00` | write | `00` | profile/apply control candidate |
| `08 06 01 00` | write | `00` | profile/apply control candidate |
| `08 07 <target> 00` | write/read-like ACK | `00`, response `50` | profile/apply control candidate |
| `03 04 <target> 00` | write | chunked profile metadata | profile name/GUID/owner structure write |
| `03 05 <target> 00` | write | none | profile metadata/apply candidate |
| `03 06 <target> 00` | write | none | profile clear/delete/prepare candidate |
| `0B 01 <target> 00` | write | 6-byte DPI scalar | stored/profile DPI scalar write candidate |
| `0B 04 01 00` | write | 38-byte DPI table | live DPI projection |
| `0B 04 <target> 00` | write | 38-byte DPI table | stored/profile DPI table write candidate |
| `0B 84 01 00` | read | 36-byte DPI table | live DPI readback after projection |
| `10 05 <target> 00` | write | brightness byte | stored/profile brightness write candidate |

The `01 xx` and `08 05` / `08 06` / `08 07` families are still research-only.
Do not ship writes to those keys until we safely probe them outside Synapse.

## Button Binding Payloads

Profile-capable button binding writes reuse the existing BLE 10-byte action
payload:

```text
[target][slot][layer][action][p0_le16][p1_le16][p2_le16]
```

The first payload byte mirrors the target byte in the key:

```text
key:     08 04 <target> <slot>
payload: <target> <slot> <layer> <action> ...
```

Examples:

| Meaning | Key | Payload |
|---|---|---|
| Stored/profile target `2`, slot `0x04`, keyboard F | `08 04 02 04` | `02 04 00 02 02 00 45 00 00 00` |
| Live target `1`, slot `0x04`, keyboard F | `08 04 01 04` | `01 04 00 02 02 00 45 00 00 00` |
| Stored/profile target `3`, slot `0x05`, mouse button 5 | `08 04 03 05` | `03 05 01 01 01 05 00 00 00 00` |
| Live target `1`, slot `0x05`, mouse button 5 | `08 04 01 05` | `01 05 01 01 01 05 00 00 00 00` |
| Live target `1`, slot `0x0F`, keyboard mapping | `08 04 01 0F` | `01 0F 00 02 02 00 09 00 00 00` |

OpenSnek's current Bluetooth button binding implementation only writes target
`1`. Full profile support will need the target to be explicit and validated.

## Read / Inventory

Status: partially mapped.

What is confirmed:

- Synapse can list host profiles by GUID/name in its own logs/storage.
- Selecting profiles in Synapse emits `from actionFromUI newActiveProfileGUID`,
  `set active profile`, and `[Armory] Active profile`.
- The mouse receives setting projection writes after profile selection.

What is not confirmed:

- A BLE command that lists onboard profile slots.
- A BLE command that maps a stored/profile target byte to a Synapse GUID.
- A BLE command that returns profile names. Names may be host-only.
- Whether `01 8C <target> 00` is an existence check, enable flag, dirty flag, or
  another stored-target state.

Implementation guidance:

- Treat the device as having a live projection surface first.
- Treat stored/profile targets as opaque numeric targets until create/update/delete
  captures prove stable semantics.
- Preserve host GUID/name mapping in OpenSnek storage rather than assuming the
  mouse stores human-readable profile names.

## Activate / Select

Status: projection behavior mapped; minimal activation command not mapped.

Profile selection through Synapse appears to:

1. Update Synapse host state:
   - `from actionFromUI newActiveProfileGUID <guid>`
   - `set active profile <serial>: <guid>`
   - `set device metadata <serial>: {"activeProfileGuid":"<guid>"}`
2. Project profile-owned settings to the live target:
   - DPI through `0B 04 01 00`
   - buttons through `08 04 01 <slot>`
   - lighting/effect state through existing lighting keys when applicable
3. Often read back live settings:
   - `0B 84 01 00`
   - `01 82 00 00`

Current implementation direction:

- First implementation can model "activate profile" as applying the stored
  OpenSnek profile snapshot to live target `1`.
- Do not assume a hidden BLE active-slot selector until a focused capture proves
  one exists.

## Create

Status: mapped for one Synapse-created profile into stored/profile target `2`.

Capture:

- `captures/ble/windows/2026-06-15-203420-profile-create-disposable-pass-1/`

Synapse first created/activated a host profile:

- GUID: `a5c15916-b5fd-4f33-8408-d978cd3bf37c`
- Initial name: `BRIAN-DESKTOP-Default 1`
- Final user-supplied name: `OPENSNEK_CREATE_PROBE_1`
- OBM slot/profile ID: `2`
- Owner hash: `31933b5452df5708882d4fb55d0b2905f16d829500fe936c56f98d5cd0241a76`

Important Synapse log lines:

- `obmEngineMouse.addProfile() profileId:2, guid:a5c15916-b5fd-4f33-8408-d978cd3bf37c, name:OPENSNEK_CREATE_PROBE_1`
- `addProfileNameStructure profileId:2, guid:a5c15916-b5fd-4f33-8408-d978cd3bf37c, name:OPENSNEK_CREATE_PROBE_1`
- `set OBM result ... slot":2,"guid":"a5c15916-b5fd-4f33-8408-d978cd3bf37c","name":"OPENSNEK_CREATE_PROBE_1"`

Observed create/write sequence around the `addProfile` event:

| Key | Len | Payload / response | Working role |
|---|---:|---|---|
| `03 06 02 00` | 0 | none | prepare/clear target `2` candidate |
| `08 05 02 00` | 1 | `00` | profile/apply control candidate |
| `01 8C 02 00` | 0 | response `01` | target `2` state check |
| `08 07 02 00` | 1 | `00`, response `50` | profile/apply control candidate |
| `03 05 02 00` | 0 | none | metadata/apply candidate |
| `03 04 02 00` | 80/80/80/26 | chunked profile metadata | profile GUID/name/owner structure |
| `0B 01 02 00` | 6 | `40 06 40 06 00 00` | stored target `2` current DPI scalar candidate (`1600`, `1600`) |
| `0B 04 02 00` | 38 | DPI stage table | stored target `2` DPI stage table |
| `08 05 02 00` | 1 | `00` | follow-up profile/apply control candidate |
| `10 05 02 00` | 1 | `54` | stored target `2` brightness |

### `03 04 <target> 00` Profile Metadata Chunks

The create capture writes the profile metadata as four chunks to `03 04 02 00`.
Each payload starts with:

```text
fa 00 <offset_le16> <data bytes...>
```

Observed offsets:

- `0x0000`
- `0x004C`
- `0x0098`
- `0x00E4`

Reconstructed non-zero fields:

| Offset | Length | Meaning |
|---:|---:|---|
| `0x0000` | 16 | GUID bytes, Windows/GUID little-endian layout: `a5c15916-b5fd-4f33-8408-d978cd3bf37c` |
| `0x0010` | 22 | ASCII profile name: `OPENSNEK_CREATE_PROBE_1` |
| `0x0074` | 64 | ASCII owner hash: `31933b5452df5708882d4fb55d0b2905f16d829500fe936c56f98d5cd0241a76` |

The remaining observed bytes in the 247-byte reconstructed structure were zero
padding in this capture. The fixed field sizes are not proven yet; treat the
offsets and padding as capture-backed for this profile, not a finalized binary
schema.

Open questions:

- Whether Synapse chose target `2` because it was the first recyclable/free OBM
  slot, because a previous slot `2` profile was replaced, or because creation
  always starts there in this state.
- Whether `03 06 02 00` is a delete/clear/prepare command. Synapse logs mention
  `obmEngineMouse.deleteProfile(2)` before the add completes, suggesting it may
  clear the target before rewriting it.
- Whether create without a rename prompt would write the same metadata once with
  the default duplicated name.

## Update

Status: mapped for active-profile single button binding writes; partially mapped
for setting projection and DPI writes.

Confirmed update surfaces:

- Live DPI table: `0B 04 01 00`
- Live button binding: `08 04 01 <slot>`
- Stored/profile button binding candidates: `08 04 <target> <slot>`

### Active Profile Button Binding

Capture:

- `captures/ble/windows/2026-06-15-204312-profile-update-active-button-pass-1/`

The active profile was `OPENSNEK_CREATE_PROBE_1`:

- GUID: `a5c15916-b5fd-4f33-8408-d978cd3bf37c`
- OBM slot/profile ID: `2`

The capture contains two Button5 keyboard edits. Both used the same write shape:

| Event | Key | Payload | Interpretation |
|---|---|---|---|
| Button5 -> keyboard HID `0x09` | `08 04 02 05` | `02 05 00 02 02 00 09 00 00 00` | write stored target `2`, slot `0x05` |
| Button5 -> keyboard HID `0x09` | `08 04 01 05` | `01 05 00 02 02 00 09 00 00 00` | immediately project same binding to live target `1` |
| Button5 -> keyboard HID `0x07` | `08 04 02 05` | `02 05 00 02 02 00 07 00 00 00` | write stored target `2`, slot `0x05` |
| Button5 -> keyboard HID `0x07` | `08 04 01 05` | `01 05 00 02 02 00 07 00 00 00` | immediately project same binding to live target `1` |

No profile metadata rewrite (`03 04`), DPI write, lighting write, `08 05`,
`08 07`, or `01 8C` operation was present in the reduced button-update windows.

Current implementation guidance:

- Updating a button on the active profile should write the stored profile target
  first and then write the live target `1`.
- The payload format is identical except for the target byte in both the key and
  payload byte 0.
- This is faster than a full profile projection and does not require profile
  metadata rewrites for simple button changes.

Needed capture:

- On the same known profile, change exactly one DPI stage or active stage.
- Compare whether Synapse writes both stored target and live target when the
  edited profile is active, and whether it writes only stored target when the
  edited profile is inactive.

## Delete

Status: not mapped.

Needed capture:

- Delete one known disposable profile.
- Record the deleted GUID/name and current active profile before deletion.

Questions to answer:

- Does deletion clear a stored target on-device?
- Does Synapse compact/reassign target bytes?
- What happens if the deleted profile is active?

## Rename

Status: likely host-only for rename-only updates in observed Synapse flows.

Captures:

- `captures/ble/windows/2026-06-15-204849-profile-rename-only-pass-1/`
- `captures/ble/windows/2026-06-15-205102-profile-rename-only-pass-2/`

Pass 1 was intended to rename the active disposable profile
`OPENSNEK_CREATE_PROBE_1` to `OPENSNEK_RENAME_PROBE_1`. Synapse logged the
active profile with the renamed display name at `+8.574s`, but the packet
capture contained only periodic `10 04 00 00` lighting-frame writes.

Pass 2 captured a rename of a different Synapse profile because renaming the
assigned disposable profile removed it from the assigned-slot UI. Synapse logged
the profile `cbb11d67-38cd-46db-bc16-a95424aaee61` as
`OPENSNEK_CAPTURE_1` at `+4.292s`, then as `OPENSNEK_CAPTURE_1_foo` at
`+12.995s`. There were no non-lighting vendor operations near the rename event.
The only non-lighting operations in that capture were profile-selection/button
projection writes at `+3.69s` and `+35.9s`:

| Time | Key | Payload | Interpretation |
|---:|---|---|---|
| `3.687556` | `08 04 01 05` | `01 05 00 01 01 05 00 00 00 00` | live Button5 projection |
| `3.717190` | `08 04 03 05` | `03 05 01 01 01 05 00 00 00 00` | stored target `3` Button5 write |
| `3.738594` | `08 04 01 05` | `01 05 01 01 01 05 00 00 00 00` | live Button5 projection |
| `35.907082` | `08 04 01 05` | `01 05 01 01 01 05 00 00 00 00` | live Button5 projection |
| `35.929506` | `08 04 01 04` | `01 04 00 02 02 00 45 00 00 00` | live Button4 projection |

Current implementation guidance:

- Treat profile display names as OpenSnek host-side metadata for rename/update.
- Do not rewrite `03 04 <target> 00` just to rename an existing profile.
- The `03 04` metadata structure is still required evidence for create, where
  Synapse wrote GUID/name/owner chunks to the stored target.
- If a future capture proves device-side rename persistence, add it as a
  separate stored-target metadata update path rather than using it for basic
  host display-name changes.

Open questions:

- Whether an explicit device-side rename exists but Synapse defers it until a
  profile is reassigned, exported, synced, or recreated.
- Whether names in `03 04` are used by firmware or only copied during profile
  creation for Synapse/OBM bookkeeping.

## OpenSnek Implementation Shape

Proposed types:

```text
BLEProfileTarget
  target: UInt8              // 1 = live projection, 2..n = stored/profile candidate
  hostGUID: UUID?            // OpenSnek/Synapse host identity when known
  name: String?              // host-side display name when known
  snapshot: DeviceSnapshot   // DPI, lighting, buttons, etc.
```

Proposed behavior:

- `readProfiles()` initially reads/returns OpenSnek-known host profiles and the
  current live projection snapshot; it should not pretend to list device-native
  names until that is captured.
- `activateProfile(id)` applies the stored snapshot to target `1`.
- `updateProfile(id, changes)` updates OpenSnek storage and, if active, applies
  changed settings to target `1`.
- Stored-target writes stay behind a hardware-gated experimental path until
  create/update/delete captures prove safety.

## Next Captures

Recommended order:

1. Create one disposable profile with no manual setting edits.
2. Update one DPI setting or active DPI stage on the active disposable profile.
3. Update one setting on an inactive profile.
4. Delete the disposable profile.
5. Revisit device-side rename only if we find a Synapse flow that emits BLE
   metadata writes for rename-only changes.
