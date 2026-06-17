# Basilisk V3 Pro USB Profile CRUD Spec

This spec defines the Basilisk V3-family USB onboard-profile API for the mapped
core profile surface. It intentionally excludes macros, advanced button
families, and advanced lighting effects.

Validated device: Basilisk V3 Pro USB PID `0x00AB`/`0x00AA`.

## Storage Model

USB profile-addressed commands use a one-byte storage/profile ID.

| Storage/profile | Meaning | Client behavior |
|---:|---|---|
| `0` | Effective active profile | Read only for hydration after profile changes. Mirrors the firmware-selected profile. |
| `1` | Base/default profile | Assignable and selectable. Often mirrors profile `0` while active. |
| `2` | Stored profile 2 | Assigned only when listed by `05:81`. |
| `3` | Stored profile 3 | Assigned only when listed by `05:81`. |
| `4` | Stored profile 4 | Readable even when unassigned. |
| `5` | Stored profile 5 | Readable even when unassigned. |

Readable banks are not necessarily assigned onboard profiles. The assigned
profile set is `05:81`, not the set of banks that respond to reads.

## Status Codes

| Status | Meaning in profile flows |
|---:|---|
| `0x02` | Success. |
| `0x03` | Rejected in current profile state, commonly unassigned/non-cycleable profile. |
| `0x04` | Timeout/no response. |
| `0x05` | Unsupported command. |

Every write must validate the response class/cmd echo, success status, and
requested profile ID when the command echoes one.

## Client API

### `listProfiles()`

Read assigned profile IDs:

```text
Count: class 05, cmd 80, size 00
List:  class 05, cmd 81, size 00
```

`05:80` returns the assigned-profile count in `args[0]`.

`05:81` returns:

```text
args[0]    = max profile ID
args[1...] = assigned profile IDs
```

Use `05:81` as the source of truth. `00:87` is stale summary telemetry on the V3
Pro and must not drive profile UI.

### `readActiveProfile()`

Read the active profile ID:

```text
Get:      class 05, cmd 84, size 00
Response: args[0] = active profile ID
```

The response can report `data_size = 00` while still carrying the active profile
ID in `args[0]`. Validate the success status and class/cmd echo, then read
`args[0]`.

### `activateProfile(profile)`

Select an assigned profile:

```text
Set:  class 05, cmd 04, size 01
Args: [0] = profile ID
```

Required confirmation:

1. Write returns success and echoes the requested profile.
2. `05:84` returns the requested profile.
3. Profile `0` reads match the selected profile where hydration is required.

If the selector returns `0x03`, leave the current active profile unchanged in
client state and refresh inventory.

### `watchProfileButton()`

The physical profile-cycle button emits passive USB HID hint reports on the
keyboard-style interface (`usagePage=0x01`, `usage=0x06`, `input=16`,
`feature=1`):

