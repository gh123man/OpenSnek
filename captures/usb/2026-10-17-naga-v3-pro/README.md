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
| `0x6A` | `12 01 01` | front scroll-wheel button |

Method: every slot from `1` to `255` was read on the effective profile, then candidate slots were
temporarily rebound to distinct keyboard keys and pressed physically. The owner reported
`front index: a, back index: b, front scroll: d, pinky: c, profile button on bottom: e`, with the
**rear** behind-the-wheel button typing nothing. All temporary bindings were restored to the
factory blocks above and verified on both the live (`0x00`) and persistent (`0x01`) layers.

Notes:

- Razer's `23 / 17 / 13` programmable-button counts confirm the model: `23 - 12 = 17 - 6 = 13 - 2 = 11`
  body buttons, so the 2-button plate reuses the Naga Pro family's slots `0x04`/`0x05` while the 6-
  and 12-button plates keep slots `80-85` and `64-75`.
- Slots `0x06`-`0x08`, `0x0D`, `0x0F`-`0x33`, `0x36`-`0x38`, `0x3A`-`0x3F`, `0x4C`-`0x4F`,
  `0x56`-`0x5F`, `0x61`-`0x69`, `0x6B`-`0x7F`, and `0x81`-`0xFF` do not exist on this device
  (reads rejected). Slot `0x80` answers a null `00 01 00 00 00 00 00` block.
- Every slot in the table round-tripped a same-value write on **both** the live and persistent
  layers, so the shipped profile treats the whole table as editable.
- The two index-finger buttons and the scroll-wheel button carry vendor-specific factory actions
  (`DPI` and the wheel mode), so they have no semantic default binding and keep their factory block
  as the Default restore target.

### The rear behind-the-wheel button is not a remappable slot

The rear button switches the wheel between tactile, free-spin, and smart-reel behavior. It did not
answer reads for any slot `1..255`, and rebinding slots `0x04`/`0x05` to keyboard actions did not
make it type, so it is not addressable through the per-profile button table. The device also rejects
the protocol scroll-mode pair (`02:94` returns status `0x05`). Razer's product material describes the
mode switching as automatic based on scroll speed with a Synapse-tunable responsiveness level, which
matches a device-level control rather than a per-profile binding. OpenSnek therefore does not expose
it and does not guess a slot for it.

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

- The 6-button and 2-button plates were not physically available during this pass, so their label
  order and the 2-button plate's reversed label mapping are inherited from the Naga Pro family
  rather than re-validated here.
- Only the 2.4 GHz receiver identity (`0x00E8`) was observed. A wired-cable identity for the Naga
  V3 Pro has not been seen yet, so the profile claims only the receiver PID.
- Onboard profile metadata reads are rejected, so profile name/owner/UUID round-tripping and
  profile create/delete remain unvalidated. Stored-bank DPI, stage, and brightness writes do work.
- Software lighting custom frames (`0f:03`) were not exercised on this device.
