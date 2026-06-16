# Basilisk V3 Pro USB Profile CRUD Draft

This is the implementation-facing working spec for Basilisk V3-family USB
onboard profile support. It intentionally avoids Synapse USB traffic captures.
The current evidence comes from existing OpenSnek USB protocol support, earlier
hardware validation notes, and direct OpenSnek USB feature-report reads from an
attached Basilisk V3 Pro (`1532:00AB`) on 2026-06-16.

Use this as the USB companion to `BLE_PROFILE_CRUD_SPEC.md` until both
transports are ready to productionize behind one profile API.

## Current Answer

The USB protocol is stronger than expected for stored profile data. It does not
reuse the BLE profile-management key family directly, but it does expose
profile-addressed setting banks through existing USB commands.

Strong enough to build against experimentally:

- DPI scalar reads use `04:85` with a storage/profile byte. Storage IDs `0..5`
  all read successfully on the attached Basilisk V3 Pro.
- DPI stage-table reads use `04:86` with the same storage/profile byte. Storage
  IDs `0..5` all read successfully when queried serially.
- USB storage/profile IDs `2` and `3` match the profiles previously created
  over Bluetooth, including target `3`'s recreated DPI table
  `760,960,1160,1360,1560`.
- Lighting brightness reads use `0F:84` with the same storage/profile byte and
  per-zone LED ID. Storage/profile `3` returned brightness `0x60`, matching the
  Bluetooth-created target `3`.
- Button bindings use `02:8C` / `02:0C` with a profile byte. Profiles `0..5`
  are readable on the attached V3 Pro, and existing OpenSnek USB button writes
  already use this command family for validated button-profile workflows.
- Physical USB profile-cycle presses are detectable through passive HID input
  reports on the keyboard-style interface: `04 00 ...` followed about 200 ms
  later by `05 39 ...`.
- Direct active profile ID reads use `05:84`, size `00`. The value tracked
  profile-button changes between profile `1` and stored profile `3`.
- Software active profile selection uses `05:04 <profile>`. It ACKed for
  assigned profiles `1` and `3`, updated `05:84`, and projected
  storage/profile `0`; it rejected readable but unassigned profiles `2`, `4`,
  and `5` with status `0x03`.
- Assigned profile inventory uses `05:81`, size `00`. After cleanup it returned
  `05 01 03`: max storage/profile ID `5`, assigned profiles `1` and `3`.
  During a guarded create probe it changed to `05 01 03 04 05`, while
  `05:80` changed from count `2` to count `4`.
- After a USB physical profile-cycle press, storage/profile `0` mirrors the
  newly active firmware-selected onboard profile for at least DPI and
  brightness.
- Profile UUID/name metadata is readable over USB through `05:88` chunk reads.
  Slots `2..5` returned UUID/name metadata; slots `2` and `3` returned the
  same metadata previously written and read over Bluetooth.
- Profile UUID/name metadata writes use `05:08` chunks over the same 250-byte
  metadata object. For already assigned/listed profiles, `05:08` can rename or
  repair metadata without `05:02`. For unassigned banks, `05:08` returns
  status `0x03` until a `05:02 <profile>` assign/prepare prelude is sent.
- Delete/unassign uses `05:03 <profile>`. Live validation on profile `2`
  removed that stored bank from the hardware cycle ring, while the bank's
  readable settings and metadata remained intact.

Not strong enough to ship as full USB profile CRUD yet:

- `00:87` returns a profile summary payload, but it is not trustworthy as the
  hardware-active profile ID on the V3 Pro. It stayed `02 32 03` while
  physical profile-cycle presses moved effective storage `0`, while `05:84`
  tracked the direct active profile ID, and while banks `4` and `5` remained
  directly
  readable through profile-addressed commands and metadata chunks.
- Stored-profile writes for DPI scalar, DPI stages, and stored lighting
  brightness are changed-value write/readback validated on storage/profile `5`,
  with automatic restore. The same temporary values persisted across a USB
  reconnect and were restored afterward. Production code still needs
  cross-transport readback and power-cycle validation before enabling
  user-driven stored-bank writes.
- `05:02 <profile>` plus four full `05:08` chunks can assign/create an unlisted
  bank, but the assign path initialized or disturbed profile content in the
  live probe: profile `4`'s DPI scalar/stage active token and brightness changed
  and had to be restored through the mapped `04:05`, `04:06`, and `0F:04`
  stored-profile writers. Production create must write desired content after
  metadata assignment and verify every mapped surface.
