# Naga V3 Pro 2.4 GHz receiver discovery + validation (2026-10-17)

Device: Razer Naga V3 Pro on its own 2.4 GHz receiver dongle `1532:00E8`, firmware `0x02010201`,
serial `632634H38609522`, `bcdDevice` `0x0100`. Side plate physically installed: **12-button**.
Raw probe output: [probe-log.txt](probe-log.txt), full slot sweep: [slot-sweep.txt](slot-sweep.txt).

## Why

The Naga V3 Pro is the first Naga that is not a Naga Pro / Naga V2 Pro variant, so it resolved as an
unsupported device. This capture records the read-only evidence used to add the `0x00E8` USB profile
plus the write/readback/restore checks that justify each shipped capability. Every write in the log
was followed by a readback and a restore, and the mouse was left on its original state: five DPI
stages `400/800/1600/3200/6400` with `1600` active, spectrum lighting at brightness `85` on all
three zones, and factory button bindings.

## Identity and state reads

| Read | Command | Observed |
| --- | --- | --- |
| Serial | `00:82` | `632634H38609522` |
| Firmware | `00:81` | `0x02010201` |
| Device mode | `00:84` | `00 00` (onboard memory active) |
| Poll rate | `00:85` | `01` (1000 Hz); `00:05` write/readback validated (`02` -> restore `01`) |
| DPI scalar | `04:85` (storage `01`) | `06 40 06 40` = `1600` / `1600`; write `1700` -> readback -> restore validated |
| DPI stages | `04:86` (storage `01`) | active token `0x03`, count `5`, stages `400/800/1600/3200/6400`; same-value write read back byte-identical |
| Independent X/Y | `04:05` | `800x1600` read back as `03 20 06 40`, so `supportsIndependentXYDPI` ships enabled |
| DPI ceiling | `04:05` | the firmware stores and echoes `30000`, `35000`, `45000`, `50000`, and `60000` without clamping; Razer's published Focus Pro 50K ceiling (`50000`) is therefore the authoritative limit |
| Battery | `07:80` | charging `00`, raw level `a4` (`64%`) |
| Low battery threshold | `07:81` | `4d` |
| Idle time | `07:83` | `01 2c` = 300 s; `07:03` write `360` -> readback -> restore validated |
| Scroll mode | `02:94` | status `0x05` (not supported), so scroll-mode controls stay hidden |
| Scroll acceleration / smart reel | `02:96` / `02:97` | `00` / `00` |
| Onboard profiles | `05:80` / `05:81` / `05:84` / `00:87` | count `01`, inventory `05 01` (max `5`, assigned `1`), active `1`, summary `01 01 00` |
| Onboard profile metadata | `05:88` slots `02`-`05`, offsets `0x0000`/`0x0080`/`0x0100` | every read answers status `0x03`, so onboard profile CRUD ships disabled |
| Onboard profile writes | stored slot `4` (`profile=5`) | same-value DPI scalar, DPI stages, and brightness writes all round-trip (`status=ok`) even though metadata cannot be read |
| Active profile select | `05:04` target `2` | rejected while slot 2 is unassigned; the device only activates assigned profiles |

## Button table

| Slot | Factory block | Physical control |
| --- | --- | --- |
| `0x01`-`0x03` | `01 01 01` .. `01 01 03` | left / right / middle click |
| `0x04` | `01 01 04` | 2-button plate label 2 (no dedicated body button) |
| `0x05` | `01 01 05` | 2-button plate label 1 (no dedicated body button) |
| `0x09` / `0x0A` | `01 01 09` / `01 01 0a` | scroll up / scroll down |
| `0x0B` | `06 01 01` | front index-finger button (factory DPI action) |
| `0x0C` | `06 01 02` | rear index-finger button (factory DPI action) |
| `0x0E` | `07 01 04` | underside profile button |
| `0x34` / `0x35` | `0e 01 68 00 14` / `0e 01 69 00 14` | wheel tilt left / right |
| `0x39` | `0c 01 39` | pinky button |
| `0x40`-`0x4B` | `02 01 00 1e` .. `02 01 00 2e` | 12-button plate: keyboard `1..9, 0, -, =` |
| `0x50`-`0x55` | `02 01 00 1e` .. `02 01 00 23` | 6-button plate: keyboard `1..6` |
| `0x6A` | `12 01 01` | front scroll-wheel button (cycles the wheel mode) |
| `0x80` | `00 01 00` | rear scroll-wheel button (no action by default) |

