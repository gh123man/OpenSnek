# Basilisk V3 Pro Bluetooth Profile CRUD Draft

This is the implementation-facing working spec for Basilisk V3 Pro Bluetooth
profile support. It is capture-backed but still incomplete; use it as the place
to accumulate the CRUD model before promoting behavior into Swift.

Primary evidence:

- `captures/ble/windows/2026-06-15-195434-profile-button-cycle-focused-pass-4/`
- `captures/ble/windows/2026-06-15-202616-profile-inventory-read-path-pass-1/`
- `captures/ble/windows/2026-06-15-224531-profile-synapse-startup-takeover-pass-1/`
- `captures/ble/windows/2026-06-15-225000-profile-active-target0-dpi-surface/`

## Current Answer

The current corpus is enough to draft the onboard profile API shape, but not
enough to ship a full safe profile manager yet.

What is now strong enough to build against experimentally:

- stored target create/rewrite uses `03 04` metadata chunks plus stored target
  setting writes, with `08 05`/`08 07`/`03 05` apply/control candidates
- a live macOS probe replayed the target-`2` create flow and registered stored
  slot `1` in `03 80 00 00` as target `2`
- stored target delete/unassign is `03 06 <target> 00` with an empty payload
- target inventory has a strong read candidate: `03 80 00 00`
- active target ID has a live-validated read: `03 82 00 00`
- target metadata has a strong read candidate: `03 84 <target> 00` with
  offset/length payloads
- button edits use the stored target first and then project to target `1`
- live macOS probing validated stored-only updates for an inactive target:
  target `3` accepted and read back DPI, Button5, brightness, and static
  scroll-wheel color changes while `03 82` stayed on target `1`
- firmware profile-button presses are detectable through passive HID reports
  `04 04 ...` followed by `05 05 39 ...`
- after that HID hint, `03 82 00 00` identifies the active target directly;
  `0B 82 00 00` remains the DPI-fingerprint fallback/validation path
- stored profile create/rewrite captures include a target-addressed brightness
  write on `10 05 <target> 00`; this proves at least one lighting byte is part
  of the stored-profile transaction

What is still not strong enough to ship by default:

- a direct active profile selector write
- complete create target allocation rules
- a proven device-side rename/update path for existing profile metadata
- exact behavior when multiple onboard slots have identical DPI fingerprints
- an atomic "read/write whole profile as one blob" command
- a complete per-profile lighting effect model; stored brightness and static
  zone color now have read/write shapes, but advanced/effect payloads are not
  decoded

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
| Hardware-active setting surface | Target byte `0` on active read families such as `0B 81/82/83`, `08 84`, `10 85`, and `10 83` | After firmware cycling to target `3`, target `0` read back target `3` DPI, Button5, brightness, and static color |
| Active profile target | `03 82 00 00` returns the active/cycle-selected target byte | Live macOS probe changed `03 82` from `01` to `02` to `03` as the firmware profile button moved across targets |
| Active profile settings | Synapse-open: host-side Synapse state plus projected target `1`; Synapse-closed: firmware-selected onboard target, with target `0` reads mirroring active settings | Selection captures produce projection bursts; firmware-cycle captures update target `0` DPI/lighting/button surfaces |
| Device-native target inventory | Partially mapped through `03 80 00 00` and `03 84 <target> 00` | Startup capture returned target lists and chunked metadata reads after wall-clock filtering |

Important distinction: selecting a profile in Synapse is not passive inventory.
The Windows profile-inventory capture shows that UI profile selection logs
`newActiveProfileGUID` and then sends live projection writes.

## Wire Keys Seen So Far

| Key | Direction | Observed payload/response | Working role |
|---|---|---|---|
| `01 86 00 00` | read | `00 00 00` | profile/session state read candidate before projection bursts |
| `01 82 00 00` | read | `03 00` | scalar state read candidate during projection |
| `01 8C <target> 00` | read | `01` for observed targets | stored/profile target state candidate |
| `03 80 00 00` | read | `01 02 03` in the filtered startup window | onboard target/profile list candidate |
| `03 82 00 00` | read | one-byte target ID (`01`, `02`, `03` live-validated) | current active profile target |
| `03 84 <target> 00` | read | offset/length request, chunked response | stored target metadata read candidate |
| `08 04 <target> <slot>` | write | 10-byte button action payload | button binding for stored/profile target or live target |
| `08 84 00 <slot>` | read | 16-byte packed button readback | hardware-active button binding after firmware profile cycling |
| `08 05 <target> 00` | write | `00` | profile/apply control candidate |
| `08 06 01 00` | write | `00` | profile/apply control candidate |
| `08 07 <target> 00` | write/read-like ACK | `00`, response `50` | profile/apply control candidate |
| `03 04 <target> 00` | write | chunked profile metadata | profile name/GUID/owner structure write |
| `03 05 <target> 00` | write | none | profile metadata/apply candidate |
| `03 06 <target> 00` | write | none | delete/unassign stored profile target from onboard cycle list |
| `0B 01 <target> 00` | write | 6-byte DPI scalar | stored/profile DPI scalar write candidate |
| `0B 04 01 00` | write | 38-byte DPI table | live DPI projection |
| `0B 04 <target> 00` | write | 38-byte DPI table | stored/profile DPI table write candidate |
| `0B 81/82/83 00 00` | read | scalar/stages/token | active hardware DPI surface after firmware profile cycling |
| `0B 81/82/83 <target> 00` | read | scalar/stages/token | stored target DPI fingerprint reads for targets `2..5` |
| `0B 84 01 00` | read | 36-byte DPI table | live DPI readback after projection |
| `10 85 <target> <led>` | read | brightness byte | stored/profile per-zone brightness read |
| `10 85 00 <led>` | read | brightness byte | hardware-active per-zone brightness read after firmware profile cycling |
| `10 05 <target> 00` | write | brightness byte | stored/profile brightness write observed during create/rewrite and live stored-update probe |
| `10 83 <target> <led>` | read | 10-byte static/effect zone state | stored/profile lighting zone state read |
| `10 83 00 <led>` | read | 10-byte static/effect zone state | hardware-active lighting zone state after firmware profile cycling |
| `10 03 <target> <led>` | write | 10-byte static-zone state | stored/profile static color write |
| `10 85 01 <led>` | read | brightness byte | live V3 Pro per-zone brightness read |
| `10 05 01 <led>` | write | brightness byte | live V3 Pro per-zone brightness write |
| `10 83 00 <led>` | read | 10-byte static-zone state | live V3 Pro per-zone static color read |
| `10 03 00 <led>` | write | 10-byte static-zone state | live V3 Pro per-zone static color write |

The `01 xx` and `08 05` / `08 06` / `08 07` families are still research-only.
Do not ship writes to those keys until we safely probe them outside Synapse.
The `03 80`, `03 82`, `03 84`, and `0B 81/82/83` reads are safer candidates, but still
need Swift-side implementation and error handling before they become product
features.

Lighting scope note:

- `10 05 <target> 00` writes a profile-scoped brightness byte. After writing
  `0xc8` to target `3`, `10 85 03 <led>` returned `c8` for the tested V3 Pro
  LEDs while live `10 85 01 <led>` stayed at `54`.
- `10 85 <target> 00` is not the stored brightness read; target `2`/`3` with
  `<led> = 00` returned error status.