- No atomic whole-profile settings blob is known. USB profile hydration remains
  a multi-surface operation over metadata, DPI, buttons, brightness, and any
  future static/effect/macro surfaces.

External evidence:

- OpenRazer's [Unknown commands](https://github.com/openrazer/openrazer/wiki/Unknown-commands)
  page notes onboard memory slot IDs `0x02..0x05`, with `0x00` as no-store and
  `0x01` as the default profile.
- The same page lists `05:02` as a probable current onboard profile command,
  `05:08` as a probable onboard profile bulk write command, `05:03` as a clear
  slot candidate, and `0F:02` effect writes using profile ID as the first byte.
- Live OpenSnek USB probing on the V3 Pro confirms the slot-ID model and finds
  the high-bit `05:88` metadata read counterpart. Follow-up live probing
  validates `05:03` as delete/unassign from the hardware cycle ring and `05:04`
  as the software active-profile selector. A later bulk probe maps `05:81` as
  assigned-profile inventory and `05:08` as the low-bit metadata-object write.

## Bluetooth Create/Name Mapping

Bluetooth has a guarded create/rewrite path for explicit stored targets and a
validated assigned-target metadata rename path. `OpenSnekProbe bt-profile-create`
clears a chosen target, runs the observed prepare/apply control steps, writes
`03:04` metadata chunks with UUID/name/owner fields, then writes stored DPI and
brightness. Targets `2`, `3`, and temporary target `5` were created/recreated
successfully, appeared in `03:80`, read back through `03:84`, and selected
through `03:02` when assigned. Direct `03:04` metadata writes reject with status
`0x03` on unassigned targets, but the same full metadata object works as a
rename/update once the target is assigned. Rename-only Synapse captures did not
emit `03:04`, so host display-name edits can still remain host-owned unless the
user explicitly asks to rename onboard metadata.

USB now maps the create/name pieces, with a stronger caveat around assignment
side effects than Bluetooth:

| Bluetooth behavior | USB counterpart | Status |
|---|---|---|
| Active target read `03:82` | `05:84` | Validated. |
| Active target select `03:02` | `05:04 <profile>` | Validated for assigned profiles. |
| Inventory `03:80` | `05:81`, with count hint `05:80` | Validated experimentally. `05:81` returns max profile ID followed by assigned profile IDs. |
| Delete/unassign `03:06 <target>` | `05:03 <profile>` | Validated as cycle-ring unassign, not erase. |
| Metadata read `03:84 <target>` | `05:88 <profile,offset,total>` | Validated for UUID/name/owner chunks. |
| Metadata write `03:04 <target>` | `05:08 <profile,offset,total,data>` | Validated over a 250-byte metadata object. Works without the create prelude for already assigned profiles; unassigned targets/banks reject until the create/assign prelude runs. |
| Prepare/apply/create controls `08:05`, `08:07`, `03:05`, `01:8C` | `05:02 <profile>` before `05:08` | Validated as USB assign/create prelude for an unlisted bank. It can initialize/disturb DPI and brightness, so create must be followed by content writes/readback. |
| Stored DPI/buttons/brightness writes | `04:05`, `04:06`, `02:0C`, `0F:04` | Profile-addressed content writes are validated on known banks. |

Practical result: USB and Bluetooth now match for core mapped CRUD semantics:
list, activate, unassign, rename/repair metadata on assigned profiles, and
create/assign a named bank through a transport-specific prelude plus full
metadata writes. The USB assign path is known not to be content-preserving, and
Bluetooth create is still a multi-surface transaction, so production create
should immediately write the desired DPI, button, and lighting profile content
and verify readback on either transport.

## Storage / Target Model

USB profile-addressed setting commands use a one-byte storage/profile field.
On the attached Basilisk V3 Pro, those IDs line up numerically with BLE profile
targets for stored banks:

| USB storage/profile | Working interpretation | Notes |
|---:|---|---|
| `0` | direct/effective live layer | Reads current effective USB state. |
| `1` | base persistent/live store | Usually mirrors `0` in the current state. |
| `2` | stored profile bank / BLE target `2` | Matches the Bluetooth-created stored slot 1 data. |
| `3` | stored profile bank / BLE target `3` | Matches the Bluetooth-created/recreated stored slot 2 data. |
| `4` | stored profile bank / BLE target `4` | Readable metadata name `OS_P4_RENAMED`; `05:02` + full `05:08` temporarily assigned it, then `05:03` removed it from inventory. |
| `5` | stored profile bank / BLE target `5` | Metadata was repaired to `OS_P5_BULK_MAP` with full `05:08` chunks, then `05:03` removed it from inventory. |