### Finding slot `0x80` (128): use the device's own inventory

A read sweep of every slot `1..255` reported slot `0x80` as a null-looking `00 01 00 00 00 00 00`
block, and slot `0x80` is *after* the last slot the sweep's candidate list covered meaningfully, so it
was initially dismissed as padding. Press-validating the neighbouring slots produced no match for the
rear behind-the-wheel button, which looked like a firmware-only control.

The device actually publishes its own mappable-button inventory on `02:84`: a count byte followed by
one slot ID per mappable button. `OpenSnekProbe usb-button-inventory` reads it:

```
button-inventory class=02 cmd=84 count=33
slots=[1,2,11,12,14,3,52,53,106,57,128,66,65,64,69,68,67,72,71,70,75,74,73,80,81,82,83,84,85,5,4,9,10]
```

That is exactly the 32 slots the read sweep found plus slot `128`. The eleven body buttons
(`1,2,3,11,12,14,52,53,57,106,128`) also match Razer's published `23 / 17 / 13` programmable-button
counts, since `23 - 12 = 17 - 6 = 13 - 2 = 11`.

Binding slot `128` to a keyboard key made the rear wheel button type that key, so the button is
remappable and the slot is real. A later, more careful owner pass corrected which button carries the
wheel-mode cycle: it is the **front** button (slot `0x6A`/`106`, factory `12 01 01`, a class-`0x12`
action), while the **rear** button ships the class-`0x00` no-action form and does nothing by default.
Writing the factory blocks back (`12 01 01` for slot `106`, `00 01 00` for slot `128`) restored both
behaviors and was verified by readback on both layers.

Method: every slot from `1` to `255` was read on the effective profile, then candidate slots were
temporarily rebound to distinct keyboard keys and pressed physically. The owner reported
`front index: a, back index: b, front scroll: d, pinky: c, profile button on bottom: e`, with the
**rear** behind-the-wheel button typing nothing at the time because its slot had not been bound yet.
All temporary bindings were restored to the factory blocks above and verified on both the live
(`0x00`) and persistent (`0x01`) layers.

Notes:

- Razer's `23 / 17 / 13` programmable-button counts confirm the model: `23 - 12 = 17 - 6 = 13 - 2 = 11`
  body buttons, so the 2-button plate reuses the Naga Pro family's slots `0x04`/`0x05` while the 6-
  and 12-button plates keep slots `80-85` and `64-75`.
- Slots `0x06`-`0x08`, `0x0D`, `0x0F`-`0x33`, `0x36`-`0x38`, `0x3A`-`0x3F`, `0x4C`-`0x4F`,
  `0x56`-`0x5F`, `0x61`-`0x69`, `0x6B`-`0x7F`, and `0x81`-`0xFF` are absent from the inventory and
  do not answer reads.
- Every slot in the table round-tripped a same-value write on **both** the live and persistent
  layers, so the shipped profile treats the whole table as editable.
- The two index-finger buttons, both scroll-wheel buttons, the pinky button, and the underside
  profile button carry vendor-specific factory actions, so they have no semantic default binding and
  keep their factory block as the Default restore target.

## Side plates

The owner has all three plates.