- `10 03 <target> <led>` writes a stored/profile static-zone payload and
  `10 83 <target> <led>` reads it back. Target `3`, LED `0x01` accepted and
  returned `01 00 00 01 12 34 56 00 00 00` while live `10 83 00 01` remained
  white.
- Unedited stored zones can return an effect-shaped payload such as
  `03 01 28 01 00 ff 00 00 ff 00`; the advanced/effect-state schema is still
  unmapped even though static-zone payloads are now validated.

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
- In the wall-clock-filtered Synapse startup capture, `03 80 00 00` returned a
  compact onboard target list candidate (`01 02 03`) and Synapse then read
  metadata chunks through `03 84 02 00` and `03 84 03 00`.
- Live macOS probing found that `03 82 00 00` returns the active target byte.
  It returned `02` when stored target `2` was active, `01` after cycling back to
  the default/live target, and `03` after creating/cycling to target `3`.
- `03 84 <target> 00` uses a 4-byte request payload that looks like
  `<offset_le16><length_le16>`; response chunks include GUID bytes, ASCII/UTF-8
  profile names, and owner hash fragments in the same structure family as
  create-time `03 04` metadata writes.
- Live macOS readback of the profiles created by `OpenSnekProbe` confirmed the
  UUID/name fields are device-backed for those targets:
  - target `2`: GUID `3a35ec93-bee1-4b29-9d3d-0d2b88f9edef`, name `OPENSNEK_MAC_SLOT_1`
  - target `3`: GUID `3bdbc397-3075-4beb-8f8a-34c45b186ff9`, name `OPENSNEK_MAC_SLOT_3`

What is not confirmed:

- Whether `03 80 00 00` is the complete onboard profile slot list, an enabled
  target list, or only the set Synapse chose to inspect in that startup state.
- Whether `03 84` always maps a stored/profile target byte to a Synapse GUID
  across reconnect, delete/recreate, and host changes.
- Whether `03 82 00 00` is stable across reconnects and every transport-owned
  state, though current live evidence strongly supports it as the active target
  read.
- Whether `01 8C <target> 00` is an existence check, enable flag, dirty flag, or
  another stored-target state.

Implementation guidance:

- Treat target `1` as the Synapse live projection surface for existing
  setting writes.
- Treat target `0` on `0B 81/82/83` as the hardware-active DPI identity surface,
  not as the same thing as target `1`.
- Treat stored/profile targets as opaque numeric targets until read/create/update
  captures prove stable semantics across reconnects.
- Read device-backed UUID/name metadata where available, but keep OpenSnek's
  host profile mapping canonical until reconnect, delete/recreate, and rename
  semantics are validated.

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
- Firmware/onboard profile-button activation is a separate path: detect the
  passive HID hint, then read `03 82 00 00` for the active target. Use
  `0B 82 00 00` only as a fallback or validation fingerprint.

## Create

Status: mapped for one Synapse-created profile into stored/profile target `2`
and live-validated on macOS for replacing stored slot `1` / target `2`.

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

Live macOS probe validation:

```bash
swift run --package-path OpenSnek OpenSnekProbe bt-profile-create \
  --stored-slot 1 \
  --profile-name OPENSNEK_MAC_SLOT_1 \
  --values 400,800,1600,3200,6400 \
  --active 3 \
  --yes \
  --name "BSK V3 PRO"
```

The probe replayed the target-`2` sequence above with a generated GUID
`3a35ec93-bee1-4b29-9d3d-0d2b88f9edef`. Each write/control step returned the
normal BLE success status (`0x02`). After stale notifies settled, readback showed:

```text
03 80 00 00 -> 01 02
0B 81 02 00 -> 1600x1600
0B 82 02 00 -> 400,800,1600,3200,6400
0B 83 02 00 -> 0x03
```

That is enough to treat the create replay as a working stored-slot replacement
for target `2` in this device state. It does not prove general free-slot
allocation rules; the command is intentionally guarded by `--yes` because it
clears/replaces the target.

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

Live metadata readback:

`03 84 <target> 00` is a write-framed read: send a 4-byte request payload with
`<offset_le16><length_le16>`, then parse the returned metadata bytes.

Examples validated on macOS after `OpenSnekProbe bt-profile-create`:

| Target | Request | Returned identity |
|---:|---|---|
| `2` | `03 84 02 00` + `00 00 4c 00` | GUID `3a35ec93-bee1-4b29-9d3d-0d2b88f9edef`, name `OPENSNEK_MAC_SLOT_1` |
| `3` | `03 84 03 00` + `00 00 4c 00` | GUID `3bdbc397-3075-4beb-8f8a-34c45b186ff9`, name `OPENSNEK_MAC_SLOT_3` |
| `3` | `03 84 03 00` + `4c 00 4c 00` | owner hash chunk beginning with `31933b5452df5708882d...` |

This proves UUID/name metadata is stored on the device for the created targets.
It does not prove standalone rename safety; the earlier Synapse rename-only
captures did not emit a metadata rewrite, so OpenSnek should treat isolated
metadata updates as experimental until directly validated.

Open questions:

- Whether Synapse chose target `2` because it was the first recyclable/free OBM
  slot, because a previous slot `2` profile was replaced, or because creation
  always starts there in this state.
- Whether `03 06 02 00` is a delete/clear/prepare command. Synapse logs mention
  `obmEngineMouse.deleteProfile(2)` before the add completes, suggesting it may
  clear the target before rewriting it.
- Whether create without a rename prompt would write the same metadata once with
  the default duplicated name.

### Recreate After Delete

Live macOS validation recreated deleted target `3` with
`OpenSnekProbe bt-profile-create --stored-slot 2`. The sequence re-added target
`3` to inventory:

```text
03 80 00 00 -> 01 02 03
03 84 03 00 -> new UUID/name metadata
10 85 03 <led> -> recreated brightness
```

One important caveat: in this recreate pass, the `0B 04 03 00` stored DPI stage
write returned status `0x01`, and readback showed the old stage table remained.
Retrying the same `0B 04 03 00` payload returned status `0x02` and read back
correctly as `760,960,1160,1360,1560` with token `04`.

Implementation guidance:

- Treat create/rewrite as a multi-step transaction with per-step ACK checks.
- Do not continue silently after a non-`0x02` write status.
- Read back every written surface before considering a stored profile valid.
- If one surface fails, the target can be partially rewritten; retry or rebuild
  the target from a known complete snapshot.

Reconnect persistence:

After Bluetooth disconnect/reconnect, the recreated target persisted:

```text
03 80 00 00 -> 01 02 03
03 82 00 00 -> 01
03 84 03 00 + 00 00 4c 00 -> GUID/name OPENSNEK_RECREATE_SLOT_2
03 84 03 00 + 4c 00 4c 00 -> owner hash chunk
0B 81/82/83 03 00 -> 1360x1360, stages 760,960,1160,1360,1560, token 04
10 85 03 <led> -> 60
```

This proves the create/recreate path persisted inventory, metadata, DPI, and
brightness across a fresh Bluetooth session. The active target reset to `1` on
this reconnect.

## Update

Status: mapped for active-profile single button binding writes and active
saved-slot DPI edits; partially mapped for inactive stored-target updates.

Confirmed update surfaces:

- Live DPI table: `0B 04 01 00`
- Live button binding: `08 04 01 <slot>`
- Stored/profile DPI scalar/table: `0B 01 <target> 00`, `0B 04 <target> 00`
- Stored/profile button binding: `08 04 <target> <slot>`
- Stored/profile brightness: `10 05 <target> 00`
- Stored/profile static zone color: `10 03 <target> <led>`