Do not treat readable banks as assigned onboard profiles. On the same device,
`05:81` distinguished assigned profiles from readable stale banks, and `05:03`
removed profiles from that inventory while leaving metadata/settings readable.

## Physical Profile Button Detection

Status: validated for USB HID hinting and effective-state refresh.

Two live macOS probe passes used `OpenSnekProbe usb-input-listen` while the
mouse was connected as USB `1532:00AB`. Each physical profile-cycle button
press emitted the same report pair on the HID interface with usage page `0x01`,
usage `0x06`, `input=16`, `feature=1`:

| Press | First report | Follow-up report | Gap |
|---:|---|---|---:|
| `1` | `04 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00` | `05 39 00 00 00 00 00 00 00 00 00 00 00 00 00 00` | `0.197s` |
| `2` | `04 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00` | `05 39 00 00 00 00 00 00 00 00 00 00 00 00 00 00` | `0.197s` |

Other HID interfaces emitted zero-filled noise around the same action:

```text
usage 0x01:0x02 input=8  -> 00 00 00 00 00 00 00 00
usage 0x01:0x06 input=8  -> 00 00 00 00 00 00 00 00
```

Implementation guidance:

- Use the `0x01:0x06`, `input=16`, `feature=1` interface as the primary USB
  profile-cycle hint source on the V3 Pro.
- Debounce on the `05 39 ...` report. The preceding `04 00 ...` report is a
  useful companion signal but does not carry an active profile ID.
- After the hint, issue a small readback of effective storage/profile `0`
  instead of fingerprinting the whole device.
- If a user-facing active slot label is needed, match storage/profile `0`
  against known stored banks. Use multiple surfaces where possible because
  duplicate DPI tables can make DPI-only matching ambiguous.
- The read-only probe helper `OpenSnekProbe usb-profile-read` performs that
  diagnostic sweep across metadata, DPI, brightness, and selected button slots.
  Production UI refresh should still prefer a minimal effective profile `0`
  read after the passive HID hint, and only compare against stored banks when a
  slot label is needed.

### Effective State After Profile Button Presses

Before the USB profile-button passes, the device reported:

```text
00:87 -> 02 32 03
04:85 storage 0 -> 1200x1200
04:86 storage 0 -> 600,900,1000,1200,1400
```

After the first physical profile-cycle press:

```text
00:87 -> 02 32 03
04:85 storage 0 -> 1600x1600
04:86 storage 0 -> 400,800,1600,3200,6400, active token 03
0F:84 storage 0 led 01 -> 54
02:8C profile 0 slot 05 -> default Button5
```

That matches stored bank `2`.

After the second physical profile-cycle press:

```text
00:87 -> 02 32 03
04:85 storage 0 -> 1360x1360
04:86 storage 0 -> 760,960,1160,1360,1560, active token 04
0F:84 storage 0 led 01 -> 60
0F:84 storage 0 led 04 -> 60
02:8C profile 0 slot 05 -> default Button5
```

That matches stored bank `3`, including the brightness value written during the
Bluetooth recreate validation.

Conclusion: USB can reliably detect a physical profile-cycle button press and
reactively identify the selected onboard profile. `05:84`, size `00`, returns
the active profile ID, while storage/profile `0` mirrors that active profile's
effective settings for hydration.

### Direct Active Profile ID

Status: validated on the attached V3 Pro.

```text
Get:      class 05, cmd 84, size 00
Response: args[0] = active profile ID
```

The observed response can report `data_size = 00` while still carrying the
active profile byte in `args[0]`. Clients should validate the success status and
class/cmd echo, then read `args[0]`; do not require the response size byte to be
non-zero.

Live validation after profile `2` had been deleted/unassigned from the cycle
ring:

| Action | `05:84` | Effective storage/profile `0` |
|---|---:|---|
| Before press | `03` | matched stored profile `3` |
| Press profile-cycle button | `01` | matched base/profile `1` |
| Press profile-cycle button again | `03` | matched stored profile `3` |

`00:87` stayed `02 32 03` throughout those transitions.

### Assigned Profile Inventory

Status: validated experimentally on the attached V3 Pro.

