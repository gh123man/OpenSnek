# Naga Pro native default banks + native block-form write test (2026-10-05)

Device: Razer Naga Pro, 2.4 GHz receiver `1532:0090`, firmware string `0x00112100`, USB HID.
Side panel physically installed for this capture: **2-button**.
Raw probe output: [A-probe-log.txt](A-probe-log.txt)
Write-test transcript: [B-native-block-write-test.txt](B-native-block-write-test.txt)

This capture exists to advance the remaining Naga Pro work in
[issue #56](https://github.com/gh123man/OpenSnek/issues/56): native factory blocks for slots `64-75`
and `80-82`, the class-`0x03` action on slots `83-85`, and the full-reset preflight blocker.

## Why the active profile could not be used

The unit is not factory-fresh on its active profile: it carries a previous owner's Synapse profile
named `"Jack"`, which remapped wheel tilt to keyboard `PageUp`/`PageDown` (`0d 04 00 4b` /
`0d 04 00 4e`) and the 12-button panel to numpad `1-0` plus back/forward.

The device reports two assigned profiles (`0x01`, `0x02`); profiles **`0x03`, `0x04`, and `0x05` are
unassigned stored banks that still hold coherent, firmware-initialized tables**. All three banks are
byte-identical, including DPI stages (`400/800/1600/3200/6400`, active token `0x03`) and brightness
`85`. They read in a *different encoding* from Synapse-written content (`02 01` / `0e 01` instead of
`02 02` / `0e 03`), which is why they look like firmware defaults rather than tool-written data.

## Captured native default banks (profiles 3/4/5, identical)

| Slot group | Native block | Meaning |
| --- | --- | --- |
| 1 / 2 / 3 | `01 01 01` / `01 01 02` / `01 01 03` | left / right / middle click |
| 4 / 5 | `01 01 04` / `01 01 05` | back / forward (2-button panel) |
| 9 / 10 | `01 01 09` / `01 01 0a` | scroll up / down |
| 11 / 12 | `06 01 01` / `06 01 02` | class `0x06` sub-ID `01` / `02` (DPI down / up?) |
| 14 | `07 01 04` | class `0x07` data `04` (scroll-mode toggle?) |
| 52 / 53 | `0e 01 09 00 14` / `0e 01 0a 00 14` | scroll left / right, no turbo |
| 64-75 (12-button panel) | `02 01 00 1e` .. `02 01 00 2e` | keyboard `1 2 3 4 5 6 7 8 9 0 - =` |
| 80-85 (6-button panel) | `02 01 00 1e` .. `02 01 00 23` | keyboard `1 2 3 4 5 6` |

**No class-`0x03` block appears anywhere on this unit**, including slots `83-85`. On this firmware
those three 6-button-panel slots carry plain keyboard `4` / `5` / `6` blocks.

## Encoding difference

OpenSnek's writer emits function-data length `0x02` for keyboard blocks (`02 02 00 <key>`) and
`0x03` for turbo scroll (`0e 03 <buttonID> <rateHi> <rateLo>`). The firmware's own default banks use
length `0x01` with the same payload offsets:

- native keyboard `1`: `02 01 00 1e`
- native scroll left: `0e 01 09 00 14`

`ButtonBindingSupport.buttonBindingDraftFromUSBFunctionBlock` treats byte 1 as a length, so
`02 01 00 1e` decodes as `data = [0x00]` and falls back to HID key `0x04` (`'A'`). The write test in
[B-native-block-write-test.txt](B-native-block-write-test.txt) proves physically that the firmware
emits `'1'` for that block, so the native key is byte 3.

## Related observation: Synapse-written mouse-button blocks

The live profile also stores class-`0x01` body buttons in a second encoding that the current
decoder misreads:

| Slot | Live block | Decodes as today | Expected |
| --- | --- | --- | --- |
| 4 | `01 01 01 04 e4 00 00` | left click | back |
| 5 | `01 01 01 05 e4 00 00` | left click | forward |
| 9 | `01 01 01 09 e4 00 00` | left click | scroll up |
| 10 | `01 01 01 0a e4 00 00` | left click | scroll down |

The button ID sits in byte 3 (`01 01 01 <buttonID> <x>`), while the firmware-native and
OpenSnek-written forms put it in byte 2 (`01 01 <buttonID> ...`). Both forms round-trip unchanged
through `0x02:0x0C` / `0x02:0x8C`, so this is a decoder gap rather than firmware normalization.
It is pre-existing and out of scope for the native-defaults change; captured here so it can be
fixed separately.

## Limitations

- Only the 2-button panel is available, so slots `64-85` could not be physically pressed.
- The default banks come from unassigned profile banks. Whether maintainers accept those as the
  source for `defaultUSBFunctionBlock` is a design decision for issue #56.
- The shipped wheel-tilt default (`0e 03 09 00 8e`, turbo enabled) differs from the stored native
  block (`0e 01 09 00 14`, no turbo). Same button ID, different encoding; both need maintainer review.