### Stored-Only Update Probe

Live macOS validation on the connected `BSK V3 PRO` updated inactive target `3`
without projecting to live target `1`.

Baseline before the update:

```text
03 80 00 00 -> 01 02 03
03 82 00 00 -> 01
target 0 DPI -> 600,800,1000,1200,1400
target 3 DPI -> 700,900,1100,1300,1500
live lighting -> brightness 0x54, color ffffff
```

Stored-only writes sent:

| Surface | Key | Payload | Readback |
|---|---|---|---|
| DPI scalar | `0B 01 03 00` | `46 05 46 05 00 00` (`1350x1350`) | `0B 81 03 00 -> 1350x1350` |
| DPI stages | `0B 04 03 00` | active token `04`, stages `750,950,1150,1350,1550` | `0B 82/83 03 00 -> same stages, token 04` |
| Button5 | `08 04 03 05` | `03 05 00 02 02 00 0a 00 00 00` | `08 84 03 05` even lane `02 02 00 0a 00 00 00` |
| Brightness | `10 05 03 00` | `c8` | `10 85 03 <led> -> c8` for tested LEDs |
| Scroll-wheel static color | `10 03 03 01` | `01 00 00 01 12 34 56 00 00 00` | `10 83 03 01 -> same payload` |

After these writes:

```text
03 80 00 00 -> 01 02 03
03 82 00 00 -> 01
target 0 DPI -> 600,800,1000,1200,1400
live Button5 -> default mouse Button5
live lighting -> brightness 0x54, color ffffff
```

This proves mapped stored-target surfaces can be updated while inactive and read
back without immediately changing the live/projection layer.

Physical profile-cycle validation:

After one physical profile-cycle button press, the passive HID watcher saw the
expected hint pair and `03 82 00 00` moved to target `3`. The target-`0`
hardware-active surfaces then mirrored stored target `3`:

| Surface | Hardware-active read | Result |
|---|---|---|
| Active target | `03 82 00 00` | `03` |
| DPI | `0B 81/82/83 00 00` | `1350x1350`, stages `750,950,1150,1350,1550`, token `04` |
| Brightness | `10 85 00 <led>` | `c8` for tested LEDs |
| Static scroll-wheel color | `10 83 00 01` | `01 00 00 01 12 34 56 00 00 00` |
| Button5 | `08 84 00 05` | same packed lanes as stored target `3`, including keyboard HID `0x0a` |

Live/projection target `1` stayed on the old values (`0x54` brightness, white
static color, default Button5). This confirms the practical runtime model:
after firmware/onboard cycling, use `03 82` for identity and target `0` reads
for active hardware state; target `1` is a separate host/live projection bank.

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

### Attempted Inactive Saved-Slot Button Update

Captures:

- `captures/ble/windows/2026-06-15-213442-profile-inactive-saved-slot-button-update-pass-1/`
- `captures/ble/windows/2026-06-15-213655-profile-inactive-saved-slot-button-update-pass-2/`

Pass 1 was intended to change one button on an inactive saved/onboard profile,
but the user accidentally changed DPI instead. Treat it as an invalid button
mapping pass. It produced another active-profile/live-target DPI projection and
does not answer inactive button behavior.

Pass 2 captured a Button5 keyboard assignment intended for a saved/onboard slot
that was not meant to be the live profile. Synapse's model did not expose a
clean offline-only edit: the in-window active-profile log showed `OS_P5` with
the new Button5 mapping, and the wire trace wrote both stored target `5` and
live target `1`.

Relevant pass 2 writes:

| Event | Key | Payload | Interpretation |
|---|---|---|---|
| Button5 -> keyboard HID `0x09` | `08 04 05 05` | `05 05 00 02 02 00 09 00 00 00` | stored target `5`, slot `0x05` |
| Button5 -> keyboard HID `0x09` | `08 04 01 05` | `01 05 00 02 02 00 09 00 00 00` | immediately project same binding to live target `1` |

No profile metadata rewrite (`03 04`), target add/delete (`03 05`/`03 06`),
profile apply (`08 05`/`08 07`), DPI table write, or brightness write occurred
in the pass 2 in-window operation.

Implementation guidance:

- Synapse's editable-profile UI appears to converge on the same stored-then-live
  write shape for button edits: `08 04 <stored-target> <slot>`, then
  `08 04 01 <slot>`.
- This pass does not prove a pure offline inactive-slot write path because
  selecting a profile for editing in Synapse makes that profile live, then
  Synapse projects the edited mapping to live target `1`.
- For an OpenSnek-owned profile manager, inactive profile edits can remain
  host-side until the user selects/projects that profile. When projecting a
  selected profile, write the stored target first if it is assigned, then write
  live target `1`.

### Attempted Inactive Saved-Slot DPI Update

Capture:

- `captures/ble/windows/2026-06-15-214111-profile-inactive-saved-slot-dpi-update-pass-1/`

This pass was intended to modify one DPI value on a saved/onboard profile that
was not currently live. Synapse does not expose that as a true offline edit:
selecting the profile in the UI made it live before the edit. Synapse logged:

- `set active profile ... 27530668-c3e2-4e0a-a06e-a4854383c4e9`
- `[Armory] Active profile ... "name":"OS_P4_RENAMED"`
- `profileIdList":[1,2,4,5]`

The in-window BLE traffic used only live target `1` DPI writes:

| Event | Key | Payload/response | Interpretation |
|---|---|---|---|
| Selection/activation projection | `0B 04 01 00` | `03 05 00 90 01 90 01 00 00 01 20 03 20 03 00 00 02 40 06 40 06 00 00 03 80 0C 80 0C 00 00 04 00 19 00 19 00 00 00` | live target `1`, active token `3`, table `400`, `800`, `1600`, `3200`, `6400` |
| DPI edit | `0B 04 01 00` | `02 05 00 90 01 90 01 00 00 01 9C 18 9C 18 00 00 02 40 06 40 06 00 00 03 80 0C 80 0C 00 00 04 00 19 00 19 00 00 00` | live target `1`, active token `2`, table `400`, `6300`, `1600`, `3200`, `6400` |
| DPI edit readback | `0B 84 01 00` | `02 05 01 90 01 90 01 00 00 02 9C 18 9C 18 00 00 03 40 06 40 06 00 00 04 80 0C 80 0C 00 00 05 00 19 00 19 00` | live target readback confirms `6300` second stage |
| Revert/projection | `0B 04 01 00` | `02 05 00 90 01 90 01 00 00 01 20 03 20 03 00 00 02 40 06 40 06 00 00 03 80 0C 80 0C 00 00 04 00 19 00 19 00 00 00` | live target `1`, active token `2`, table `400`, `800`, `1600`, `3200`, `6400` |

No stored-target DPI table write (`0B 04 <stored-target> 00`) occurred in this
attempted inactive DPI update pass.

Implementation guidance:

- Synapse UI cannot be used as evidence for a pure offline inactive DPI update
  path because selecting an assigned profile makes it live.
- OpenSnek should treat inactive profile DPI edits as host-side snapshot changes
  until the user activates/projects that profile.
- When projecting the selected profile, write live target `1` with `0B 04 01 00`.
  Stored-target DPI writes remain limited to create/rewrite flows until a
  non-UI API or firmware behavior proves otherwise.

### Noisy Active Saved-Slot DPI Update

Capture:

- `captures/ble/windows/2026-06-15-212318-profile-active-saved-slot-dpi-update-pass-1/`