```text
Count:    class 05, cmd 80, size 00
Response: args[0] = assigned profile count

List:     class 05, cmd 81, size 00
Response: args[0] = max profile ID, args[1...] = assigned profile IDs
```

Live validation:

| State | `05:80` | `05:81` | Selector behavior |
|---|---:|---|---|
| After cleanup | `02` | `05 01 03` | `05:04 01` and `05:04 03` ACK; `04`/`05` reject |
| After `05:02 04` + full `05:08` | `04` | `05 01 03 04 05` | `05:04 04` ACKed |
| After `05:03 04` and `05:03 05` | `02` | `05 01 03` | `05:04 04` and `05:04 05` reject |

Earlier, `05:81` returned `05 01 03 05` while `05:04 05` rejected. The follow-up
bulk probe showed why: profile `5` was assigned/listed, but its metadata had
been damaged to `ff...`; after a full `05:08` metadata repair, `05:04 05`
ACKed. Treat `05:81` as assignment inventory, but still require selector/readback
validation when recovering from damaged metadata or unknown third-party state.

Other nearby profile-management reads:

- `05:80`, size `00`, returns the assigned-profile count. With one- or two-byte
  args it echoed the last request byte into `args[1]` in earlier probes, so use
  size `00`.
- `05:8A`, size `00`, returned `05`. With one- or two-byte args it kept
  returning `05` and echoed the last request byte into `args[1]`.

Current interpretation: `05:80` is the assigned-profile count, `05:81` is the
side-effect-free inventory equivalent to BLE `03:80`, and `05:8A` looks like a
max profile-bank ID hint. `00:87` remains stale summary telemetry and should not
drive profile UI.

### Software Active Profile Selector

Status: validated on the attached V3 Pro, with side effects.

```text
Set:      class 05, cmd 04, size 01
Args:     [0] = active profile ID
Response: success echoes class 05, cmd 04, and the requested profile ID
```

Live validation:

| Command | Result |
|---|---|
| `05:04 01` | ACKed, `05:84` stayed/changed to `01`, effective storage/profile `0` matched base/profile `1` |
| `05:04 03` | ACKed, `05:84` changed to `03`, effective storage/profile `0` matched stored profile `3` |
| `05:04 02` | status `0x03`, active profile stayed `1` |
| `05:04 04` | status `0x03` before assignment; ACKed after `05:02 04` + full `05:08`; status `0x03` again after `05:03 04` |
| `05:04 05` | status `0x03` while metadata was invalid; ACKed after metadata repair; status `0x03` again after `05:03 05` |

This can be used as a software selector for assigned profiles. It also gives a
side-effecting way to infer cycleability by trying candidate profile IDs and
restoring the original active ID afterward. Prefer `05:84` for passive UI
refresh and avoid using `05:04` as normal inventory discovery.

## USB Metadata Object Bulk Read / Write

Status: mapped experimentally for UUID/name/owner metadata.

The OpenRazer unknown-command notes describe onboard profile chunks written
through `05:08` with headers like:

```text
<slot> <offset_hi> <offset_lo> 00 fa <chunk-data...>
```

The high-bit counterpart `05:88` works as a USB metadata chunk read on the
attached V3 Pro when the request size is `0x50`:

```text
class 05, cmd 88, size 50
args: <slot> <offset_hi> <offset_lo> 00 fa
```

The response starts with the same 5-byte chunk header, followed by up to 75
bytes of metadata data. The metadata object is 250 bytes (`0x00fa`) long and
uses byte offsets. Because the USB HID report has 80 argument bytes before the
checksum, the useful chunk shape is always a `0x50` payload: 5 header bytes plus
75 data bytes. The complete object is covered by offsets:

```text
0x0000, 0x004b, 0x0096, 0x00e1
```

Short write-side tail chunks can fail to respond; use full `0x50` writes and
pad bytes past `0x00fa` with zeroes.

Validated reads:

| Slot | Request | Result |
|---:|---|---|
| `2` | `05:88`, args `02 00 00 00 fa` | GUID `3a35ec93-bee1-4b29-9d3d-0d2b88f9edef`, name `OPENSNEK_MAC_SLOT_1` |
| `3` | `05:88`, args `03 00 00 00 fa` | GUID `c7aae39e-43b0-41ae-bf46-b4ae556a4a02`, name `OPENSNEK_RECREATE_SLOT_2` |
| `3` | `05:88`, args `03 00 40 00 fa` | zero padding followed by owner hash beginning `31933b5452df5708882d4fb...` |
| `3` | `05:88`, args `03 00 80 00 fa` | owner hash continuation ending `...d0241a76`, then zero padding |
| `3` | `05:88`, args `03 00 c0 00 fa` | zero padding |
| `4` | `05:88`, args `04 00 00 00 fa` | GUID `27530668-c3e2-4e0a-a06e-a4854383c4e9`, name `OS_P4_RENAMED` |
| `5` | `05:88`, args `05 00 00 00 fa` | Before the unsafe write probe: GUID `18f2a4cc-ecb8-4765-b532-9df401a686d6`, name `OS_P5`; after the unsafe write probe: GUID `ffffffff-ffff-ffff-ffff-ffffffffffff`, name `nil`; after full-object repair: GUID `18f2a4cc-ecb8-4765-b532-9df401a686d6`, name `OS_P5_BULK_MAP` |

The slot-`3` offset-`0` raw data begins:

```text
9e e3 aa c7 b0 43 ae 41 bf 46 b4 ae 55 6a 4a 02
4f 50 45 4e 53 4e 45 4b 5f 52 45 43 52 45 41 54 45 ...
```

The first 16 bytes decode as the Windows/GUID little-endian representation of
`c7aae39e-43b0-41ae-bf46-b4ae556a4a02`, followed by the ASCII profile name
`OPENSNEK_RECREATE_SLOT_2`.

Negative/limited probes:

| Command | Result |
|---|---|
| `05:82`, size `00` | status `0x03` |
| `05:82`, size `01`, args `02` | status `0x03` |
| `05:82`, size `01`, args `01` / `03` | status `0x03` |
| `05:83`, size `01`, args `03` | status `0x03` |
| `05:88`, size `05` | success, but returns only the 5-byte chunk header |
| `05:8A`, size `01`, args `01` / `03` | success, returned `05` and ignored the requested profile byte in this pass |
| `06:8E`, size `0E`, args all zero / leading `01` / leading `03` | success, stable payload `00 64 00 04 c0 00 00 04 a8 00 00 00 15`; not profile-dependent |

Write-side validation:

| Probe | Result |
|---|---|
| `05:08 05 <offset> 00 fa <data>` at offsets `0000`, `004b`, `0096`, then short tail `00e1` | First three full chunks ACKed and repaired profile `5` UUID/name; short tail had no response. |
| `05:08 05 00e1 00 fa` with full `0x50` padded payload | ACKed; profile `5` metadata remained repaired. |
| `05:04 05` after profile `5` metadata repair | ACKed and selected profile `5`; active profile was restored to `1`. |
| Direct `05:08 04 ...` before assignment | status `0x03`; profile `4` metadata/settings unchanged. |
| `05:02 04`, then four full `05:08 04 ...` chunks | ACKed, changed `05:81` from `05 01 03 05` to `05 01 03 04 05`, and `05:04 04` selected profile `4`. |
| `05:03 04` and `05:03 05` cleanup | Removed `4` and `5` from `05:81`; selectors rejected both again. |

The `05:02` assignment path disturbed profile `4` content during the create
probe. DPI scalar changed from `800x800` to `1600x1600`, stage active token
changed from `0x02` to `0x03`, and brightness changed from `0x54` to `0x55`.
OpenSnek restored profile `4` with the validated profile-addressed content
writes. Treat `05:02` + `05:08` as "create/assign metadata, then rewrite
content", not as a content-preserving operation.

Implementation guidance:

- Use `05:88` as the USB metadata-object read path.
- Use `05:08` only with a complete 250-byte object split into four full `0x50`
  reports at offsets `0x0000`, `0x004b`, `0x0096`, and `0x00e1`.
- For rename/repair of an already assigned profile, skip `05:02` and write the
  full metadata object. Confirm with `05:88`, then confirm selector state with
  `05:04`/`05:84` only if needed.
- For create/assign of an unassigned readable bank, send `05:02 <profile>` and
  then the four full `05:08` chunks. Immediately write the intended DPI,
  button, and lighting content with profile-addressed commands and read it back.
- Do not use `06:8E` as part of the mapped create flow. The read-only probe
  returned stable profile-independent data and was not needed for the successful
  assignment probe.

## Live USB Read Snapshot

Attached device:

```text
OpenSnekProbe usb-info -> 1532:00ab:00130000:usb pid=0x00ab
```

Profile summary:

```text
00:87 -> args 02 32 03
```