```text
04 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
05 39 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

Use the second report (`05 39 ...`) as the debounced event. The reports do not
carry a profile ID. On each event, read `05:84`, then hydrate storage/profile
`0` if the UI needs active settings.

### `readProfile(profile)`

Read the mapped profile snapshot by combining these surfaces:

| Surface | Read command | Arguments |
|---|---|---|
| Metadata | `05:88`, size `0x50` | `<profile> <offset_hi> <offset_lo> 00 fa` |
| DPI scalar | `04:85`, size `07` | `<profile> 00 00 00 00 00 00` |
| DPI stages | `04:86`, size `26` | `<profile> ...` |
| Button binding | `02:8C`, size `0A` | `<profile> <slot> <hypershift> 00 00 00 00 00 00 00` |
| Brightness | `0F:84`, size `03` | `<profile> <led> 00` |
| Static/effect state | `0F:82`, size `0C` | `<profile> <led> 00 00 00 00 00 00 00 00 00 00` |

Profile `0` reads the effective active state. Profiles `1..5` read profile
banks whether or not they are assigned.

### `createProfile(profile, metadata, content)`

Create/assign uses an explicit profile ID. The API must choose a profile from
`2..5` that is not present in `05:81`, unless the caller is intentionally
replacing an assigned profile.

Validated transaction:

```text
1. Set 05:02 <profile>
2. Write metadata field chunks through 05:08
3. Write DPI stages, then DPI scalar
4. Write mapped button bindings
5. Write brightness values
6. Write static-color values when the source lighting mode is static
7. Read back inventory, metadata, and every written content surface
```

`05:02` can initialize or disturb existing bank content. Treat create as
"assign metadata, then write the complete desired profile content". Never assume
the target bank remains content-preserving across `05:02`.

The profile is valid only after readback succeeds:

- `05:81` contains `profile`.
- `05:04 <profile>` succeeds, or the client deliberately skips selector probing.
- `05:88` returns the requested UUID/name.
- DPI, button bindings, brightness, and static colors match the requested
  content.

### `renameProfile(profile, metadata)`

Rename is a metadata rewrite on an assigned profile.

Required preconditions:

- `profile` is present in `05:81`.
- The client has a complete metadata object, preserving UUID/owner fields unless
  the user intentionally changes them.

Transaction:

```text
1. Write metadata field chunks through 05:08
2. Read 05:88 and verify UUID/name
```

Direct `05:08` writes to unassigned banks return status `0x03`; use
`createProfile` to assign a bank.

### `updateProfile(profile, changes)`

For stored profiles, write only changed mapped surfaces, then read back each
surface:

| Surface | Write command | Arguments |
|---|---|---|
| DPI scalar | `04:05`, size `07` | `<profile> <dpi_x_be16> <dpi_y_be16> 00 00` |
| DPI stages | `04:06`, size `26` | `<profile> <active_stage_id> <count> <rows...>` |
| Button binding | `02:0C`, size `0A` | `<profile> <slot> <hypershift> <7-byte function block>` |
| Brightness | `0F:04`, size `03` | `<profile> <led> <brightness>` |
| Static color | `0F:02`, size `09` | `<profile> <led> 01 00 00 01 <R> <G> <B>` |

When writing both DPI stages and DPI scalar, write stages first and scalar
second. A stage-table write can re-project the scalar readback to the selected
stage value.

### `deleteProfile(profile)`

Delete means unassign from the firmware cycle ring:

```text
Set:  class 05, cmd 03, size 01
Args: [0] = profile ID
```

Required confirmation:

- Write returns success and echoes the requested profile.
- `05:81` no longer contains `profile`.
- `05:04 <profile>` rejects with status `0x03` if probed.

Do not treat delete as secure erase. Metadata/settings can remain readable after
unassign and can be reused by a later create flow.

## Metadata Object

The USB metadata object is 250 bytes (`0x00fa`) and is transferred through
`05:08` write chunks and `05:88` reads.

### Chunk Header

```text
<profile> <offset_hi> <offset_lo> 00 fa
```

Reads use four full `0x50` reports. Each report carries a 5-byte header plus 75
data bytes.

Offsets:

```text
0000, 004b, 0096, 00e1
```

Product writes only send chunks that overlap the modeled UUID/name/owner fields:
`0000`, `004b`, and `0096`. The `00e1` chunk is padding-only for the current
metadata model and can be rejected by the V3 Pro USB firmware even after the
useful metadata bytes have landed. Do not require that padding-only tail write
for create or rename success.

### Fields

| Offset | Size | Encoding |
|---:|---:|---|
| `0x0000` | 16 | UUID in Windows/GUID little-endian byte order. |
| `0x0010` | Up to 100 | UTF-8/ASCII profile name, zero-padded. |
| `0x0074` | 64 | ASCII owner hash, zero-padded. |

Names longer than the available field must be rejected or truncated by the
client before writing. The current probe uses ASCII names.

## DPI Encoding

### Scalar

```text
Get: 04:85, size 07
Set: 04:05, size 07
Args:
  [0]    profile
  [1..2] DPI X, big-endian
  [3..4] DPI Y, big-endian
  [5..6] zero on writes
```

### Stages

```text
Get: 04:86, size 26
Set: 04:06, size 26
Args:
  [0] profile
  [1] active stage ID token
  [2] stage count
  [3...] stage rows