This pass was intended to update one DPI stage on the active saved/onboard
profile. The actual user action included multiple profile switches and several
DPI changes, so this capture is evidence for traffic shape but not a clean
single-operation proof.

Early in the capture Synapse rebuilt/added target `2` for profile GUID
`26a33407-4094-469b-b3b1-f3caae38693b`
(`Brian's MacBook Pro (2)-Default`). That full stored-target rewrite included:

| Key | Payload | Interpretation |
|---|---|---|
| `03 05 02 00` | empty | target prepare/add candidate |
| `08 05 02 00` | `00` | stored target apply/flag candidate |
| `01 8C 02 00` | read response `01` | stored target presence/read candidate |
| `08 07 02 00` | `00` | stored target apply/flag candidate |
| `03 04 02 00` | four chunked metadata writes | stored target GUID/name/owner metadata |
| `0B 01 02 00` | `20 03 20 03 00 00` | stored target current DPI scalar candidate (`800`, `800`) |
| `0B 04 02 00` | DPI table | stored target DPI table: `400`, `800`, `1600`, `3200`, `6400` |
| `10 05 02 00` | `54` | stored target brightness candidate |
| `08 04 02 04` | `02 04 00 02 02 00 45 00 00 00` | stored target button-slot write |

The later DPI edits and profile projections in the same wall-clock capture
window used live target `1` only:

| Event | Key | Decoded DPI table | Interpretation |
|---|---|---|---|
| Active-profile DPI edit | `0B 04 01 00` | `400`, `7150`, `1600`, `3200`, `6400` | live target DPI projection/edit |
| Revert/projection | `0B 04 01 00` | `400`, `800`, `1600`, `3200`, `6400` | live target DPI projection |
| Other profile projection | `0B 04 01 00` | `600`, `800`, `1000`, `1200`, `1400` | live target DPI projection |
| Other profile DPI edit | `0B 04 01 00` | `600`, `5250`, `1000`, `1200`, `1400` | live target DPI projection/edit |

Current implementation guidance:

- Do not treat this noisy pass as proof that active DPI edits are live-only.
- The pass does show that simple DPI changes during active profile UI work can
  be represented as `0B 04 01 00` live target writes, while the observed
  `0B 04 02 00` stored-target DPI table belonged to a broader target add/rewrite.
- The clean pass below confirms the active saved/onboard DPI edit path as a
  live-target write with no stored-target DPI table write.
- Persisting DPI directly into an existing stored/onboard target remains
  research-only outside of create/rewrite flows.

### Active Saved-Slot DPI Update

Capture:

- `captures/ble/windows/2026-06-15-213027-profile-active-saved-slot-dpi-update-clean-pass-1/`

The active profile was `Brian's MacBook Pro (2)-Default`:

- GUID: `26a33407-4094-469b-b3b1-f3caae38693b`
- OBM slot/profile ID: `2` (`"obmSlotId":[2]` in Synapse logs)

The pass contains some Synapse activation replay near the end of the capture,
including a live DPI projection, a stored button replay on target `2`, and a
matching live button replay. The actual DPI edit then changed stage 1 from
`400` to `7650` and changed the active DPI stage token from `2` to `1`.

Relevant writes:

| Event | Key | Payload/response | Interpretation |
|---|---|---|---|
| Activation replay DPI projection | `0B 04 01 00` | `02 05 00 90 01 90 01 00 00 01 20 03 20 03 00 00 02 40 06 40 06 00 00 03 80 0C 80 0C 00 00 04 00 19 00 19 00 00 00` | live target `1`, active token `2`, table `400`, `800`, `1600`, `3200`, `6400` |
| Activation replay stored button | `08 04 02 04` | `02 04 00 02 02 00 45 00 00 00` | stored target `2`, Button4 `KEY_F12` |
| Activation replay live button | `08 04 01 04` | `01 04 00 02 02 00 45 00 00 00` | live target `1`, Button4 `KEY_F12` |
| DPI edit | `0B 04 01 00` | `01 05 00 E2 1D E2 1D 00 00 01 20 03 20 03 00 00 02 40 06 40 06 00 00 03 80 0C 80 0C 00 00 04 00 19 00 19 00 00 00` | live target `1`, active token `1`, table `7650`, `800`, `1600`, `3200`, `6400` |
| DPI edit readback | `0B 84 01 00` | `01 05 01 E2 1D E2 1D 00 00 02 20 03 20 03 00 00 03 40 06 40 06 00 00 04 80 0C 80 0C 00 00 05 00 19 00 19 00` | live target readback confirms `7650` first stage |

No stored-target DPI table write (`0B 04 02 00`) occurred in this active
saved-slot DPI edit pass.

Implementation guidance:

- Updating DPI for the currently active saved/onboard profile should write the
  live target with `0B 04 01 00`.
- Synapse does not appear to persist this active DPI edit directly to the stored
  target on the device. OpenSnek should persist the profile snapshot in its own
  host-side profile model and apply it to live target `1` when that profile is
  selected.
- Do not write `0B 04 <stored-target> 00` for an active DPI edit unless a later
  inactive-profile capture proves the stored-target update path and safety.

## Delete

Status: mapped for saved-slot unassign/`None` on one target.

Capture:

- `captures/ble/windows/2026-06-15-205659-profile-slot-unassign-none-pass-1/`
- `captures/ble/windows/2026-06-15-210321-profile-active-slot-unassign-cycle-pass-1/`

Setting an assigned saved/onboard slot to `None` in Synapse logged:

- `obmEngineMouse.deleteProfile(3)`
- `profileIdList":[1,4,5,2]`
- `numOfProfiles":4`
- `remove OBM result ...`

The capture contains buffered BTVS packets from before the wrapper's wall-clock
capture start. Filtering by `metadata.json` `captureStart`/`captureEnd` leaves
one non-lighting vendor operation in the actual 60-second capture window:

| Wall time | Key | Payload | Status | Interpretation |
|---|---|---|---|---|
| `20:58:05.994` | `03 06 03 00` | empty | `02` | delete/unassign stored target `3` |

The Synapse `deleteProfile(3)` event followed at `20:58:06.175`, about 181 ms
after the BLE write.

Active-target unassign capture:

- Synapse logged `obmEngineMouse.deleteProfile(2)`.
- The OBM profile list changed to `profileIdList":[1,4,5]` and
  `numOfProfiles":3`.
- The delete write was `03 06 02 00` with empty payload and status `02`.
- No immediate replacement live projection was sent by the delete itself.

Live macOS target-`3` delete validation:

After stored-only update and activation testing, target `3` was active and
inventory was `01 02 03`. Sending `03 06 03 00` with an empty payload returned
success status `0x02`.

Immediate readback after delete:

```text
03 80 00 00 -> 01 02
03 82 00 00 -> 03
01 8C 03 00 -> 01
03 84 03 00 -> target 3 UUID/name metadata still readable
0B 81/82/83 03 00 -> target 3 DPI still readable
10 85/10 83 03 <led> -> target 3 lighting still readable
```

So `03 06 <target> 00` removes the target from the cycleable inventory, but it
does not immediately erase target metadata/settings banks and does not force the
active target to change if that target was active.

After one physical profile-cycle button press:

```text
03 80 00 00 -> 01 02
03 82 00 00 -> 01
target 0 DPI -> 600,800,1000,1200,1400
target 0 brightness -> 0x54
target 0 static color -> ffffff
target 0 Button5 -> default mouse Button5
```

