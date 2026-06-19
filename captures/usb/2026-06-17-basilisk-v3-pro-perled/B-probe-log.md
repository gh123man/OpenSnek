# V3 Pro Per-LED Probe — final log (2026-06-17)

Device: USB `1532:00aa`, firmware `0x02120000`, transport `usb`.

## Headline result

The Basilisk V3 Pro has **12 individually addressable LEDs** (1 logo + 1 scroll wheel + **10** underglow), all driven by a single Custom Frame command. OpenSnek currently only exposes 3 zones. Razer Synapse exposes 9 underglow zones — meaning the 10th underglow LED is hidden from official software too.

## Protocol details

### Custom Frame write

| Field | Value |
|-------|-------|
| Command class | `0x0F` (matrix lighting) |
| Command ID | `0x03` (Custom Frame) — **not effect-id 0x05** as `USB_PROTOCOL.md` currently claims |
| Payload size | `0x04 + 3 × cells` |
| Storage byte | `0x01` (VARSTORE) — only value tested |
| Row byte | **ignored by firmware** (try `0x00`; `0x01` is silently aliased to row 0) |
| START_COL / END_COL | both inclusive; valid range `0..0x0B` (12 cells) |
| RGB triplet order | **`[B, R, G]`** — Blue first, then Red, then Green |
| Cells beyond `0x0B` | accepted (status `0x02`), but no physical LED — silently dropped |
| Effect activation | implicit — writing a Custom Frame switches the active effect to the frame |

### Effect ID table — `USB_PROTOCOL.md` is currently wrong

Observed via [razer_usb.py:735-758](../../../tools/python/razer_usb.py#L735-L758) and confirmed by replaying static-color writes:

| Effect ID | Actual meaning |
|-----------|----------------|
| `0x00` | Off |
| `0x01` | Static |
| `0x02` | Breathing |
| `0x03` | Spectrum |
| `0x04` | Wave |
| `0x05` | Reactive |
| `0x06`–? | unknown / not enumerated |

`USB_PROTOCOL.md:655-663` lists Wave=`0x01`, Reactive=`0x02`, Breathing=`0x03`, Spectrum=`0x04`, Custom Frame=`0x05`, Static=`0x06` — that's wrong on every line. Custom Frame is not an effect ID at all; it's a separate command (`Cmd 0x03`).

## col → physical LED map

User-described positions (looking at the mouse from above):

| col | Physical LED |
|---:|---|
| 0 | Logo |
| 1 | Scroll Wheel |
| 2 | Underglow — left front (links oben) |
| 3 | Underglow — left, 2nd from front |
| 4 | Underglow — left, 3rd from front |
| 5 | Underglow — left, 4th from front |
| 6 | Underglow — left, back (links 5) |
| 7 | Underglow — right back / bottom (rechts unten) |
| 8 | Underglow — right, one higher |
| 9 | Underglow — right, one higher again |
| 10 | Underglow — right middle |
| 11 | Underglow — right front (oben rechts) — **hidden in Synapse** |

OpenSnek currently treats `0x01` (scroll), `0x04` (logo), and `0x0a` (entire underglow) as the only LED IDs via `Cmd 0x02`. With Cmd 0x03 the underglow becomes 10 separately controllable cells.

## Probe history

### B1 — Sanity: Static via raw channel
`usb-raw --class 0x0F --cmd 0x02 --size 0x09 --args 0x01,0x0A,0x01,0x00,0x00,0x01,0xff,0x00,0x00` → status `0x02`. Underglow flipped from dim white to bright red. ✓ Confirmed: scroll/logo/underglow are exposed via Cmd 0x02 + LED IDs (the OpenSnek path).

### B2 v1 — Class 0x03 Cmd 0x0B (OpenRazer matrix path)
Rejected with status `0x05` (not_supported). The V3 Pro does not use the keyboard-matrix-style address space.

### B2 v2 — Class 0x0F Cmd 0x03 (the actual Custom Frame)
`--class 0x0F --cmd 0x03 --size 0x1F --args 0x01,0x00,0x00,0x08,…9 RGB`. Status `0x02`. Several LEDs lit, including some on the scroll-wheel/logo area — first hint that this command writes a **flat frame across the whole mouse**, not just underglow.

### B3 — Full 11-cell write
`--size 0x25 --args 0x01,0x00,0x00,0x0A,…11 RGB`. Status `0x02`. Initial pass mapped cells to physical positions, but a color anomaly (col 3 yellow → "off") and inconsistent identification led to discovery of the [B,R,G] byte order via the 3-phase verification test on col 5.

### B5 — Sequential single-LED sweep
For each col `i ∈ 0..10`, wrote `00,ff,00` at col i and `00,00,00` elsewhere. User reported a clean position list per col. First run interpreted as `[R,G,B]` was confusing because what we sent as "red" appeared blue. Once the byte order was confirmed as `[B,R,G]`, every col mapped to a distinct physical LED.

### B6 — 12th cell discovery
A static-red probe on cols 2–9 with col 10 = red, scroll/logo off, revealed a dark slot adjacent to col 10 on the right side. Extending to `END_COL = 0x0B` (size `0x28`) with cols 0–10 = `00,00,00` and col 11 = red lit up the previously-dark LED → **col 11 = real LED, the 12th cell**.

### B7 — Verify upper bound
`END_COL = 0x0C` (size `0x2B`) accepted but no new LED responded to col 12. So **12 cells max** per row.

### B8 — Verify row dimension
`ROW = 0x01, END_COL = 0x00, col 0 = red` lit the Logo — the same LED as `ROW = 0 col 0`. **The row byte is aliased / ignored.**

## What this enables

1. OpenSnek can expose **10 underglow zones** (vs the current 1) by issuing one Cmd 0x03 write per state change. No new transport plumbing needed.
2. Scroll wheel and Logo can also be RGB-controlled via this command, which sidesteps the limited effect set on Cmd 0x02 if the UI wants per-LED color.
3. Future feature: full-mouse RGB animations (e.g., wave from front-left to rear-right) become trivial — just write 12 cells per frame.

## Open follow-ups (not part of this probe)

- Test `NOSTORE = 0x00` storage byte to see if Custom Frame supports non-persistent state (useful for animations without flash wear).
- Probe BLE side: vendor key `100F0300` or `10030000` with the same `[B,R,G]` payload — is the BLE protocol identical?
- Other Razer Basilisk variants (V3, V3 35K, V3 X HyperSpeed): same protocol or different?
- Synapse exposes 9 underglow zones — figure out which physical LED Synapse hides, so we can keep parity with their numbering.

## Reset state at end of session

Restored via:
```bash
OpenSnekProbe usb-lighting-effect --kind spectrum --zone all --pid 0x00aa
```
All three OpenSnek zones (scroll/logo/underglow) on Spectrum effect = `Cmd 0x02, ID 0x02, args [VARSTORE, LED, 0x03, 00, 00, 00]`.