```

Stage row:

```text
<stage_id> <dpi_x_be16> <dpi_y_be16> 00 00
```

Preserve stage IDs when rewriting a table.

## Button Binding Encoding

```text
Get: 02:8C, size 0A
Set: 02:0C, size 0A
Args:
  [0] profile
  [1] button slot
  [2] hypershift flag
  [3..9] 7-byte USB function block
```

Use the shared USB button-function block decoder/encoder. Do not expose profile
button slot `0x6A` in product UI until its write/readback path is reliable.

## Lighting Encoding

### Brightness

```text
Get: 0F:84, size 03
Set: 0F:04, size 03
Args:
  [0] profile
  [1] LED ID
  [2] brightness for set, zero placeholder for get
```

Validated V3 Pro LED IDs:

```text
01 scroll wheel
04 logo
0a underglow
```

### Static Color / Effect State

USB effect-state reads use `0F:82`, size `0x0C`.

```text
Get: 0F:82, size 0C
Args:
  [0] profile
  [1] LED ID
  [2..11] zero placeholder

Observed response payload:
  [0] storage echo, currently 00 on V3 Pro even for stored-profile reads
  [1] LED ID
  [2] effect ID
  [3..] effect parameters
```

Static-color responses use:

```text
00 <led> 01 00 00 01 <R> <G> <B> 00 00 00
```

Static-color writes use `0F:02`, size `0x09`:

```text
<profile> <led> 01 00 00 01 <R> <G> <B>
```

On the validated V3 Pro, writing static colors to assigned profile `2`, then
selecting profile `2` with `05:04`, made effective profile `0` return the same
per-LED static colors through `0F:82`. The original profile effect payloads were
restored through `0F:02`.

Non-static effect payloads are readable as raw `0F:82` effect state, but the v1
client snapshot exposes only static colors. Do not infer or rewrite non-static
effect semantics until the effect-state model is expanded.

## BLE Mapping

| Bluetooth behavior | USB counterpart | Rule |
|---|---|---|
| Inventory `03:80` | `05:81`, count hint `05:80` | Use inventory as assigned-profile source of truth. |
| Active target read `03:82` | `05:84` | Read after profile-button hints and selector writes. |
| Active target select `03:02` | `05:04` | Assigned profiles only. |
| Metadata read `03:84` | `05:88` | Same UUID/name/owner object. |
| Metadata write `03:04` | `05:08` | Assigned profiles only unless create prelude runs. |
| Create prelude `03:06` + `08:05`/`08:07` + `03:05` | `05:02` | Assigns an unlisted bank before metadata writes. |
| Delete/unassign `03:06` | `05:03` | Removes from cycle ring; does not erase readable bank. |

USB and Bluetooth have parity for the mapped core CRUD surface. They do not
share command IDs or framing.

## Profile-Scoped And Global Surfaces

| Surface | Scope |
|---|---|
| Inventory `05:81` / count `05:80` | Device profile list. |
| Active profile `05:84` | Device runtime pointer. |
| UUID/name/owner metadata | Stored profile bank. |
| DPI scalar/stages | Stored profile bank plus profile `0` active mirror. |
| Button bindings | Stored profile bank plus profile `0` active mirror. |
| Brightness | Stored profile bank plus profile `0` active mirror. |
| Static colors | Stored profile bank plus profile `0` active mirror. |
| Non-static effect payloads | Readable raw effect state; not exposed in v1 snapshots. |
| Serial, firmware | Device telemetry. |
| Battery | Device telemetry. |
| Sleep timeout / idle time | Device setting. Do not include in profile snapshots. |
| Low battery threshold | Device setting. Do not include in profile snapshots. |
| Poll rate | Device setting. Do not include in profile snapshots. |
| Device mode | Device setting. Do not include in profile snapshots. |
| Scroll mode / acceleration / smart reel | Device setting or single VARSTORE, not profile CRUD. |

## Excluded Surfaces

Do not include these in the first product CRUD API:

- macros
- advanced button action families beyond the existing mapped function blocks
- non-static effect payload editing beyond static colors
- Synapse software-owned profile navigation
- a claimed atomic whole-profile blob

The client API is complete for the mapped core surfaces by orchestrating multiple
commands per profile operation. There is no mapped single-command bulk profile
read/write.
