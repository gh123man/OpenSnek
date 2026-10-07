# Naga V2 Pro button capture (2026-10-07, live session)

Device: Razer Naga V2 Pro, 2.4 GHz receiver `1532:00A8`, firmware `0x02142000`.
Session driven live over OpenSnekProbe (no wizard).

## Purpose

Finish the Naga V2 Pro button surface left open by PR #124:

- physical label order for the 12-button and 6-button side panels,
- decode the three top-button slots (`0x0E`, `0x60`, `0x6D`),
- check whether top buttons are writable despite shipping read-only,
- mirror the button surface over Bluetooth.

## Read sweep results

Effective profile (`profile=0`) and base profile (`profile=1`) are the live user layer and
carry the owner's remaps:

| Slot | Native (unassigned banks) | Effective/base (live) |
| --- | --- | --- |
| `0x34`/`0x35` wheel tilt | `0e 01 68 00 14` / `0e 01 69 00 14` | `0d 04 00 4b 00 32` (PageUp) / `0d 04 00 4e 00 32` (PageDown) |
| `0x43` (slot 67) 12-button label 4 | `02 01 00 21` | `02 02 00 21` (same key, explicit remap form) |
| `0x40`-`0x4B` | keyboard `1..9,0,-,=` | keyboard `1..9,0,-,=` |
| `0x50`-`0x55` | keyboard `1..6` | keyboard `1..6` |

Top-button slots in the live layer:

| Slot | Native | Effective/base | Stored profile 2 (`Jack`) |
| --- | --- | --- | --- |
| `0x0E` (14) | `07 01 04` (class `0x07`) | `07 01 04` | `06 01 06` (DPI cycle) |
| `0x60` (96) | `06 01 06` (DPI cycle) | `06 01 06` | `02 02 00 6e` (keyboard F19) |
| `0x6D` (109) | `12 01 04` (class `0x12`) | `12 01 04` | `02 02 00 6d` (keyboard F18) |

Key finding: stored profile `Jack` (profile 2) shows slots `0x60` and `0x6D` carrying
keyboard-simple remaps written through the standard `02 02 00 <key>` encoding, so those
slots are writable by the firmware even though OpenSnek currently preserves them read-only.
Slot `0x0E` is remapped to DPI cycle in that profile.

Hypershift reads (`--hypershift 1`) return a shifted window starting with class `0x00`; not
usable as a second binding layer through this probe shape.

## Files

- `probe-log.txt` - full identity + read sweep transcript
- `panel-12-label-map.txt` - physical label order (filled in live)
- `panel-6-label-map.txt` - physical label order (filled in live)
- `top-button-observations.txt` - physical behavior of the three top buttons

## Top-button pass (2026-10-07, live)

Physical/Synapse mapping from the owner:

| Physical control | Synapse default | Current Jack mapping | Slot |
| --- | --- | --- | --- |
| Forward top button (closer to wheel) | cycle up scroll-wheel stages | F18 | `0x6D` (109) |
| Rear top button | cycle down scroll-wheel stages | F19 | `0x60` (96) |
| Scroll click | middle click | middle click | `0x03` (3) |

Raw blocks:

| Slot | Onboard effective/base | Direct/live projection |
| --- | --- | --- |
| `0x60` (96) | `06 01 06` (class `0x06`) | `02 02 00 6e` = keyboard F19 |
| `0x6D` (109) | `12 01 04` (class `0x12`) | `02 02 00 6d` = keyboard F18 |

Notes:

- The two live layers differ: the onboard effective/base profile still holds the native
  class-`0x06`/`0x12` blocks, while the direct (RAM) projection carries the owner's F18/F19
  remaps. Physical presses follow the direct layer, which is why a press during this session
  emitted F18/F19 and did not move the DPI stage.
- Write validation: `usb-button-set --profile direct` to slots 96 and 109 applied and read back
  (`02 02 00 04` staged, then restored to `02 02 00 6e` / `02 02 00 6d`). Both slots accept
  function-block writes; they are only "read-only" in OpenSnek today because the app has not
  enabled them, not because the firmware refuses.
- Persisted evidence: the stored profile `Jack` (profile 2) carries the same F19/F18 blocks on
  slots 96/109, so the remaps survive as stored profile content too.
- Slot `0x0E` (14) native block `07 01 04` matches the Naga Pro v1 slot 14 ("Scroll Mode
  Toggle"). The physical control for it was not identified in this session.
- Probe note: `usb-button-set --hid-key` parses decimal, not hex; use `usb-button-set-raw --hex`
  for exact function blocks.