Working interpretation is `active-ish=2`, `unknown=0x32`, `count=3`. The middle
byte is not reserved-zero on this device. Because storage `0` / `1` did not
match storage `2` in the same pass, do not use this as authoritative current
profile state yet.

DPI scalar reads (`04:85`, size `07`, args `<storage>`):

| Storage | Scalar |
|---:|---|
| `0` | `1200x1200` |
| `1` | `1200x1200` |
| `2` | `1600x1600` |
| `3` | `1360x1360` |
| `4` | `800x800` |
| `5` | `800x800` |

DPI stage reads (`04:86`, size `26`, args `<storage>`):

| Storage | Active token | Stages |
|---:|---:|---|
| `0` | `04` | `600,900,1000,1200,1400` |
| `1` | `04` | `600,900,1000,1200,1400` |
| `2` | `03` | `400,800,1600,3200,6400` |
| `3` | `04` | `760,960,1160,1360,1560` |
| `4` | `02` | `400,800,1600,3200,6400` |
| `5` | `02` | `400,800,1600,3200,6400` |

Lighting brightness reads (`0F:84`, size `03`, args
`<storage>,<led>,00`) on LED IDs `0x01`, `0x04`, and `0x0A`:

| Storage | Brightness |
|---:|---:|
| `0` | `0x54` |
| `1` | `0x54` |
| `2` | `0x54` |
| `3` | `0x60` |
| `4` | `0x54` |
| `5` | `0x54` |

Button5 reads (`02:8C`, size `0A`, args
`<profile>,05,00,00,00,00,00,00,00,00`):

| Profile | Button5 block |
|---:|---|
| `0` | `01 01 05 00 00 00 00` |
| `1` | `01 01 05 00 00 00 00` |
| `2` | `01 01 05 00 00 00 00` |
| `3` | `01 01 05 00 00 00 00` |
| `4` | `01 01 05 00 00 00 00` |
| `5` | `02 02 00 09 00 00 00` |

The profile `5` keyboard block is from earlier OpenSnek USB button-profile
testing and confirms this bank is distinct from the default banks.

A later read-only sweep with:

```text
OpenSnekProbe usb-profile-read --profiles 2,3,4,5 --button-slots 5,106 --pid 0x00ab
```

confirmed the current effective storage/profile `0` matched stored profile `3`
after hardware cycling, across DPI scalar/stages, all three brightness zones,
Button5, and profile-button slot `0x6A`. The same sweep read `0x6A` as
`12 01 01 00 00 00 00` on profiles `0..5`.

## Wire Commands

### Profile Summary

```text
Get:      class 00, cmd 87, size 00
Response: args[0] = profile/state byte candidate
          args[1] = unknown; observed 00 on older passes, 32 on 2026-06-16
          args[2] = profile count candidate
```

Observed V3 Pro payloads include `01 00 03`, `02 00 03`, and now `02 32 03`.
This register is useful telemetry, not a proven active profile source.

### Active Profile ID

```text
Get:      class 05, cmd 84, size 00
Response: args[0] = active profile ID
```

This is the direct USB counterpart for active-profile identity. On the attached
V3 Pro it changed from `03` to `01` and back to `03` across physical
profile-cycle button presses, while effective storage/profile `0` matched the
reported active profile each time.

### Set Active Profile ID

```text
Set:      class 05, cmd 04, size 01
Args:     [0] = active profile ID
Response: success echoes class 05, cmd 04, and the requested profile ID
```

On the attached V3 Pro, `05:04 01` and `05:04 03` ACKed and changed the active
profile reported by `05:84`. Candidate profiles `2`, `4`, and `5` returned
status `0x03` in the current state, even though their banks remained readable.
This makes `05:04` the validated active selector and a side-effecting
assignability probe.

### DPI Scalar

```text
Get:      class 04, cmd 85, size 07
Set:      class 04, cmd 05, size 07
Args:     [0] = storage/profile
          [1..2] = DPI X, big-endian
          [3..4] = DPI Y, big-endian
          [5..6] = reserved/zero on writes
```

Read validation now covers storage/profile `0..5`.

### DPI Stages

```text
Get:      class 04, cmd 86, size 26
Set:      class 04, cmd 06, size 26
Args:     [0] = storage/profile
          [1] = active stage ID token
          [2] = count
          [3+n*7] = stage rows
```

Stage rows are:

```text
[stage_id][dpi_x_be16][dpi_y_be16][00][00]
```

