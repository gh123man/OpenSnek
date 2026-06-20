# Basilisk V3 Pro — per-LED lighting protocol

**Date:** 2026-06-17
**Hardware:** Razer Basilisk V3 Pro, USB cabled, PID `0x00AA`, firmware `0x02120000`; updated tail-cell and header-pad validation on PID `0x00AB`, firmware `0x01140000`
**Companion log:** [`captures/usb/2026-06-17-basilisk-v3-pro-perled/B-probe-log.md`](../../captures/usb/2026-06-17-basilisk-v3-pro-perled/B-probe-log.md)

## Summary

OpenSnek currently ships the V3 Pro with three lighting zones (`scroll_wheel`, `logo`, `underglow`) driven by `Class 0x0F Cmd 0x02` (Set Effect). This is the OpenRazer-compatible zone-effect path, and it treats the entire underglow strip as a single LED.

The V3 Pro firmware also supports a **second lighting command — `Class 0x0F Cmd 0x03` (Custom Frame)** — that writes per-LED RGB values into a flat frame buffer. Initial PID `0x00AA` probing confirmed 12 visible cells: 1 logo + 1 scroll wheel + **10 underglow**. Follow-up PID `0x00AB` probing on 2026-06-20 showed two additional responsive tail cells at columns `0x0C..0x0D`, for 14 total cells. Razer Synapse exposes fewer underglow zones than the Custom Frame path.

Activating Cmd 0x03 implicitly switches the active effect on the affected LEDs to "custom frame mode", so a single write is enough — no separate switch-effect step is required. The frame is **volatile**: the mouse does not restore this state after restart, so the current conclusion is that Cmd 0x03 is a software-driven frame-buffer path for live patterns rather than an onboard persistent lighting setting.

## Command shape

| Field | Value | Notes |
|-------|-------|-------|
| Class | `0x0F` | Same class as the zone-effect path |
| Command ID | `0x03` | Set Custom Frame |
| Data size | `0x05 + 3 × cells` | `0x2F` for the 14-cell V3-family frame |
| `args[0]` | Storage byte | `0x01` is accepted, but the resulting Custom Frame state still does not survive mouse restart. |
| `args[1]` | Row | **Ignored by firmware.** `0x00` and `0x01` produced identical LED state — `0x01` aliases to row 0. |
| `args[2]` | START_COL | `0x00` valid |
| `args[3]` | END_COL | inclusive; validated responsive through `0x0D` (14 cells) on PID `0x00AB` firmware `0x01140000` |
| `args[4]` | Reserved/pad byte | Write `0x00`. Omitting this byte shifts the cell stream by one byte. |
| `args[5..]` | RGB cells | **`[R, G, B]` triplet order** |

Status byte conventions match the rest of the Razer USB report layout (`0x02` = success, `0x05` = not_supported, `0x03` = failure).

### Color byte order

The triplet order is conventional **`[R, G, B]`** once the reserved pad byte at `args[4]` is present. A post-pad 3-phase verification showed:

| Args sent (R, G, B) | LED color observed |
|---|---|
| `ff, 00, 00` | Red |
| `00, ff, 00` | Green |
| `00, 00, ff` | Blue |

Earlier unpadded probes falsely suggested a rotated `[B, R, G]` order because the missing pad byte shifted every color stream by one byte.

Triplets begin after the reserved pad byte at `args[4]`. The pad was validated on 2026-06-20 after an unpadded single-cell 50% white probe split into a yellow light-bar LED and a blue scroll-wheel LED; the same probe with the pad lit only the intended light-bar LED in white.

### Storage semantics for `0x00, 0x00, 0x00`

`0x00, 0x00, 0x00` is an explicit OFF, not "skip this cell". Writing `00,00,00` at all cells turns every addressed LED off, including Logo and Scroll Wheel.

### Persistence semantics

Custom Frame writes should be treated as live, software-driven state. A frame written through `Cmd 0x03` changes the LEDs immediately, but the mouse does not restore that frame after restart. This differs from the normal zone-effect/profile paths, where stored settings are expected to survive reconnect or restart when written to the persistent bank.

Until a separate commit/readback mechanism is decoded, OpenSnek should keep this out of the normal app lighting UI and avoid representing it as saved device state. It remains useful for probes, live previews, and future software-driven animations where OpenSnek can stream or reapply frames while running.