This confirms firmware skips the unassigned target on the next cycle and returns
to a target in the inventory ring. OpenSnek should remove deleted targets from
its cycleable profile list immediately, but should not assume `03 06` securely
erases or invalidates all per-target readbacks.

After the active target was unassigned, pressing the physical profile button
while Synapse was open produced Synapse software `navigateProfile` events. This
path appears to cycle over a hybrid Synapse host profile list, not only the
mouse's OBM/on-device `profileIdList`: it can select locally stored Synapse
profiles, on-device-backed profiles, and stale host profiles that are no longer
present in the OBM list. Observed post-delete selections included:

| Rel s | GUID | Name |
|---:|---|---|
| `3.269` | `cbb11d67-38cd-46db-bc16-a95424aaee61` | `OPENSNEK_CAPTURE_1_foo` |
| `5.903` | `a5c15916-b5fd-4f33-8408-d978cd3bf37c` | `OPENSNEK_RENAME_PROBE_1` |
| `8.324` | `27530668-c3e2-4e0a-a06e-a4854383c4e9` | `OS_P4_RENAMED` |
| `10.116` | `18f2a4cc-ecb8-4765-b532-9df401a686d6` | `OS_P5` |

Treat those post-delete `navigateProfile` selections as Synapse host-state/UI
behavior, not as authoritative onboard-cycle inventory. A firmware-only cycle
test should be done with Synapse closed if we need to prove exactly what the
mouse does without Synapse's software profile navigator.

Synapse-closed Bluetooth cycle captures:

- `captures/ble/windows/2026-06-15-214518-profile-synapse-closed-physical-cycle-pass-1/`
- `captures/ble/windows/2026-06-15-215545-profile-bt-hardware-cycle-synapse-closed-pass-1/`
- `captures/ble/windows/2026-06-15-222336-profile-cycle-event-driven-followup-read/`
- `captures/ble/windows/2026-06-15-225000-profile-active-target0-dpi-surface/`
- `captures/ble/windows/2026-06-15-224531-profile-synapse-startup-takeover-pass-1/`

The user closed/crashed Synapse and pressed the physical profile button during
60-second BTVS captures. The first capture contained no decoded BLE vendor
writes or notify responses, and no matching Synapse events occurred in the
capture window. During the second capture, the user confirmed that the bottom
LED advanced, so the mouse did perform a firmware/onboard profile cycle.

Important timing note for the second capture: `summary.md` lists three decoded
vendor reads (`01 86 00 00`, `01 90 00 01`, `05 81 00 01`), but absolute
packet timestamps place those frames before the wrapper's `captureStart`. Treat
them as buffered/stale BTVS traffic, not as in-window profile-cycle behavior.
In the actual 60-second window, no decoded vendor write/read/notify identified
the new active profile.

BTVS did show malformed/short ATT notifications on handle `0x001b` during the
wall-clock capture window. These clustered near the button-press activity but
BTVS did not expose payload bytes:

| Cluster | Count | Start | End | Duration |
|---:|---:|---|---|---:|
| `1` | `21` | `21:55:57.009` | `21:55:57.196` | `0.187s` |
| `2` | `73` | `21:56:01.608` | `21:56:02.289` | `0.681s` |
| `3` | `122` | `21:56:08.164` | `21:56:09.969` | `1.805s` |

Companion Windows HID sniffing of the Basilisk V3 Pro Bluetooth HID collections
captured a clearer passive signal. With Synapse closed, three physical
profile-button presses produced exactly two 9-byte reports per press on the
Bluetooth HID collection with usage page `0x01`, usage `0x00`:

| Press | First report | Follow-up report | Gap |
|---:|---|---|---:|
| `1` | `04 04 00 00 00 00 00 00 00` | `05 05 39 00 00 00 00 00 00` | `0.201s` |
| `2` | `04 04 00 00 00 00 00 00 00` | `05 05 39 00 00 00 00 00 00` | `0.203s` |
| `3` | `04 04 00 00 00 00 00 00 00` | `05 05 39 00 00 00 00 00 00` | `0.203s` |

Treat these passive HID reports as a firmware profile-cycle hint, not as a
decoded active profile ID. This is enough for a real-time OpenSnek UI without
continuous current-profile polling: the HID hint is the event, and OpenSnek
should perform a small one-shot follow-up active-target read only after that
event arrives.

Follow-up read validation:

The event-driven watcher capture used a deliberately distinctive profile setup:
the active profile had a DPI table shaped like `100, 100, 100, 100, 800` while
another profile had random DPI settings. With Synapse closed, three physical
profile-button presses generated the expected HID hint pairs and each hint
triggered exactly one `0B 84 01 00` read. A second pass pressed the profile
button once, waited 2 seconds after the HID hint, then read both `0B 84 01 00`
and button slot `08 84 01 04`.

Observed result:

| Pass | Trigger | Follow-up reads | Result |
|---|---|---|---|
| 3-press event-driven pass | `04 04 ...` / `05 05 39 ...` per press | `0B 84 01 00` after each debounced hint | DPI table stayed `100,100,100,100,800` |
| 1-press delayed pass | `04 04 ...` / `05 05 39 ...` | 2-second delay, then `0B 84 01 00` and `08 84 01 04` | DPI table and button payload stayed unchanged |

This means the HID report is enough to avoid continuous polling for change
detection, but the currently known live-target readback keys are not enough to
identify the firmware-ring active profile after a Synapse-closed onboard cycle.
They appear to read the current BLE live/software projection surface, which did
not move with the hardware profile ring in these passes.

The later active target-`0` DPI sweep fills that specific gap for distinctive
DPI profiles: use `0B 82 00 00`, not `0B 84 01 00`, to fingerprint the
hardware-selected onboard profile.

No-profile live macOS qualification:

A later live macOS probe pass had no apparent stored/cycleable profiles loaded.
`03 80 00 00` returned only `01`, the active hardware DPI table was
`600,800,1000,1200,1400`, and no stored target table matched it. Pressing the
physical profile button while the probe was listening on the validated BLE HID
interface produced no `04 04 ...` / `05 05 39 ...` hint and no active
`0B 82 00 00` change. Treat this as evidence that the passive profile-button
hint may only be emitted when the firmware actually performs a profile
transition; a single-target/no-stored-profile state can make the button a no-op.

One-profile live macOS validation:

After replaying the target-`2` create flow above, the physical profile button
worked again and a Swift `IOHIDDeviceRegisterInputReportCallback` watcher on the
Bluetooth HID collection captured the expected pair:

```text
04 04 00 00 00 00 00 00 00
05 05 39 00 00 00 00 00 00
```

A follow-up BLE read immediately after that button press showed the hardware
active target changed from the prior live table to the stored target-`2` table:

```text
before: 0B 82 00 00 -> 600,800,1000,1200,1400
after:  0B 82 00 00 -> 400,800,1600,3200,6400
03 80 00 00 -> 01 02
```

The all-target debug scan also found hidden target banks with the same
`400,800,1600,3200,6400` table. For UI identity, prefer inventory-listed
cycleable targets from `03 80 00 00`; in this pass target `2` was the only
inventory-listed stored target, so the profile-button transition identified
stored slot `1`.

Direct active-target validation:

Follow-up live macOS probing found a simpler read:

```text
03 82 00 00 -> <active-target>
```

Observed sequence:

| State | `03 82 00 00` | Validation |
|---|---:|---|
| target `2` active after cycling to stored slot `1` | `02` | `0B 82 00 00` matched target `2` |
| cycled back to default/live target | `01` | `0B 82 00 00` returned `600,800,1000,1200,1400` |
| created target `3` with `700,900,1100,1300,1500`, then cycled to it | `03` | `0B 82 00 00` matched target `3` |

This makes `03 82 00 00` the preferred current-active-profile read. The
fingerprint read (`0B 82 00 00`) is still useful as a fallback, for validation,
and for detecting inconsistent/ambiguous firmware state.

Active DPI target correction:

The user clarified OpenSnek's slot terminology for this work:

- slot `0` means the live/current profile surface
- slots `1..4` mean non-live onboard slots
- BLE target `1` maps to live slot `0` for the older projection table key
  `0B 84 01 00`
- BLE targets `2..5` map to stored slots `1..4`

A follow-up read-only DPI-family sweep found the active firmware DPI surface in
the `0B 81/82/83 00 00` keys:

| Key | Payload shape | Working meaning |
|---|---|---|
| `0B 81 00 00` | 6-byte DPI scalar pair | current active DPI scalar for the hardware-selected profile |
| `0B 82 00 00` | 30-byte list of five 6-byte DPI pairs | current active profile's DPI stages, without stage IDs |
| `0B 83 00 00` | 1 byte | current active stage token/index for the hardware-selected profile |

The same keys with stored targets read the stored slots:

| Stored slot | BLE target | Example table |
|---:|---:|---|
| slot `1` | target `2` | `3200, 10200, 1600, 7900, 1100` |
| slot `2` | target `3` | `100, 100, 100, 100, 800` |
| slot `3` | target `4` | `400, 800, 1600, 3200, 6400` in this state, but user says this slot was not intentionally mapped |
| slot `4` | target `5` | `400, 800, 1600, 3200, 6400` in this state, but user says this slot was not intentionally mapped |

In `profile-cycle-active-target0-short-2026-06-15.json`, the before/after state
proved the active target behavior:

| Moment | `0B 82 00 00` active table | Matching stored target |
|---|---|---|
| before | `3200, 10200, 1600, 7900, 1100` | target `2` / stored slot `1` |
| after one hardware profile-button cycle | `100, 100, 100, 100, 800` | target `3` / stored slot `2` |

The later `slot2-to-slot3` pass did not change the active target. The user
clarified that only stored slots `1` and `2` were intentionally mapped and slots
`3`/`4` were unmapped, so treat that pass as consistent with unmapped slots
being skipped or ignored rather than as a failure of the active-target model.

Synapse startup takeover capture:

The startup capture launched Synapse/AppEngine during a 60-second BTVS capture
while the mouse was in Bluetooth mode. BTVS emitted some buffered packets with
timestamps before the wrapper's `captureStart`; the analysis below filters to
the actual wall-clock capture window only.

Synapse logs first reported an active software profile:

- `activeProfile: 18f2a4cc-ecb8-4765-b532-9df401a686d6`
- name: `OS_P5`

The matching in-window BLE traffic did not contain a simple profile-button
binding rewrite such as `08 04 <target> 6A`. Instead, startup ownership looked
like a profile/apply and projection sequence:

| Rel s | Key | Payload / response | Working role |
|---:|---|---|---|
| `14.061` | `08 05 01 00` | write `00`, success | live target profile/apply control candidate |
| `14.094` | `08 07 01 00` | write `00`, response `50` | live target profile/apply control candidate |
| `14.122` | `08 06 01 00` | write `00`, success | live target profile/apply control candidate |
| `14.147` | `0B 04 01 00` | table `100,100,100,100,800` | live DPI projection to target `1` / slot `0` |
| `14.175` | `00 81 00 00` | response `02 32 03 00` | device/profile state read candidate |
| `14.213` | `01 8C 01 00` | response `01` | live/stored target state check |
| `14.350` | `08 05 01 00` | write `00`, success | repeated live apply |
| `14.370` | `08 07 01 00` | write `00`, response `50` | repeated live apply |
| `14.394` | `08 06 01 00` | write `00`, success | repeated live apply |
| `14.470` | `0B 04 01 00` | table `100,100,100,100,800` | repeated live DPI projection |
| `14.589` | `03 80 00 00` | response `01 02 03` | onboard profile list / target inventory candidate |
| `14.670..14.972` | `03 84 02/03 00` | metadata chunks | profile metadata reads for stored targets |
| `15.001..15.145` | `0B 81/84 01/02/03 00` | DPI scalar/table reads | live and stored DPI inspection |
| `15.386..17.678` | `08 84 <target> <slot>` | button readbacks | button inventory reads for targets `1`, `2`, and `3`, including slot `0x6A` |
| `17.783` | `08 04 01 01` | button write | live target button rewrite during startup mapping restore |
| `17.880` | `08 04 01 05` | button write | live target Button5 rewrite |
| `18.039` | `08 04 03 05` | button write | stored target `3` Button5 rewrite |

Observed profile-button binding reads:

| Key | Response payload | Interpretation |
|---|---|---|
| `08 84 01 6A` | `6A 00 12 12 01 01 01 01 00 00 00 00 00 00 00 00` | live target profile-button binding read |
| `08 84 02 6A` | same shape | stored target `2` profile-button binding read |
| `08 84 03 6A` | same shape | stored target `3` profile-button binding read |

Live macOS probe validation also observed a non-duplicated 16-byte readback
after writing stored target `2`, Button5:

```text
08 84 02 05 -> 05 00 02 01 02 01 00 05 09 00 00 00 00 00 00 00
```

Read this as two interleaved 7-byte function-block lanes after the `slot,00`
prefix:

```text
even lane: 02 02 00 09 00 00 00  # keyboard-simple HID 0x09
odd lane:  01 01 05 00 00 00 00  # mouse Button5/default
```

The even lane matched the guarded stored-target write payload, proving the
stored button write can persist on target `2` even when `03 80 00 00` reports
only target `1`. The odd-lane semantics still need broader mapping before
product UI should expose this readback as a single definitive binding.

No `08 04 <target> 6A` write was observed in the filtered startup window. That
means Synapse's "software takeover" of the physical profile button is not
currently explained as a simple remap of slot `0x6A`. The most likely current
model is:

- Synapse starts by applying/projecting its selected software profile onto the
  live target.
- Synapse reads the hardware/profile-button binding and other button slots.
- Profile-button ownership may be host-side event handling of the hardware
  event stream, or a side effect of the `08 05` / `08 07` / `08 06` live apply
  sequence, rather than a dedicated `0x6A` binding rewrite.

OpenSnek should not copy this behavior by default. Firmware-first behavior means
leaving hardware profile cycling alone and using passive HID hints plus
`0B 82 00 00` active-DPI readback to refresh UI state.

User observation during these passes:

- In Bluetooth mode, the physical profile button does work as an onboard
  firmware profile switch when the mouse is not connected to Synapse.
- In USB mode, the same profile button also behaves as a hardware/onboard switch
  and can cycle profiles even when the mouse is not connected to a host.
- When connected to Synapse, both Bluetooth and USB profile-button behavior
  appears to be intercepted by Synapse as software navigation; on USB, the
  bottom LED no longer responds to button presses in that state.
- The bottom LED indicates whether the mouse is using hardware/onboard profile
  cycling or Synapse/software-owned profile navigation.