Read validation now covers storage/profile `0..5`. Write support is already
validated for live/base storage in OpenSnek, and same-value stored-bank
write/readback plus changed-value write/readback are validated on
storage/profile `5`. The changed values persisted across a USB reconnect and
were restored afterward. Cross-transport readback and power-cycle persistence
must still be validated before production UI support.

When writing both DPI stages and the scalar surface, write the stage table
first and the scalar second. In the reconnect validation pass, writing the
stage table after the scalar caused the scalar readback to return to the
stage-token-selected `800x800` value until `04:05` was applied again.

### Button Binding

```text
Get:      class 02, cmd 8C, size 0A
Set:      class 02, cmd 0C, size 0A
Args:     [0] = profile
          [1] = button slot
          [2] = hypershift flag
          [3..9] = 7-byte USB function block
```

Profile IDs `0..5` read successfully on the attached V3 Pro. Existing OpenSnek
button-profile workflows already validate write/readback on this command
family for supported USB button slots.

### Lighting Brightness

```text
Get:      class 0F, cmd 84, size 03
Set:      class 0F, cmd 04, size 03
Args:     [0] = storage/profile
          [1] = LED ID
          [2] = brightness for set, zero placeholder for get
```

Read validation now covers storage/profile `0..5` and V3 Pro LED IDs `0x01`,
`0x04`, and `0x0A`. Same-value stored-bank write/readback validation covers
profile `5` and all three V3 Pro LED IDs.

### Lighting Effects

```text
Set:      class 0F, cmd 02, size varies
Args:     [0] = storage/profile
          [1] = LED ID
          [2] = effect ID
          [3...] = effect parameters
```

Because the existing USB effect write shape already starts with the same
storage/profile byte, effects are likely profile-scoped. This is not proven as
full profile CRUD yet because no reliable effect-state readback API is mapped.

### Delete / Unassign Stored Profile

```text
Set:      class 05, cmd 03, size 01
Args:     [0] = storage/profile
Response: echoes class 05, cmd 03, and the requested storage/profile byte
```

Validation on the attached V3 Pro:

- `05:03 05` ACKed and left profile `5`'s readable metadata/settings bank
  intact.
- `05:03 02` ACKed. A follow-up profile-read still showed profile `2`'s
  metadata, DPI, brightness, and buttons readable, but the next physical
  profile-cycle press skipped profile `2` and moved effective storage/profile
  `0` to stored profile `3`.
- `05:03 04` and `05:03 05` ACKed after temporary bulk-create probes. `05:81`
  changed from `05 01 03 04 05` to `05 01 03`, `05:80` changed to `02`, and
  `05:04 04` / `05:04 05` returned status `0x03` again. Both banks remained
  readable afterward.

Treat this as hardware cycle-ring unassign, not as storage erase. Production
code should expose a clear recovery story before surfacing it as user-facing
delete, because the bank remains readable and may be reusable/reassignable.

## BLE-Looking Commands Tried Over USB

These USB feature-report reads were attempted on the attached V3 Pro to check
whether BLE profile-management keys carry over directly:

| USB command | Result |
|---|---|
| `03:80`, size `00` | status `0x04` timeout |
| `03:82`, size `00` | status `0x05` not supported |
| `03:84`, size `06`, args `03 00 00 00 4c 00` | status `0x05` not supported |
| `01:8C`, size `02`, args `03 00` | status `0x05` not supported |

Conclusion: USB profile-addressed setting banks are real, but USB HID does not
expose the BLE inventory/active/metadata command family through the same
class/cmd IDs.

## CRUD Status

