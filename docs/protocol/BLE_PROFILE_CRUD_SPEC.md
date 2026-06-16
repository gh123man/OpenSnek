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
| `0B 04 01 00` | write | 38-byte DPI table | live DPI projection |
| `0B 84 01 00` | read | 36-byte DPI table | live DPI readback after projection |

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

Status: not mapped.

Needed capture:

- Create a new profile in Synapse, with no setting edits beyond whatever Synapse
  does automatically.
- Prefer starting from a known profile count and record the new GUID/name.

Questions to answer:

- Does Synapse allocate a new stored/profile target byte on the device?
- Is there an explicit create/allocate command, or only host-side GUID creation
  followed by writes to an existing target?
- Are `08 05`, `08 06`, `08 07`, or `01 8C` involved in allocation?

## Update

Status: partially mapped for setting projection and button/DPI writes.

Confirmed update surfaces:

- Live DPI table: `0B 04 01 00`
- Live button binding: `08 04 01 <slot>`
- Stored/profile button binding candidates: `08 04 <target> <slot>`

Needed capture:

- On one known profile, change exactly one button binding.
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

Status: likely host-only, not confirmed.

Needed capture:

- Rename a profile without changing any settings.

Questions to answer:

- Does any BLE traffic occur beyond normal background traffic?
- Are names stored on-device at all?

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
2. Rename that disposable profile.
3. Update one setting on the active disposable profile.
4. Update one setting on an inactive profile.
5. Delete the disposable profile.
