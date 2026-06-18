# Basilisk V3 Pro Bluetooth Profile CRUD Spec

This spec defines the Basilisk V3 Pro Bluetooth onboard-profile API for the
mapped core profile surface. It intentionally excludes macros, advanced button
families, and advanced lighting effects.

Validated device: Basilisk V3 Pro Bluetooth PID `0x00AC`, device name
`BSK V3 PRO`.

## Target Model

| Target | Meaning | Client behavior |
|---:|---|---|
| `0` | Hardware-active mirror | Read only. Use after firmware profile cycling to hydrate active DPI, button, brightness, and static-color state. |
| `1` | Live/projection target | Existing live Bluetooth writes use this target. Synapse also projects selected profiles here. |
| `2` | Stored slot 1 | Inventory-listed when assigned. |
| `3` | Stored slot 2 | Inventory-listed when assigned. |
| `4` | Stored slot 3 | Readable even when unassigned; do not treat as assigned unless listed by `03 80`. |
| `5` | Stored slot 4 | Readable even when unassigned; do not treat as assigned unless listed by `03 80`. |

Readable target banks can remain readable after delete/unassign. The assigned
profile set is the `03 80 00 00` inventory result, not the set of banks that
respond to setting reads.

## Status Codes

| Status | Meaning in profile flows |
|---:|---|
| `0x02` | Success. |
| `0x03` | Rejected in current profile state, commonly unassigned/non-cycleable target. |
| `0x01` | Non-success/transient write failure. Stop the transaction and read back before retrying. |

Every profile write transaction must check the status for each command. A
non-`0x02` write can leave a target partially updated.

## Client API

### `listProfiles()`

Read assigned targets:

```text
Read key: 03 80 00 00
Response payload: assigned target bytes
Example: 01 03
```

Return only targets present in this payload. Target `1` is the base/live profile.
Targets `2..5` map to stored slots `1..4`.

### `readActiveProfile()`

Read the active firmware target:

```text
Read key: 03 82 00 00
Response payload: one target byte
```

Use this after physical profile-button hints and after explicit selector writes.
Do not fingerprint the whole profile to identify the active target unless this
read is unavailable or inconsistent.

### `activateProfile(target)`

Select an assigned target:

```text
Write key: 03 02 00 00
Payload:   <target>
```

Required confirmation:

1. Write returns status `0x02`.
2. `03 82 00 00` returns the requested target.
3. Optional hydration reads use target `0` for active hardware state.

If the write returns `0x03`, leave the current active target unchanged in client
state and refresh inventory.

### `watchProfileButton()`

The physical profile-cycle button emits passive Bluetooth HID hint reports when
the firmware actually changes onboard profiles:

```text
04 04 00 00 00 00 00 00 00
05 05 39 00 00 00 00 00 00
```

Use the second report (`05 05 39 ...`) as the debounced event. The reports do not
carry a target ID. The Bluetooth client must accept the second report only when
it follows the captured `04 04 ...` prelude, and should match the captured
zero-tail `05 05 39 00 00 00 00 00 00` frame rather than an arbitrary
three-byte prefix. On each accepted event, read `03 82 00 00`, then hydrate
target `0` if the UI needs active settings.

If only one target is assigned, the profile button can be a firmware no-op and
no hint may be emitted.

### `readProfile(target)`

Read the mapped profile snapshot by combining these surfaces:

| Surface | Read command | Notes |
|---|---|---|
| Metadata | `03 84 <target> 00` with `<offset_le16><length_le16>` payload | UUID/name/owner metadata. |
| DPI scalar | `0B 81 <target> 00` | 6-byte DPI pair. |
| DPI stages | `0B 82 <target> 00` | Five 6-byte DPI pairs. |
| DPI stage token | `0B 83 <target> 00` | One byte. |
| Button binding | `08 84 <target> <slot>` | Packed 16-byte readback. |
| Brightness | `10 85 <target> <led>` | Per-zone brightness read. |
| Static color/effect state | `10 83 <target> <led>` | Static color payloads are mapped; advanced effect payloads are excluded. |

Target `0` reads the active firmware-selected state. Target `1` reads the
live/projection bank. Targets `2..5` read stored banks whether or not they are
assigned.

### `createProfile(target, metadata, content)`

Create/assign uses an explicit target. The API must choose a target from `2..5`
that is not present in `03 80 00 00`, unless the caller is intentionally
replacing an assigned profile.

Validated transaction:

```text
1. Write 03 06 <target> 00, empty payload
2. Write 08 05 <target> 00, payload 00
3. Read  01 8C <target> 00, expect payload 01
4. Write 08 07 <target> 00, payload 00
5. Write 03 05 <target> 00, empty payload
6. Write metadata through 03 04 <target> 00 chunks
7. Write DPI scalar/stages and mapped lighting/button content
8. Write 08 05 <target> 00, payload 00 before stored brightness writes
9. Read back inventory, metadata, and every written content surface
```

The profile is valid only after readback succeeds:

- `03 80 00 00` contains `target`.
- `03 84 <target> 00` returns the requested UUID/name.
- DPI, button bindings, brightness, and static color match the requested content.

### `renameProfile(target, metadata)`

Rename is a metadata rewrite on an assigned target.

Required preconditions:

