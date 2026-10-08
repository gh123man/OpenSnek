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

## Lighting follow-up (cross-reference)

The side-panel lighting investigation in `captures/ble/2026-10-07-naga-v2-pro-buttons/README.md`
confirms two lit zones on both transports: logo LED `0x04` and 12-button side-panel LED `0x05`.
The 6- and 2-button plates have no lighting, and there is no scroll-wheel zone. The shipped USB
profile currently declares only the logo zone and should gain the side-panel zone for parity.

## Wired USB pass (2026-10-07, direct cable)

Device: Razer Naga V2 Pro wired, `1532:00A7`, location `0x02150000`.

| Read | Result |
| --- | --- |
| USB id | `1532:00a7:02150000:usb` |
| Firmware `00:81` | `01 03 00 00` (same shape as BLE; not the receiver's `0x02142000`) |
| Serial `00:82` | `632511H24600722` |
| Battery `07:80` | raw `0x45`, 27% (matches receiver/BLE/Synapse) |
| Active profile | base (profile 1) |
| Profile inventory | max 5, assigned 1/2; stored Jack (2) intact |

Button surface is identical to the receiver: panel slots `64-75`/`80-85` carry native keyboard
defaults, live slots `96`/`109` carry the F18/F19 remaps, wheel tilt is the PageUp/PageDown
remap, and slots `14`/`96`/`109` match the receiver readings.

Lighting: raw reads confirm both zones over the cable.

| LED | Brightness (wired) |
| --- | --- |
| `0x04` logo | `0x59` |
| `0x05` 12-button side panel | `0x59` |

Both match the owner's Synapse green state, so the side-panel zone is available on wired,
receiver, and Bluetooth alike.

Write path: `usb-button-set --profile direct` on slot 64 staged `02 02 00 04` and restored
`02 01 00 1e` byte-for-byte over the cable.

Conclusion: the shipped USB profile should accept wired `0x00A7` alongside receiver `0x00A8`.

## Slot 0x0E / bottom button test (2026-10-07, live)

Staged keyboard `q` on the live direct layer of slot `0x0E` and pressed the bottom button.
The button kept cycling DPI instead of typing `q`, so slot `0x0E` is not the bottom button and
the bottom control is not remappable through the vendor button table. The original block
(`06 01 06`, DPI cycle) was restored and verified.

Slot `0x0E` stays documented read-only; its physical control on the V2 Pro remains unidentified
(it may not be present on this model at all).

## Slot 0x0E = bottom button (2026-10-07, live)

Correcting the earlier "not the bottom button" note: the first two tests failed because Razer
Synapse 4 for macOS was open and rewriting the device while the remap was staged. With Synapse
closed:

1. Staged keyboard `q` on both layers of slot `0x0E`; the bottom button typed `q` on each press.
2. Staged the factory block `07 01 04`; the bottom button changed the active onboard profile
   (confirmed by the active-profile read in the follow-up test below).
3. Restored the owner's Synapse mapping `06 01 06` on both layers and verified.

Conclusions:

- Slot `0x0E` is the bottom button and it is fully remappable.
- The factory block `07 01 04` (class `0x07`, data `0x04`) cycles onboard profiles: staging it
  and pressing the bottom button moved the active profile from 1 to 2 while the DPI stage token
  stayed put. Synapse's `06 01 06` remap is DPI-stage cycling.
- The app promotes slot `0x0E` to editable with a `Default` restore to `07 01 04`.
- Synapse 4 for macOS holds the device and overrides concurrent probe writes; close it before
  any vendor button write.

## USB charging-status protocol note (2026-10-08)

While the mouse was cabled and charging, the battery-level command `07:80` returned
`00 7d` (unused first argument + level `0x7d` = 49%), and the dedicated charging command
`07:84` returned `00 01` (second argument `0x01` = charging):

```
$ usb-raw --class 0x07 --cmd 0x80 --size 0x02
response[90]: 02 1f 00 00 00 02 07 80 00 7d 00 ...

$ usb-raw --class 0x07 --cmd 0x84 --size 0x02
response[90]: 02 1f 00 00 00 02 07 84 00 01 00 ...
```

OpenRazer splits the same way (`razer_chroma_misc_get_battery_level` = `07:80`,
`razer_chroma_misc_get_charging_status` = `07:84`). OpenSnek previously read byte 8 of the
`07:80` response as the charging flag, which is always `0x00`, so the charging icon never
appeared.

## Charging indicator note (2026-10-08)

While cabled and charging, the palm logo periodically flashes a random color for a fraction of a
second (observed roughly every 10 seconds). This is firmware charging/battery indication, not a
lighting effect and not host-controllable:

- Across ~200 samples spanning the flashes, the active onboard profile stored effect stayed `00`
  (Off) and the `0F:84` brightness register never changed.
- The flashes stopped when the mouse was switched to its 2.4 GHz wireless link (not charging).
- No OpenSnek process (app or background service) was running while the flashes were observed, and
  the device never re-enumerated during the samples.

Writing an effect or brightness change does not suppress the flash; only unplugging or running on
wireless does.