## Cell → physical LED map

User-described positions (looking at the mouse from above):

| Cell | Physical position |
|---:|---|
| 0 | Logo |
| 1 | Scroll Wheel |
| 2 | Underglow — left front |
| 3 | Underglow — left, 2nd from front |
| 4 | Underglow — left, 3rd from front |
| 5 | Underglow — left, 4th from front |
| 6 | Underglow — left rear |
| 7 | Underglow — right rear (bottom) |
| 8 | Underglow — right, one above bottom |
| 9 | Underglow — right, one further up |
| 10 | Underglow — right middle |
| 11 | Underglow — right front (the LED Synapse hides) |
| 12 | Underglow tail extension 1 (PID `0x00AB` tail-cell validation) |
| 13 | Underglow tail extension 2 (PID `0x00AB` tail-cell validation) |

Cells `0..11` were confirmed by a sequential single-LED sweep where each cell was lit red while every other cell was OFF. Cells `12..13` were confirmed on 2026-06-20 by writing all-white frames with `END_COL=0x0C` and then `0x0D`: `0x0C` lit an additional tail LED, and `0x0D` made the full tail read white.

## How this relates to existing OpenSnek code

- `OpenSnek/Sources/OpenSnekCore/DeviceSupport.swift` defines the three USB lighting zones (`scroll_wheel`, `logo`, `underglow`) with LED IDs `[0x01, 0x04, 0x0A]`. These continue to work via Cmd `0x02` and are unaffected by anything in this document.
- `OpenSnek/Sources/OpenSnekCore/SoftwareLighting.swift` models the V3-family USB Custom Frame layout as 14 cells, so all software lighting animations render the two tail cells instead of leaving them to stale hardware state.
- `OpenSnekProbe usb-lighting-frame --colors ff0000,00ff00,0000ff --start-col 0 --pid 0x00aa` writes the decoded `Cmd 0x03` Custom Frame path with conventional RGB input and wire triplets. `usb-raw --class 0x0F --cmd 0x03 --args ...` remains available for lower-level experiments.
- `docs/protocol/USB_PROTOCOL.md` now documents both Cmd 0x02's corrected effect-ID table and Cmd 0x03's Custom Frame shape.

## Effect-ID correction (separate fix, same source)

While probing, the effect-ID table in `USB_PROTOCOL.md:655-663` turned out to be wrong on every row. The correct mapping (verified against [tools/python/razer_usb.py:735-758](../../tools/python/razer_usb.py#L735-L758) and live device behavior):

| Effect ID | Actual meaning |
|-----------|----------------|
| `0x00` | Off |
| `0x01` | Static |
| `0x02` | Breathing |
| `0x03` | Spectrum |
| `0x04` | Wave |
| `0x05` | Reactive |

The doc currently says `0x05` = Custom Frame, which led to a false start during the probe. Custom Frame is **not** an effect ID; it is the separate `Cmd 0x03` documented above. The protocol doc should be amended.

## Open questions / follow-up work

- **Near-term software-driven LED effects.** Build the next app-facing pass around live, software-owned effects that stream or reapply Custom Frame data while OpenSnek is running. Treat this as an effects engine/preset surface rather than a persistent hardware lighting editor.
- **Storage byte variants.** `args[0] = 0x01` is accepted but does not make the frame persistent across mouse restart. Test whether `0x00` behaves identically for live software-driven animations.
- **BLE parity.** The BLE vendor protocol probably supports the same operation via key `100F0300` or similar. Worth probing on the BT transport.
- **Other Basilisk variants.** OpenSnek assumes the 14-cell Cmd `0x03` layout for wired V3 (`0x0099`) and V3 35K (`0x00CB`) because they share the scroll/logo/underglow zone shape. V3 X HyperSpeed (`0x00B9`) has a different lighting model and still needs a dedicated probe before exposing Custom Frame software effects.
- **Logo-side accent lights.** Some Razer mice have additional LEDs on the side of the chassis (e.g., Mamba HyperFlux). The V3 Pro doesn't appear to, but Cmd 0x03's 14-cell V3-family range and the row=0/row=1 alias are worth checking on a device that does.
- **Implementation in OpenSnek.** Do not replace the current three-zone lighting UI with Custom Frame editing until there is a product decision around volatile/software-driven lighting. A future UI should likely be a live pattern/preview surface, not a persisted static lighting editor.