- `target` is present in `03 80 00 00`.
- The client has a complete metadata object, preserving UUID/owner fields unless
  the user intentionally changes them.

Transaction:

```text
1. Write all metadata chunks through 03 04 <target> 00
2. Read 03 84 <target> 00 and verify UUID/name/owner
```

Direct `03 04` writes to unassigned targets return status `0x03`; use
`createProfile` to assign a target.

### `updateProfile(target, changes)`

For stored targets, write only changed mapped surfaces, then read back each
surface:

| Surface | Write command | Payload |
|---|---|---|
| DPI scalar | `0B 01 <target> 00` | 6-byte DPI pair. |
| DPI stages | `0B 04 <target> 00` | 38-byte table. |
| Button binding | `08 04 <target> <slot>` | 10-byte button payload. |
| Brightness | `10 05 <target> 00` | One brightness byte. |
| Static color | `10 03 <target> <led>` | 10-byte static-zone payload. |

For the currently active firmware profile, stored-target writes update the stored
bank, but target `0` is the active read surface. Existing live-layer UI writes
still use target `1`; product code must choose whether an edit is a live preview,
a stored profile edit, or both.

### `deleteProfile(target)`

Delete means unassign from the firmware cycle ring:

```text
Write key: 03 06 <target> 00
Payload:   empty
```

Required confirmation:

- Write returns status `0x02`.
- `03 80 00 00` no longer contains `target`.
- `03 02 00 00` rejects `target` with status `0x03` if probed.

Do not treat delete as secure erase. Metadata/settings can remain readable after
unassign and can be reused by a later create flow.

## Metadata Object

The Bluetooth metadata object is 250 bytes (`0x00fa`) and is transferred through
`03 04` write chunks and `03 84` reads.

### Write Chunks

```text
Write key: 03 04 <target> 00
Payload:   fa 00 <offset_le16> <data bytes>
Offsets:   0000, 004c, 0098, 00e4
```

The first three writes carry 76 data bytes each. The final write carries the
remaining metadata bytes. Pad unused bytes with zeroes.

### Read Chunks

```text
Read key:        03 84 <target> 00
Request payload: <offset_le16><length_le16>
Response:        <offset_le16><data bytes>
```

### Fields

| Offset | Size | Encoding |
|---:|---:|---|
| `0x0000` | 16 | UUID in Windows/GUID little-endian byte order. |
| `0x0010` | Up to 100 | UTF-8/ASCII profile name, zero-padded. |
| `0x0074` | 64 | Lowercase ASCII hex owner hash. |

Names longer than the available field must be rejected or truncated by the
client before writing. The owner field must be a full 64-character hex string;
short owner markers such as `OpenSnek` can leave profiles usable on the mouse
but broken in Synapse's profile UI. When writing metadata, preserve an existing
64-character owner hash from the target profile or another assigned onboard
profile on the same mouse; otherwise use OpenSnek's built-in 64-character
fallback owner hash. The current probe uses ASCII names.

## Button Binding Encoding

Button writes use a 10-byte payload:

```text
key:     08 04 <target> <slot>
payload: <target> <slot> <layer> <action> <p0_le16> <p1_le16> <p2_le16>
```

Examples:

| Binding | Key | Payload |
|---|---|---|
| Stored target `2`, Button5, keyboard HID `0x09` | `08 04 02 05` | `02 05 00 02 02 00 09 00 00 00` |
| Stored target `3`, Button5, mouse Button5 | `08 04 03 05` | `03 05 01 01 01 05 00 00 00 00` |

Readback through `08 84` can return duplicated or interleaved lanes. For the
observed 16-byte shape, after the leading `<slot> 00` prefix, the even lane forms
the written 7-byte function block and the odd lane can contain the previous or
default block. The client must prefer the even lane when it decodes instead of
preferring a default block from the odd lane. Wheel-tilt default readback can use
the shortened horizontal-scroll block `0e 01 68 00 14 00 00` / `0e 01 69 00 14
00 00`; treat that as the slot default for `0x34` / `0x35`.

## Profile-Scoped And Global Surfaces

| Surface | Scope |
|---|---|
| Inventory `03 80` | Device profile list. |
| Active target `03 82` | Device runtime pointer. |
| UUID/name/owner metadata | Stored profile target. |
| DPI scalar/stages/token | Stored profile target plus target `0` active mirror. |
| Button bindings | Stored profile target plus target `0` active mirror plus target `1` live projection. |
| Brightness | Stored profile target plus target `0` active mirror plus target `1` live projection. |
| Static color | Stored profile target plus target `0` active mirror plus target `1` live projection. |
| Lighting zone catalog `10 80 00 01` | Device capability, not profile data. |
| Sleep timeout | Device setting. Do not include in profile snapshots. |
| Battery/status | Device telemetry. Do not include in profile snapshots. |
| Poll rate | Not mapped for BLE profile CRUD. |

## Excluded Surfaces

Do not include these in the first product CRUD API:

- macros
- advanced button action families beyond the existing mapped function blocks
- advanced lighting/effect persistence
- Synapse software-owned profile navigation
- a claimed atomic whole-profile blob

The client API is complete for the mapped core surfaces by orchestrating multiple
commands per profile operation. There is no mapped single-command bulk profile
read/write.
