# Basilisk V4 HyperSpeed Bluetooth bring-up

Local hardware research on **2026-11-08**, using the owner's connected mouse and
OpenSnek at `afe240d8`. No Windows/Synapse capture or physical button walkthrough
was required. The initial pass produced research evidence. The subsequent integration now registers
a Bluetooth profile for DPI, battery, sleep, brightness and all 12 button/wheel
slots with captured native defaults. The scoped observations below remain the basis for those claims;
physical validation and unexposed features remain pending.

Raw evidence and restored baseline:
[`captures/ble/2026-11-08-basilisk-v4-hyperspeed/`](../../captures/ble/2026-11-08-basilisk-v4-hyperspeed/README.md).

## Identity and external references

| Source | Finding |
|---|---|
| Local macOS HID + standard GATT PnP ID | `BSK V4 HS`, Bluetooth LE, VID `068E`, PID `00EC`, HID version `0100` |
| [Razer support, RZ01-0568](https://mysupport.razer.com/app/answers/detail/a_id/21065) | 33,000-DPI ceiling; one underglow zone; 10 programmable buttons; five onboard profiles; wired/receiver/Bluetooth connectivity |
| [Razer product page](https://www.razer.com/gaming-mice/razer-basilisk-v4-hyperspeed) | Physical model/specification reference; not a vendor protocol specification |
| [OpenRazer PR #2959, DIRT8IKE](https://github.com/openrazer/openrazer/pull/2959) | Contributor's wired/receiver implementation and hardware observations; explicitly does not implement Bluetooth |
| [OpenRazer issue #2955](https://github.com/openrazer/openrazer/issues/2955) | USB descriptor/HID report evidence for `1532:00EB` |

PR #2959 was open/unmerged at head
`a54e307c2682efc6ad774256ea4c1ddd8bed471c` when inspected. Its description assigns
`1532:00EA` to the receiver and `1532:00EB` to wired USB. These transport assignments
were **not locally tested during the Bluetooth pass**; the subsequent
[receiver mapping](BASILISK_V4_HYPERSPEED_USB.md) validates `00EA`. Its useful USB-specific findings are brightness reads
at LED `0A` but writes/effects at `00`, longer receiver waits on interface 3, and
poll-rate commands `00:8E/0E` with `[01, rate]`. These are leads, not BLE guarantees.
The PR reports reactive lighting and special-button limitations. No public V4 HS
Bluetooth command specification was found in the searched manufacturer/OpenRazer
sources.

## Transport and standard GATT

The existing Razer service works unchanged:

- Service `52401523-F97C-7F90-0E7F-6C6F4E36DB1C`.
- Write `...1524`, properties `12` (write and write-without-response); tested with
  write-with-response, serialized exchanges, no command retries.
- Notify `...1525`, properties `18` (read and notify). Eight-byte response headers
  and separate payload frames, including short final frames.
- Additional characteristic `...1526`, properties `18`; function not investigated.
- Standard Battery Service `180F`, level `2A19`.
- Device Information `180A`: model `2A24`, manufacturer `2A29`, PnP ID `2A50`.
  No firmware/hardware/software revision characteristic was exposed in this survey.
- PnP ID bytes `02 8e 06 ec 00 00 01`: USB vendor-ID source, VID `068E`, PID
  `00EC`, product version `0100`. Product version is not proof of firmware version.

HID reports use IDs `01` (mouse), `02` (consumer), `03` (system), `04`/`05`
(vendor-style input), `06` (keyboard). Maximum input size is nine bytes; maximum
feature size is one byte. The sanitized descriptor is in `hid-identity.json`.
Passive DPI/profile-event meaning was not physically validated.

## Results by feature

Here, **validated** means a local probe result for the exact operation described,
not end-to-end app support or physical rendering/press validation.

| Feature | Read | Changed write/readback | Exact restore | Remaining limit |
|---|---|---|---|---|
| DPI X/Y | Validated | 1600/1600 → 1700/1800 | Raw 36-byte baseline matched | 33K ceiling comes from Razer, not a ceiling write test |
| Stage count/selection | Validated | Five → one; five → three with second stage active | Five original stages and active ID matched after each | No power-cycle persistence check |
| Sleep timeout | `300` seconds | `301` seconds | `300` seconds | No actual sleep/wake cycle |
| Underglow brightness | `55` hex = 85/255 | `56` hex = 86/255 | `55` hex | Visible brightness change not independently observed |
| Battery | Vendor `69` hex, standard `29` hex | Read-only | N/A | One comparison point, no charging transition |
| Button inventory/bindings | 12 slots, targets 0 and 1 | Eight slots changed to right-click, both targets read back | All 16 bytes per target matched | Physical labels/presses still unverified |
| Lighting effects/color | Ten-byte state readable | Four tested address variants ACK but state stays unchanged | All tested state reads match baseline | **Not validated; do not enable static/effect writes** |
| Profile inventory/active target | Both return `01` | Not tested | N/A | Metadata GET rejected on targets 0, 1, 2; CRUD unproven |
| Poll rate | Two USB-inspired BLE candidates return `05` | Not attempted | N/A | No mapped BLE poll-rate command |

All mutating exchanges used an immutable CoreBluetooth peripheral UUID, a private
original-state journal, and `BLEProbeSession` with the app/service stopped. Each
setting was restored before moving on. The final journal phase is `restored` and
the final full snapshot matched every captured mutable baseline. No driver-mode,
profile-create/delete/select, firmware, pairing, or unknown-opcode writes were sent.
No serials, Bluetooth addresses, peripheral UUIDs, or personal profile metadata are
included in the committed evidence.

## DPI

Reads: `0B 84 01 00` (stage table), `0B 81 01 00` (current X/Y),
`0B 82 01 00` (pair/triple list), `0B 83 01 00` (active stage ID).
Write: `0B 04 01 00`, 38 bytes.

With five stages the baseline table is 36 bytes: active ID `03`, count `05`, IDs `01..05`, X/Y values
`400, 800, 1600, 3200, 6400`. Active ID resolves to the third stage. Seven-byte
entries contain an ID and little-endian X/Y plus trailing bytes. On this device
the trailing bytes resemble a third DPI coordinate, rather than zero padding;
the last entry is truncated by the 36-byte response. Do not reinterpret or destroy
these bytes merely because existing builders call part of them a marker.

Tests preserved the raw table, changed only X/Y or the count/active-ID bytes, and
appended two zero bytes for the 38-byte write. The entire returned 36-byte baseline
was restored after each test. Reads shrink to eight bytes for one stage and 22
bytes for three stages. The integrated app/probe retain previously observed hidden
stage bytes across these shortened reads and use a dedicated preserving builder.
A new session starting with fewer than five stages has no complete baseline and
refuses DPI writes rather than inventing the omitted bytes. This limitation remains
until a complete hidden-stage read or safe persistent baseline is available.

## Power

- `05 84 00 00` / `05 04 00 00`: two-byte LE timeout; `2c01 → 2d01 → 2c01`.
- `05 81 00 01`: vendor battery `69` hex = 105; standard `2A19` returned 41%.
  `floor(105 * 100 / 255) = 41`. Always using the byte scale is supported by this
  comparison; do not switch to literal percent for raw values below 100. Rounding
  versus truncation cannot be distinguished by this single measurement.
- `05 80 00 01`: `01`. Charging semantics remain unvalidated; do not automatically
  interpret it as charging. No cable/charge transition was tested.
- `05 82 00 00`: `4d` (77), consistent with the related-device low-battery-threshold
  candidate. No changed write or independent semantic confirmation was performed.

## Buttons

Inventory `08 80 00 00` and `08 80 01 00` both return:

```text
01 02 03 04 05 34 35 0e 39 80 09 0a
```

Read `08 84 <target> <slot>` returns 16 bytes: slot, layer, then interleaved
current and original function blocks. Current bytes are offsets `2,4,...14`;
the other lane is `3,5,...15`. Do not select a lane by whichever function happens
to decode first. The original lane remained at the baseline during each live test;
this experiment does not prove it is always the immediately previous write.

Write `08 04 01 <slot>` used ten bytes `[01, slot, 00] + seven-byte function block`.
Both target 0 and target 1 reflected the changed current block. Restoring the exact
original block made the full 16-byte responses byte-identical to their baselines.

| Slot | Original block | Interpretation / physical confidence | Changed/restore tested |
|---|---|---|---|
| `01` | `01010100000000` | Left click | Yes (follow-up) |
| `02` | `01010200000000` | Right click | Yes (follow-up) |
| `03` | `01010300000000` | Middle click | Yes (follow-up) |
| `04` | `01010400000000` | Back | Yes |
| `05` | `01010500000000` | Forward | Yes (follow-up) |
| `34` | `0e016800140000` | Left tilt, shared Basilisk horizontal-scroll function | Yes |
| `35` | `0e016900140000` | Right tilt, shared Basilisk horizontal-scroll function | Yes |
| `0e` | `07010400000000` | Profile-cycle function; underside profile button candidate | Yes |
| `39` | `0c013900000000` | Hypershift candidate from related-model function semantics | Yes |
| `80` | `00010000000000` | Host-dependent/unassigned function; AI Prompt Master candidate | Yes |
| `09` | `01010900000000` | Scroll up | Yes |
| `0a` | `01010a00000000` | Scroll down | Yes |

The inventory and native blocks are proven; the special-button physical assignments
are inference pending presses. Slot `80`'s block must not be normalized to all-zero
"clear layer". Neither V3 DPI-cycle slot `60` nor V3 clutch slot `0F` appears in the
inventory. No separate scroll-mode-toggle slot was advertised. Twelve inventory
entries versus ten programmable buttons is consistent with including wheel-up/down
events; it is not proof that every advertised entry is a distinct physical button.

## Lighting: success ACK is insufficient

- `10 80 00 01` returns only LED `0A` (underglow).
- Brightness `10 85 01 0A` / `10 05 01 0A` works and restores. Read target `00`
  also returns the same value. Brightness read `10 85 01 00` rejects with `03`.
- State reads `10 83 <00|01> <00|0A>` all return
  `03 01 28 01 00 ff 00 00 ff 00` at baseline. Target `02`, LED `0A`, also reads it.
- Effect-list candidates `10 82 00 00`, `10 82 00 0A`, `10 82 01 0A` return
  `00 01 02 03 05 08`. This is an advertised list, not demonstrated effect support.
- Legacy frame read `10 84 00 00` rejects with `03`.
- Static body `01 00 00 01 20 a0 60 00 00 00` was tried once at each of
  `10 03 00 0A`, `10 03 00 00`, `10 03 01 0A`, `10 03 01 00`.
  All ACK `02`; none changed the checked effect state. The target-1 pass checked
  all four state-read variants. Every attempt was followed by an original-body
  restore and baseline verification.

These failures do not prove that no visible LED change happened or that all effect
control is impossible. The state register could describe a stored effect while a
write changes only runtime rendering. Without physical confirmation or a known-good
Synapse capture there is no authoritative successful effect mapping. Avoid more
blind format/mode writes. In particular, do not switch `01 02` device mode: related
firmware has documented instability on that path.

## Profiles and other reads

- `03 80 00 00` inventory and `03 82 00 00` active target both return `01`.
  Do not infer five accessible/writable banks from the marketing profile count.
- Metadata GET `03 84 <00|01|02> 00` with offset/length body `00004c00` rejects
  with `03`. The CLI calls this `bt-raw-write` because the GET carries an ATT
  request body; it is not a profile mutation. No metadata contents were retained.
- Target-2 DPI, button `04`, and lighting-state reads succeed and match current
  values. Reads alone do not establish assigned banks or persistence.
- `01 8C 01 00` and `01 8C 02 00` return `08`; meaning unconfirmed.
- `01 82 00 00` returns `0000`; `01 86 00 00` returns `000000`.
- `00 81 00 00` returns `01001000`; do not label this firmware without evidence.
- `00 80 00 00` returns `404143`; `00 80 00 01` returns `0001050608`.
- `00 8E 00 00` and `00 8E 01 00` reject with `05`. These were narrow candidates
  prompted by the USB PR, not an exhaustive proof that Bluetooth polling is fixed.

## Integration decisions and remaining validation

1. Registered a **Bluetooth-only** `00EC` profile and normalize the `HS` advertised-name
   abbreviation without conflating V4 HS with V4 Pro. Validate wired/receiver IDs separately; the later receiver pass is linked above.
2. Use 33K in both editor/merge and wire clamps. Preserve raw trailing DPI bytes,
   IDs, hidden stages, and active-ID semantics. The actual app bridge passed the
   hardware DPI reliability sequence with original-state restore; see
   [test evidence](../../captures/ble/2026-11-08-basilisk-v4-hyperspeed/app-dpi-reliability.txt).
3. Use the byte battery scale below 100 as well; leave charging unknown until a
   meaningful charge transition is observed.
4. Preserve the button inventory/defaults above and the correct interleaved lane.
   Expose the three special slots by inferred native-action names (Profile, Hypershift,
   AI Prompt Master), preserving their captured Default blocks. Physical button-to-slot
   correlation remains untested; see the follow-up receiver report.
5. Separate brightness from effect capabilities. A profile with static lighting
   enabled would currently claim more than the successful probes establish.
6. Keep profile CRUD, polling, scroll-mode settings, and custom-frame streaming
   unexposed. No physical sleep/offline/reconnect or power-cycle persistence test
   was performed, and no endurance claim follows from this finite session.

The most valuable later capture is a **single Bluetooth Synapse lighting change**,
including startup/notification subscription and a brightness-only change for
comparison. Next are profile selection/metadata and wheel settings. A brief physical
press check can settle special-button labels without collecting a packet capture.

## Remaining-button follow-up

The connected Bluetooth mouse was revalidated after the receiver pass. Slots 1,
2, 3 and 5 each received a changed mouse-button function; both targets 0/1 returned
the requested current lane, and each original full 16-byte payload was restored
immediately. The scope was pinned to the same peripheral UUID as the first pass,
with a new private journal `/tmp/opensnek-bskv4-bt-remaining-buttons.json`.
See [raw evidence](../../captures/ble/2026-11-08-basilisk-v4-hyperspeed/remaining-buttons-write-restore.txt).

The profile now exposes all twelve inventory entries. Native Default blocks for
Profile/Hypershift/AI remain exact, including the AI button's `00010000000000`
form. No physical button correlation, firmware persistence or Synapse AI-host
behavior is inferred from successful register writes.

The complete app-path hardware gate then passed changed mapping, native Default,
and exact original restore for all twelve slots on both read targets;
[app-path evidence](../../captures/ble/2026-11-08-basilisk-v4-hyperspeed/all-buttons-app-pass.txt).
Early attempts exposed empty successful exchanges after ATT acknowledgements;
the transport now waits for the first vendor notification before idle completion.
The capture README preserves those failures and successful journal recoveries.
