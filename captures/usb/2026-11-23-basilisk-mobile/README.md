# Basilisk Mobile USB cable mapping

Date: 2026-11-23. Device: Razer Basilisk Mobile (`RZ01-0431`), USB cable `1532:00D3`, slider
in the off position. macOS host, OpenSnekProbe from the Basilisk Mobile Bluetooth branch.
Contributor validation on owner hardware. The HyperSpeed receiver (`00D4`) was not tested.

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

## Not tested

Effects other than static over USB, the receiver identity, and app-level use on the cable.