| Operation | USB status | Current implementation guidance |
|---|---|---|
| Inventory/list | Validated experimentally | `05:81` returns max profile ID followed by assigned profile IDs; `05:80` returns assigned count. `00:87` remains stale summary telemetry. |
| Active profile read | Validated | `05:84`, size `00`, reports the active profile ID. Effective storage/profile `0` mirrors that active onboard profile after profile-button changes. |
| Active profile select | Validated | `05:04 <profile>` selects assigned profiles, updates `05:84`, and projects effective storage/profile `0`; it rejects unassigned banks with status `0x03`. |
| Metadata read/write | Validated experimentally | USB `05:88` reads and `05:08` writes the 250-byte UUID/name/owner object. Use four full `0x50` chunks; skip `05:02` for assigned-profile rename/repair. |
| Read full stored profile | Partial | Multi-surface read: DPI scalar/stages, buttons per slot, brightness per LED. Static/effect readback still missing. |
| Create stored profile | Validated experimentally | `05:02 <profile>` followed by four full `05:08` metadata chunks assigns an unlisted readable bank and makes `05:04` accept it. It can initialize/disturb content, so production create must immediately write desired settings and read them back. |
| Update stored profile | Partial | Button writes are validated. DPI scalar/stages and brightness changed-value writes are validated on profile `5` with restore, and persisted across USB reconnect. Cross-transport readback and power-cycle persistence still need guarded validation. |
| Delete/unassign | Validated cycle unassign | `05:03 <profile>` removes a stored bank from the hardware cycle ring. Profile `2` was skipped by the physical profile-cycle button after the command, while its readable bank remained intact. |
| Activate/select | Validated | Firmware profile-button activation is detectable through passive HID hints plus `05:84`; software selection works through `05:04` for assigned profiles. |

## Safe Implementation Boundary

Safe USB parity should be split into two layers:

1. Device-backed active/profile-state features:
   - list assigned profiles with `05:81` and optional count hint `05:80`
   - read active profile with `05:84`
   - react to physical profile-cycle HID hints by reading `05:84` and the
     effective storage/profile `0`
   - select a known assigned profile with `05:04 <profile>` and confirm with
     `05:84`
   - unassign/delete from the cycle ring with `05:03 <profile>` only when the UI
     explicitly communicates that the readable bank is not erased

2. Stored profile content features:
   - read metadata with `05:88`
   - write metadata with full-object `05:08` chunks, skipping `05:02` unless
     assigning a new bank
   - read/update stored button bindings with `02:8C` / `02:0C`
   - read/update stored DPI scalar/stages with `04:85/05` and `04:86/06`
   - read/update stored brightness with `0F:84/04`

What should not be implemented as device-backed USB CRUD yet:

- Treat `05:02` create/assign as content preserving. It can initialize or
  disturb stored DPI/lighting content; write the desired profile content after
  assignment.
- Treat readable banks as inventory. Banks can remain readable after
  unassign/delete; use `05:81` for assigned profiles.
- Treat `05:03` as erase. It is cycle-ring unassign; metadata/settings may stay
  readable and should be considered stale/reusable storage until a safe erase is
  mapped.

Practical product behavior: OpenSnek can safely present USB active-profile
identity and profile-button reactivity for the V3 Pro, and can edit known stored
content surfaces. USB profile name/UUID metadata can be read and written
experimentally, but user-facing create should remain guarded until the content
rewrite/readback sequence is implemented end to end.

## Profile-Scoped vs Device-Global

| Setting | USB scope | Evidence |
|---|---|---|
| DPI scalar | Profile-scoped | `04:85` reads distinct values for storage `0..5`. |
| DPI stages | Profile-scoped | `04:86` reads distinct stage tables for storage `0..5`. |
| Button bindings | Profile-scoped | `02:8C` reads distinct profile banks; profile `5` Button5 differs. |
| Lighting brightness | Profile-scoped | `0F:84` storage `3` returns `0x60`, matching the BT-created target `3`, while other banks return `0x54`. |
| Lighting static/effects | Likely profile-scoped | `0F:02` effect writes carry a storage/profile byte, but readback is not mapped. |
| Serial, firmware | Device-global | Standard `00:82` / `00:81` telemetry. |
| Battery | Device-global | `07:80` has no profile field. |
| Sleep timeout / idle time | Device-global | `07:83` / `07:03` have no profile field. |
| Low battery threshold | Device-global | `07:81` / `07:01` have no profile field. |
| Poll rate | Device-global | `00:85` / `00:05` have no profile field. |
| Device mode | Device-global | `00:84` / `00:04` have no profile field. |
| Scroll mode / acceleration / smart reel | Device-global or single VARSTORE | `02:94/14`, `02:96/16`, `02:97/17` use `VARSTORE=01`, not profile IDs. |

## Open Questions

- Do stored-bank writes through `04:05`, `04:06`, and `0F:04` later show over
  Bluetooth and persist across a full power-cycle?
- Does `05:02` always initialize the same default DPI/brightness content, or was
  the profile-`4` disturbance dependent on the current device state?
- What is the USB read/write path for static/effect lighting state, macros, and
  any other Synapse-only per-profile fields?
- Does full create/rename/delete metadata behavior persist identically across a
  USB reconnect, power-cycle, and Bluetooth reconnect?
