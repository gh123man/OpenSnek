# Basilisk Mobile USB cable and receiver mapping

Date: 2026-11-23. Device: Razer Basilisk Mobile (`RZ01-0431`), USB cable `1532:00D3`, slider
in the off position. macOS host, OpenSnekProbe from the Basilisk Mobile Bluetooth branch.
Contributor validation on owner hardware. The HyperSpeed receiver (`1532:00D4`) was probed the
same day with the mouse in 2.4 GHz mode.

| File | Evidence |
|---|---|
| `probe-log.txt` | Battery, lighting, button, DPI, poll-rate, sleep and brightness reads and writes with restores |

## Findings

- Every command used standard transaction ID `0x1F` and answered status `0x02`.
- Battery `07 80` / `07 84` (via `usb-battery-read`): raw `de` = 87%, charging.
- Lighting: brightness `0F 84 01 04 00` read `ff`; LED `0x00` returned status `0x03`, so the logo
  is LED `0x04`, as on Bluetooth. Static green via `0F 02 01 04 01 00 00 01 00 ff 00` changed the
  logo. Brightness `0F 04 01 04 40` read back and dimmed, then `ff` was restored.
- Brightness 0 latch: after `0F 04 01 04 00` then `ff`, the logo stayed off while `0F 82` and
  `0F 84` reported static green at `ff`. Re-sending `0F 02 01 04 01 00 00 01 00 ff 00` relit it.
  OpenSnek clamps brightness writes to a minimum of 1 for this mouse.
- Buttons: `usb-button-inventory` lists slots 1, 2, 3, 4, 5, 128, 52, 53, 9, 10. Slot 5 set to
  right click on profiles 0 and 1 was press-checked, then restored to the owner's 500 DPI clutch
  `06 05 05 01 f4 01 f4`, which the probe decoded on both profiles.
- DPI: `04 86 01` returns the standard big-endian table (400/800/1600/3200/6400, active stage 3),
  matching the Bluetooth table, so the store is shared. Stage 3 written as 1700 x 1800 through
  `04 06` read back exactly and was restored. Scalar `04 85 01` read 1600.
- Poll rate `00 85` read `01` (1000 Hz); `02` (500 Hz) was written, read back and restored.
- Sleep `07 83` read `00 3c` (60 s, the value set earlier over Bluetooth); 120 s was written, read
  back and restored. USB sleep is big-endian; Bluetooth is little-endian.

## Receiver (`00D4`)

- Same transaction ID `0x1F`. Brightness `0F 84 01 04 00` read `ff` (status `0x02`).
- Static orange via `0F 02 01 04 01 00 00 01 ff 80 00` was accepted and the logo changed after a
  short delay, preceded by what looked like a white flash.
- Poll rate `00 85` read `01` (1000 Hz).
- Battery via `usb-battery-read` returned raw `ff` (100%) twice, including with the mouse awake.
  A raw `07 80` with `--txn 0x1F` also answered `ff` (after one `0x04` timeout while asleep), and
  the owner confirmed the mouse was not full, so the stuck `ff` is the mouse's own report.
  OpenSnek treats `ff` through the receiver as unknown.
- Button inventory `02 84` timed out (status `0x04`) while the mouse was asleep (1 minute sleep
  timeout), then returned the same ten slots as the cable once it was awake.
- `usb-button-inventory` reports `read_failed` for an unregistered PID because the probe takes the
  transaction ID from the profile; the raw read with `--txn 0x1F` succeeded.

## Not tested

Effects other than static over USB, and DPI, sleep and button writes through the receiver.