Treat Synapse's software takeover as a vendor UI behavior, not the desired
OpenSnek model. OpenSnek should be firmware-first: trust the mouse's onboard
profile-cycle behavior and avoid replacing it with host-side software cycling
unless the user explicitly opts into host-managed profiles.

Current implementation guidance:

- Treat saved-slot `None` as a target delete/unassign operation.
- Write `03 06 <target> 00` with no payload for the target being removed from
  the mouse's physical profile-cycle list.
- After deletion, remove the target from OpenSnek's host profile inventory and
  do not include it when cycling profiles.
- If the deleted target is active, `03 06` alone does not appear to force a
  replacement live projection. OpenSnek should explicitly select/project a
  remaining profile when it wants the active view to move immediately.
- On Bluetooth and USB, OpenSnek should prefer the firmware/onboard profile
  cycle behavior. Do not copy Synapse's software interception of the physical
  profile button by default.
- On Bluetooth, listen for passive HID profile-cycle hint reports such as
  `04 04 00 00 00 00 00 00 00` and `05 05 39 00 00 00 00 00 00` where the HID
  topology is capture-validated. Use them only as refresh triggers.
- Do not continuously poll the current profile just to detect onboard
  profile-button changes. The passive HID report is the detection path.
- After a profile-cycle hint, perform only event-scoped follow-up reads. Do not
  expect the HID report to carry a target ID.
- Prefer `03 82 00 00` to read the current active target directly.
- For validation or fallback, read the active hardware DPI surface:
  - `0B 82 00 00` for the active profile's stage values
  - `0B 81 00 00` for the active scalar/current DPI pair
  - `0B 83 00 00` for the active stage token
- If `03 82` is unavailable or inconsistent, match `0B 82 00 00` against stored
  slot tables read from `0B 82 02 00` through `0B 82 05 00` to infer which
  onboard slot the firmware selected.
- Do not use `0B 84 01 00` as the active hardware profile identity source. It
  reads the live/projection stage table with stage IDs, and it can remain pinned
  to the previous projected profile while the hardware ring changes.
- If multiple stored slots have identical DPI tables, DPI-only identity is
  ambiguous. Add another fingerprint axis before claiming exact profile
  identity.
- Do not send the Synapse startup takeover/apply sequence (`08 05` / `08 07` /
  `08 06`) as part of normal OpenSnek profile monitoring. It appears tied to
  Synapse software ownership and live projection.
- Host-side cycling should be an explicit OpenSnek-owned mode, not the default
  behavior for onboard profile slots.
- Do not infer target deletion from a Synapse rename alone. Synapse currently
  appears to have a UI/state bug where renaming can unassign a profile from a
  saved slot while the Synapse-handled physical profile button may still select
  that stale host profile.

Open questions:

- Whether passive profile-cycle hint reports encode any additional state beyond
  "a profile-cycle event happened." The current Windows HID sniff did not decode
  a target ID, so OpenSnek should still do a one-shot active-target read after
  the hint.
- Whether `03 82 00 00` is stable across reconnect, delete/recreate, Synapse
  takeover, and mixed host states. Live macOS evidence supports it as the direct
  active target read.
- Whether Synapse's startup `08 05` / `08 07` / `08 06` live apply sequence is
  what disables firmware-visible profile-button cycling, or whether Synapse
  simply handles a host HID event before firmware changes the onboard slot.
  A focused "press profile button while Synapse is open" capture is still needed
  to distinguish those possibilities.
- Whether `03 06` clears target metadata/settings immediately or only removes
  the target from the onboard profile list; create captures suggest Synapse may
  later recycle and rewrite the same target.

## Rename

Status: device metadata exists, but rename-only updates looked host-only in
observed Synapse flows.

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

- Treat profile display-name edits as OpenSnek host-side metadata for now.
- Do not rewrite `03 04 <target> 00` just to rename an existing profile until
  isolated metadata update safety is validated.
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

## Profile-Scoped vs Device-Global Settings

Status: mixed. Several settings are clearly target/profile-scoped, but others
are live projection surfaces or device telemetry and should not be modeled as
stored-profile data.

| Surface | Current scope | Evidence | Implementation guidance |
|---|---|---|---|
| Target inventory | Device profile list | `03 80 00 00` returns target bytes such as `01 02 03` | Use to discover cycleable/known targets; not a user setting. |
| Active target | Device runtime pointer | `03 82 00 00` live-read `01`, `02`, and `03` as the firmware-selected target changed | Use after passive profile-button hints; not stored inside a profile. |
| UUID/name/owner metadata | Stored target/profile | `03 84 <target> 00` read back the GUID/name written by `03 04 <target> 00` for targets `2` and `3` | Device-backed for created targets, but standalone rename remains unvalidated. |
| DPI scalar/stage/token | Stored target plus hardware-active mirror | `0B 81/82/83 <target> 00` read stored targets; `0B 81/82/83 00 00` read the hardware-active surface | Read stored targets for hydration/fingerprint fallback. Use target `0` for firmware-active state after profile cycling; target `1` is projection. |
| Button bindings | Stored target plus hardware-active mirror plus live projection | `08 84/08 04 <target> <slot>` works for stored targets; `08 84 00 <slot>` mirrors the active firmware target after cycling | Store per profile in OpenSnek; after profile-cycle, hydrate active state from target `0`. |
| Lighting brightness | Stored target plus hardware-active mirror plus live projection | Stored create/rewrite and stored-only update writes use `10 05 <target> 00`; stored readback uses `10 85 <target> <led>`; hardware-active readback uses `10 85 00 <led>` | Stored brightness is mapped for the V3 Pro target model. Use target `0` to hydrate active hardware state after firmware cycling. |
| Lighting static color | Stored target plus hardware-active mirror plus live projection | Stored static write/read uses `10 03/10 83 <target> <led>`; hardware-active static readback uses `10 83 00 <led>` | Static stored color is mapped per target/LED. Use target `0` to hydrate active hardware state after firmware cycling. |
| Lighting effects / advanced state | Profile scope likely, schema incomplete | Unedited stored zones can return effect-shaped payloads such as `03 01 28 01 00 ff 00 00 ff 00` | Keep advanced/effect persistence as an open gap. |
| Lighting zone catalog | Device-global capability | `10 80 00 01` returns LED IDs for the device | Capability metadata, not profile data. |
| Sleep timeout / power management | Device-global or global register alias | Shipped key is `05 84/05 04 00 00`; live sweep of adjacent target-like reads returned the same timeout or unsupported status, not distinct profile values | Keep as device-level setting. Do not include in onboard profile snapshots unless future captures prove profile scope. |
| Battery raw/status | Device telemetry | `05 81/05 80 00 01`; target-like probes returned the same telemetry or unsupported status | Never store in profiles. |
| Poll rate | Not mapped on BLE in product Swift | No source-of-truth BLE vendor key in Swift | Keep unsupported/global until a validated BLE path exists. |

Unknown profile surfaces still include macros, advanced action families,
advanced lighting/effect data, and any hidden Synapse-only per-profile fields.

## Bulk Profile Read / Write

Status: no atomic whole-profile bulk API is mapped or used by OpenSnek today.

What we have is a set of profile-scoped surfaces:

| Surface | Read | Write | Notes |
|---|---|---|---|
| Target inventory | `03 80 00 00` | not mapped | Returns cycleable/known target bytes such as `01 02 03`. |
| Active target | `03 82 00 00` | not mapped | Preferred current-profile read after a profile-button HID hint. |
| Hardware-active state | `0B 81/82/83 00 00`, `08 84 00 <slot>`, `10 85 00 <led>`, `10 83 00 <led>` | not mapped as a direct target | Mirrors the active firmware-selected target after profile cycling. |
| Metadata UUID/name/owner | `03 84 <target> 00` + `<offset><length>` request payload | `03 04 <target> 00` chunk payloads | Device-backed for live-created targets `2` and `3`; standalone rename not validated. |
| Stored DPI scalar/stages/token | `0B 81/82/83 <target> 00` | `0B 01 <target> 00`, `0B 04 <target> 00` | Stored-target writes validated as part of create/rewrite flows. |
| Live/projection DPI | `0B 84 01 00` | `0B 04 01 00` | This is the current shipping Bluetooth live-layer DPI refresh/write path. |
| Button binding | `08 84 <target> <slot>` | `08 04 <target> <slot>` | Per-slot, not whole-profile. Current product Swift writes target `1`; probe can target stored slots. |
| Stored brightness | `10 85 <target> <led>` | `10 05 <target> 00` | Stored write/read validated on inactive target `3`. |
| Stored static color | `10 83 <target> <led>` | `10 03 <target> <led>` | Stored static-zone write/read validated on target `3`, LED `0x01`; effect-shaped payloads remain unmapped. |
| Live lighting brightness/color | `10 85 01 <led>`, `10 83 00 <led>` | `10 05 01 <led>`, `10 03 00 <led>` | Current shipping Bluetooth live-layer lighting refresh/write path on the V3 Pro. |
| Power/battery telemetry | `05 84`, `05 81`, `05 80` global keys | `05 04 00 00` for sleep timeout | Device-level surfaces; not profile bulk data. |

So, yes, OpenSnek can assemble a best-effort profile snapshot for the mapped
surfaces by bulk-reading a target, but that is an OpenSnek orchestration over
many vendor exchanges, not a single device "bulk profile read" command. It is
not yet a complete "everything Synapse can store" profile clone: unmapped button
action families, macros, advanced lighting/effect state, and any hidden
per-profile settings still need separate validation. Likewise, create/rewrite is
a multi-command transaction over metadata, DPI, stored lighting, and optional
button slot writes; no atomic "write this complete profile blob" command has
been identified.

Current OpenSnek app behavior:

- Shipping Bluetooth state refresh does not use profile inventory/metadata
  reads yet.
- `BridgeClient.readBluetoothState` reads the historical live/projection state
  through per-feature calls: live DPI via `0B 84 01 00`, battery/power scalars,
  and existing lighting keys. On V3 Pro firmware-cycled profiles, target `0`
  is the better active-hardware state source for DPI, buttons, and lighting.
- Bluetooth applies are also per-feature: live DPI through `0B 04 01 00`,
  live lighting through `10 05 01 <led>` / `10 03 00 <led>`, and button binding
  through target `1` `08 04 01 <slot>`.
- The new profile CRUD surfaces are currently probe/documentation-backed. A
  future app implementation should use `03 82` for reactive active-profile UI,
  `03 80`/`03 84` for inventory/identity hydration, target `0` reads to hydrate
  active firmware-selected state, and stored target reads only when it needs to
  hydrate a full stored profile snapshot.

## OpenSnek Implementation Shape

Proposed types:

```text
BLEProfileSurface
  target: UInt8              // 1 = Synapse live projection, 2..5 = stored target
  storedSlot: UInt8?         // OpenSnek slot 1..4 for targets 2..5
  hostGUID: UUID?            // OpenSnek/Synapse host identity when known
  name: String?              // host-side display name when known
  snapshot: DeviceSnapshot   // DPI, lighting, buttons, etc.

BLEHardwareActiveTarget
  activeTargetKey: 03 82 00 00
  target: UInt8              // current active target, e.g. 1, 2, 3

BLEHardwareActiveFingerprint
  activeStagesKey: 0B 82 00 00
  activeScalarKey: 0B 81 00 00
  activeStageTokenKey: 0B 83 00 00
  matchedStoredSlot: UInt8?  // set only when fingerprint is unique
```

Proposed behavior:

- `readProfiles()` should read `03 80 00 00` for targets and `03 84 <target>
  00` for device-backed UUID/name metadata where available. Product UI should
  still reconcile against OpenSnek-owned host metadata until reconnect, target
  churn, and rename semantics are validated.
- `activateProfile(id)` applies the stored snapshot to target `1`.
- `updateProfile(id, changes)` updates OpenSnek storage and, if active, applies
  changed settings to target `1`.
- Inactive profile edits in OpenSnek should update the host-side profile
  snapshot without trying to mirror Synapse's UI; Synapse makes profiles live
  when they are selected for editing.
- `deleteProfile(id)` / saved-slot `None` writes `03 06 <target> 00` and removes
  that target from OpenSnek's cycleable stored-profile list.
- Stored-target writes stay behind a hardware-gated experimental path until
  create/update/delete captures prove safety.
- `handleProfileButtonHint()` should debounce the passive HID reports, read
  `03 82 00 00`, and map the returned target to the inventory/profile table.
  Use `0B 82 00 00` matching only as fallback/validation; if fallback matching is
  not unique, mark the UI profile identity ambiguous instead of guessing.

Probe validation commands now cover the capture-backed subset:

```bash
swift run --package-path OpenSnek OpenSnekProbe bt-profile-read --stored-slots 1,2,3,4 --button-slots 5,106 --name "BSK V3 PRO"
swift run --package-path OpenSnek OpenSnekProbe bt-profile-create --stored-slot 1 --profile-name OPENSNEK_MAC_SLOT_1 --yes --name "BSK V3 PRO"
swift run --package-path OpenSnek OpenSnekProbe bt-profile-button-read --stored-slot 1 --button-slot 5 --name "BSK V3 PRO"
swift run --package-path OpenSnek OpenSnekProbe bt-profile-button-set --stored-slot 1 --button-slot 5 --kind keyboard_simple --hid-key 0x09 --yes --name "BSK V3 PRO"
swift run --package-path OpenSnek OpenSnekProbe bt-profile-hid-watch --name "BSK V3 PRO" --duration 20
```

The write command targets stored slots through `08 04 <target> <slot>` and only
projects to live target `1` when `--project-live` is passed. Keep metadata CRUD
and `03 06` delete/unassign outside product flows until live hardware validation
confirms the remaining edge cases.

## Remaining Gaps Before Shipping

1. Offline inactive edits remain unproven. Existing Synapse UI flows make the
   edited profile live before writing, so OpenSnek should keep inactive edits
   host-side for now.
2. Create allocation remains under-specified. We have one strong target-`2`
   create/rewrite capture and one live target-`2` replay, but not enough to know
   free-slot choice rules.
3. Stored DPI persistence remains under-specified. Active DPI edits were live
   target `1` writes; stored-target DPI table writes only appeared during
   create/rewrite flows.
4. Delete/unassign removes a target from the cycleable inventory but does not
   erase the target bank immediately. Product code must treat `03 80` as the
   cycleable source of truth and ignore stale readable deleted targets unless
   explicitly inspecting raw banks.
5. Stored lighting remains partial. Brightness and static color now have
   target-scoped read/write paths and firmware-cycle application validation, but
   advanced/effect semantics are not mapped.
6. `03 82 00 00` still needs reconnect/recreate validation before
   shipping by default. DPI fingerprinting remains the fallback path and is only
   usable when inventory-listed DPI tables are unique.
