# Basilisk V3 Pro — per-LED lighting protocol

**Date:** 2026-06-17
**Hardware:** Razer Basilisk V3 Pro, USB cabled, PID `0x00AA`, firmware `0x02120000`
**Companion log:** [`captures/usb/2026-06-17-basilisk-v3-pro-perled/B-probe-log.md`](../../captures/usb/2026-06-17-basilisk-v3-pro-perled/B-probe-log.md)

## Summary

OpenSnek currently ships the V3 Pro with three lighting zones (`scroll_wheel`, `logo`, `underglow`) driven by `Class 0x0F Cmd 0x02` (Set Effect). This is the OpenRazer-compatible zone-effect path, and it treats the entire underglow strip as a single LED.

The V3 Pro firmware also supports a **second lighting command — `Class 0x0F Cmd 0x03` (Custom Frame)** — that writes per-LED RGB values into a flat 12-cell frame buffer covering all 12 LEDs on the mouse: 1 logo + 1 scroll wheel + **10 underglow**. This command is not documented in the public OpenSnek protocol notes and is not exposed by Razer Synapse either (Synapse exposes 9 underglow zones, so one underglow LED is hidden from official software).

Activating Cmd 0x03 implicitly switches the active effect on the affected LEDs to "custom frame mode", so a single write is enough — no separate switch-effect step is required.

## Command shape

| Field | Value | Notes |
|-------|-------|-------|
| Class | `0x0F` | Same class as the zone-effect path |
| Command ID | `0x03` | Set Custom Frame |
| Data size | `0x04 + 3 × cells` | e.g. `0x25` for 11 cells, `0x28` for 12 cells |
| `args[0]` | Storage | `0x01` (VARSTORE) verified. NOSTORE not yet tested. |
| `args[1]` | Row | **Ignored by firmware.** `0x00` and `0x01` produced identical LED state — `0x01` aliases to row 0. |
| `args[2]` | START_COL | `0x00` valid |
| `args[3]` | END_COL | inclusive; valid `0x00 .. 0x0B` (12 cells). `0x0C+` is accepted but no LED responds |
| `args[4..]` | RGB cells | **`[B, R, G]` triplet order** — Blue byte first, then Red, then Green |

Status byte conventions match the rest of the Razer USB report layout (`0x02` = success, `0x05` = not_supported, `0x03` = failure).

### Byte order pitfall

The triplet order is **`[B, R, G]`**, not the conventional `[R, G, B]`. This was discovered when a 3-phase verification on col 5 showed:

| Args sent (B, R, G) | LED color observed |
|---|---|
| `00, ff, 00` | Red |
| `00, 00, ff` | Green |
| `ff, 00, 00` | Blue |

So to light an LED red, send `00, ff, 00`. To light it blue, send `ff, 00, 00`. This differs from the Static effect path (`Cmd 0x02`), which uses standard `[R, G, B]`. Watch out when bridging values between the two paths.

### Storage semantics for `0x00, 0x00, 0x00`

`0x00, 0x00, 0x00` is an explicit OFF, not "skip this cell". Writing `00,00,00` at all 12 cells turns every LED off, including Logo and Scroll Wheel.

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

This was confirmed by a sequential single-LED sweep where each cell was lit red while every other cell was OFF.

## How this relates to existing OpenSnek code

- `OpenSnek/Sources/OpenSnekCore/DeviceSupport.swift:440-444` defines the three USB lighting zones (`scroll_wheel`, `logo`, `underglow`) with LED IDs `[0x01, 0x04, 0x0A]`. These continue to work via Cmd 0x02 and are unaffected by anything in this document.
- `OpenSnek/Sources/OpenSnekProbe/main.swift:645` already exposes `usb-raw --class 0x0F --cmd 0x03 --args ...` — the probe channel used throughout this investigation. No new transport plumbing is required to ship per-LED control; only profile + UI changes.
- `docs/protocol/USB_PROTOCOL.md:646-663` documents Cmd 0x02 and lists the effect-id table — that table is currently wrong (see below) and Cmd 0x03 is not mentioned at all.

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

- **NOSTORE behavior.** Does `args[0] = 0x00` (NOSTORE) make Cmd 0x03 non-persistent? If yes, this is the right path for software-driven animations (no flash wear).
- **BLE parity.** The BLE vendor protocol probably supports the same operation via key `100F0300` or similar. Worth probing on the BT transport.
- **Other Basilisk variants.** Cmd 0x03 may or may not work on the V3 (`0x0099`), V3 X HyperSpeed (`0x00B9`), and V3 35K (`0x00CB`). All three use the same scroll/logo/underglow zone shape, so a single probe per device should clarify.
- **Logo-side accent lights.** Some Razer mice have additional LEDs on the side of the chassis (e.g., Mamba HyperFlux). The V3 Pro doesn't appear to, but Cmd 0x03's 12-cell limit and the row=0/row=1 alias are worth checking on a device that does.
- **Implementation in OpenSnek.** A separate plan should propose how to expose 10 underglow zones in the UI. Options range from a "Custom underglow strip" mode to a full per-LED color picker. The hardware path is now well understood; the open question is the UX shape.
