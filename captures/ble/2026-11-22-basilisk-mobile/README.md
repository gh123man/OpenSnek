# Basilisk Mobile Bluetooth lighting mapping

Date: 2026-11-22. Device: Razer Basilisk Mobile (`RZ01-0431`), Bluetooth `068E:00D5`.
Razer's guide names the Bluetooth device `BSK MOBILE`; the probe ran without `--name`.
macOS host, OpenSnekProbe from a fresh `main` clone the same day.
Contributor validation on owner hardware; local probe evidence, not Windows captures.

| File | Evidence |
|---|---|
| `probe-log.txt` | Lighting inventory, live and stored zone-state reads, static-red writes with readback, and both power-cycle outcomes |

## Identity

- Bluetooth PID `0x00D5` matches Razer's Windows driver package for the Basilisk Mobile
  (`rzs4lwi_00d3.inf`, `_00d4.inf`, `_00d5.inf`). OpenRazer registers `1532:00D3`
  (wired) and `1532:00D4` (receiver), so `00D5` is the Bluetooth identity.
- Before this profile, OpenSnek's diagnostics reported `Support status: Generic
  best-effort`, `Resolved profile: none`, `Onboard profile count: 1`.

## Findings

- `10 80 00 01` lists a single LED, `0x04`. On this model it is the triple-headed snake
  logo, which doubles as the connection status indicator.
- The V3 Pro zone-state keys answer on LED `0x04`:
  - live colour `10 83 00 04` / `10 03 00 04`
  - stored target 1 colour `10 83 01 04` / `10 03 01 04`
  - brightness read `10 85 01 04` returned `ff`
- Static payload `01 00 00 01 RR GG BB 00 00 00` writes and reads back exactly on both
  the live key and target 1.
- The factory state on both keys is `03 00 00 00 01 00 00 00 00 00`. Byte 0 `03` matches
  the Spectrum effect body documented for the Naga V3 Pro, and the logo was visibly colour
  cycling whenever this payload was read after a power cycle. Byte 4 is not decoded. At the
  first read the owner reported the logo as static green; whether that was the cycle seen
  mid-colour is not established.
- Live writes do not survive a power cycle: the logo returned to the colour cycle and the
  live key read the `03` payload again.
- Battery `05 81 00 01` is byte-scaled: after a drain, OpenSnek and macOS both reported 77%.
  Around power-on it read `ff` (macOS also showed a stale 100%) and once `00`; OpenSnek treats
  `00` as unknown. Charging `05 85 00 01` read `00` on battery and `01` on the cable.
- Brightness `10 05 01 04` dimmed the logo live and read back, but both `10 85 01 04` and
  `10 85 00 04` read `ff` after a power cycle; targets `02` and `03` read `00`.
- Sleep 600 s survived a power cycle. DPI stage 5 at 18,000 read back exactly and was restored.
- Buttons: inventory lists slots 1-5, 9, 10, 52, 53, 128 on both targets. Reads interleave the
  current and factory blocks. Slot 05 written as right click updated both targets, was
  press-checked, and was restored to the owner's 500 DPI clutch. In the app every slot was
  remapped to right click and press-checked, and reversed scroll direction worked.
- Two red flashes appeared at power-on on several boots, including one without any preceding
  write; the cause is not established.
- App integration: with this profile, a colour picked in OpenSnek (orange) was shown after a
  power cycle, confirming the live + target 1 mirror end to end. The app showed only the
  lighting card and battery (100%). With effects, DPI and sleep enabled, the app showed DPI
  stages (read from the mouse), lighting with the effect picker, and power management, with no
  buttons card. Pulse (dual), spectrum and a DPI stage change applied through the app; an
  app-set effect and the changed DPI stage both survived a power cycle.
- Effects: off, spectrum, wave, random breathing, red/blue breathing and green reactive were
  written to the live key with the Naga V3 Pro effect bodies; each ACKed and read back
  unchanged, and the owner reported all rendering (wave as a fast colour cycle). Breathing
  green written to target 1 came back after a power cycle.
- DPI: `0B 84 01 00` returned the 36-byte table 400/800/1600/3200/6400 with active stage ID 3;
  the scalar `0B 81 01 00` read 1600. Stage 3 written as 1700 x 1800 read back on both keys,
  and the original table was restored and verified.
- Sleep: `05 84 00 00` read 300 s; 600 s was written and read back, then 300 s restored.
- Target 1 is the boot state: after writing static red to `10 03 01 04` and power-cycling,
  the logo shows static blue (Bluetooth status) for a few seconds, then static red.

## Procedure notes

- OpenSnekProbe refuses BLE exchanges while the OpenSnek app or its background service
  (`--service-mode`) is running; both were stopped first.
- Several fast off/on cycles left the mouse unconnected to the Mac, and vendor reads timed
  out until it reconnected (once via the pairing combo, left + right + scroll-mode button
  for three seconds). A slower power cycle reconnected normally. The cause is not
  established; it was seen before any app-side writes as well as after.

## Not probed

Onboard profile metadata. The shipped profile keeps onboard profile management hidden.
