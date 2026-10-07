# Naga V2 Pro wireless receiver discovery + validation (2026-10-06)

Device: Razer Naga V2 Pro on the 2.4 GHz receiver `1532:00A8`, firmware `0x02142000`.
Side panel physically installed for this capture: **2-button**.
Raw probe output: [probe-log.txt](probe-log.txt)

## Why

The Naga V2 Pro shares the Naga Pro family's slot table but uses its own product IDs, so it resolved
as an unsupported device. This capture records the read-only evidence used to add the `0x00A8` USB
profile, plus the write/readback checks that justify each shipped capability. Every write in the log
was followed by a readback and a restore; the final commands leave the palm logo off, matching the
owner's preference.

## Identity and state reads

| Read | Command | Observed |
| --- | --- | --- |
| Serial | `00:82` | `632511H24600722` |
| Firmware | `00:81` | `0x02142000` |
| Device mode | `00:84` | `00 00` (onboard memory active) |
| Poll rate | `00:85` | `01` (1000 Hz); `00:05` write/readback validated (`02` -> restore `01`) |
| DPI | `04:85` (storage `01`) | `08 98` = 2200; write/readback validated (2300 -> restore 2200) |
| DPI stages | `04:86` (storage `01`) | active token `2`, count `2`, stages `1100` / `2200` |
| Battery | `07:80` | charging `00`, raw level `7b` |
| Low battery threshold | `07:81` | `0d` |
| Idle time | `07:83` | `01 2c` = 300 s; `07:03` write/readback validated (360 -> restore 300) |
| Scroll mode | `02:94` | status `0x05` (not supported) |
| Scroll acceleration | `02:96` | `01 00` |
| Onboard profiles | `05:80` / `05:81` / `05:84` | count `02`, inventory `05 01 02` (max 5, assigned 1/2), active `01` |

## Button table

Profiles `03`, `04`, and `05` are unassigned banks and are byte-identical to each other, so they
read as the firmware-native table. The owner's live profile `01` carries a previous owner's remaps
(notably wheel tilt -> `PageUp`/`PageDown` as `0d 04 00 4b 00 32` / `0d 04 00 4e 00 32`).

| Slot group | Native block | Meaning |
| --- | --- | --- |
| `0x01`-`0x05` | `01 01 01` .. `01 01 05` | left / right / middle click, back / forward |
| `0x09` / `0x0A` | `01 01 09` / `01 01 0a` | scroll up / down |
| `0x0E` | `07 01 04` | undecoded class-`0x07` top button (preserved read-only) |
| `0x34` / `0x35` | `0e 01 68 00 14` / `0e 01 69 00 14` | wheel tilt left / right (Basilisk-family button IDs) |
| `0x40`-`0x4B` | `02 01 00 1e` .. `02 01 00 2e` | 12-button panel: keyboard `1..9, 0, -, =` |
| `0x50`-`0x55` | `02 01 00 1e` .. `02 01 00 23` | 6-button panel: keyboard `1..6` |
| `0x60` | `06 01 06` | undecoded class-`0x06` top button matching the DPI-cycle action (preserved read-only) |
| `0x6D` | `12 01 04` | undecoded class-`0x12` top button (preserved read-only) |

Notes:

- Both side panels use the same length-`0x01` keyboard encoding the Naga Pro native banks use, so
  the HID key sits in byte 3 (`02 01 00 1e` = keyboard `1`).
- Write + readback + restore was validated on slots `0x04`, `0x40`, `0x53`, and `0x55`.
- Both the firmware-native `0e 01 68 00 14` and the turbo `0e 03 68 00 8e` wheel-tilt forms
  round-trip on slot `0x34`.
- Slots `0x0B`/`0x0C` (the Naga Pro's DPI stage buttons) do **not** exist on this device; they
  return status `0x03` on every profile.

## Lighting

| Check | Command | Observed |
| --- | --- | --- |
| Zone | `0f:82` per LED | LED `0x04` (palm logo) answers; LEDs `0x01`-`0x03` and `0x06` fail |
| Effect read | `0f:82` `01 04 00` | `00 04 00` (effect `0x00` = off) while the logo is off |
| Brightness read | `0f:84` `01 04 00` | `ff` |
| Brightness write | `0f:04` `01 00 ff` | whole-device brightness addressed through LED `0x00` (OpenRazer uses `ZERO_LED`) |
| Per-LED effects | `0f:02` LED `0x04` | off, static, spectrum, wave, reactive, pulse random/single/dual all ACK; off, static, spectrum, and pulse single visually confirmed |
| Custom frames | `0f:03` | a single logo cell renders visually (magenta confirmed); a 3-cell row is also ACKed |
| Naga-Trinity static | `0f:03` `00 00 00 00 02 <r g b> x3` | ACKed; with brightness at 0 nothing is visible, and with brightness up only the first triplet lights the logo |
| Mode switcher | `0f:02` `00 00 08 00 00 00` | OpenRazer's pre-color-switch command; ACKed, kept in the log for reference |

LED `0x05` accepts writes and reads back as static, but no visible zone lit with the 2-button panel
installed, so the side-panel lighting question is left open.

## Gaps

- The 6-button and 12-button panels were not physically available during this pass, so their
  physical label order and any side-panel lighting remain unverified. Their firmware slots were
  still read and write/readback-tested through the receiver.
- The three undecoded top buttons (`0x0E`, `0x60`, `0x6D`) keep their factory bindings; their
  native function classes are not mapped yet.
- The wireless link idles aggressively: reads start returning status `0x04` (timeout) after a few
  idle minutes, so the log was captured while the mouse was awake.