- **2-button plate — press-validated.** The plate has no printed labels. With slot `4` bound to `j`
  and slot `5` bound to `k`, the forward button typed `k` and the rear button typed `j`, confirming
  the Naga Pro family's reversed mapping (forward = slot `05`, rear = slot `04`). The same test on a
  Naga Pro receiver (`0x0090`, 2-button plate) produced the identical `kj` result, and that device's
  own inventory matches its shipped profile, so the family mapping is consistent.
- **6-button plate** matches the Naga V2 Pro layout (labels 1-6 → slots `80`-`85`).
- **Lighting:** neither the 6-button nor the 2-button plate has any lighting, so the side-panel LED
  `0x05` zone only lights the 12-button plate.

The firmware answers for every plate's slots regardless of which plate is fitted (the inventory above
was read with the 12-button plate installed), and it does not report which plate is fitted.

## Lighting

| Check | Command | Observed |
| --- | --- | --- |
| Zones | `0f:82` / `0f:84` per LED | LEDs `0x01`, `0x04`, and `0x05` answer; `0x00`, `0x0A`-`0x0C`, `0x10` are rejected |
| Zone identity | `0f:02` static per LED | visually confirmed by the owner: `0x01` scroll wheel, `0x04` logo, `0x05` side panel, matching Razer's "Logo, Scroll Wheel and 12 button side plate" |
| Brightness | `0f:84` `01 <led> 00` | `55` on all three zones; `0f:04` write `100` -> readback -> restore `85` validated per zone |
| Effects | `0f:02` per LED | off, static, spectrum, wave, reactive, pulse random/single/dual all answer `status 0x02` and read back with the expected effect id |
| Effect rendering | `0f:02` per LED | visually confirmed by the owner: wheel wave, logo pulse single (breathing), side panel reactive all animate |
| Static restore | `0f:02` `01 <led> 03 00 00 00` | spectrum restored on all three zones at the end of the pass |

## Gaps

- The 6-button plate's label order is inherited from the Naga V2 Pro rather than press-validated on
  this device; the owner confirms the layout matches.
- Onboard profile metadata reads are rejected, so profile name/owner/UUID round-tripping and
  profile create/delete remain unvalidated. Stored-bank DPI, stage, and brightness writes do work.
- Software lighting custom frames (`0f:03`) were not exercised on this device.
- **The wheel mode (tactile / free-spin / smart-reel) is not readable.** Every `(class, cmd)` pair the
  device answers with status `0x02` was collected ([wheel-mode-candidates.txt](wheel-mode-candidates.txt),
  80 commands) and digested before and after a single front-button press
  ([wheel-mode-pre-press.txt](wheel-mode-pre-press.txt) /
  [wheel-mode-post-press.txt](wheel-mode-post-press.txt)). Only `07:85` moved (`00 03 23` ->
  `00 03 24`), and a follow-up correlation killed it as a mode readout: it read `00 03 23` while the
  wheel was free-spinning and stayed `00 03 23` across a press that the owner confirmed changed the
  wheel to notched. So the mode has no identified readout, `07:85` must not be used as one, and the
  mode can only be changed with slot `106`'s factory action.

### Next instrument: a Windows Synapse capture

Synapse for macOS does not support this mouse, so the mode and its five responsiveness levels can
only be observed from a host Razer supports. A USB capture there would settle it:

1. On a Windows host, install Razer Synapse plus Wireshark with USBPcap, and filter to the mouse's
   VID/PID.
2. Capture an idle baseline, then change the wheel mode through each mode from Synapse's UI, then
   move the responsiveness slider through all five levels.
3. Compare those writes against [wheel-mode-candidates.txt](wheel-mode-candidates.txt) — 80 commands
   this firmware answers — paying attention to `02:94` (rejected here, status `0x05`), `07:85`,
   `02:98`, and the class-`0x06` block that all answered. Look for a setter whose value tracks the
   mode, plus a separate level.

If that turns up a pair, the profile can expose the mode as a real setting; until then it stays
button-only.
