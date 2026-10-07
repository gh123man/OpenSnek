# Naga Pro side-button HID encoding check (2026-10-05)

Device: Razer Naga Pro on the 2.4 GHz receiver `1532:0090`, firmware `0x00112100`.
Produced by a local wizard script that runs fixed capture windows with the OpenSnek background
service paused and always restores the working button blocks on exit.

## Why

A previous owner's Synapse profile stored the side-panel buttons in a different encoding
(`01 01 01 04 e4` / `01 01 01 05 e4`) than the firmware-native blocks (`01 01 04` / `01 01 05`).
LinearMouse could not see the side buttons as Button 4 / Button 5, so both encodings were compared
with a controlled HID capture (`usb-input-values`).

## Result

| Phase | Slot 4 block | Slot 5 block | Rear press emits | Front press emits |
| --- | --- | --- | --- | --- |
| `10-native.txt` | `01 01 04` | `01 01 05` | **Button 4** x3 | **Button 5** x3 |
| `20-synapse-rear.txt` | `01 01 01 04 e4` | `01 01 05` | **Button 1** x3 | Button 5 x3 |
| `00-controls.txt` | — | — | left click -> Button 1 | right click -> Button 2 |

The Synapse-written block genuinely emits mouse Button 1 (left click). The OpenSnek decode of that
block (`data=[0x01]` -> `.leftClick`) was correct; the stored binding was simply not Button 4 / 5.

## Related decode bug

The same session confirmed the `0x02:0x8C` read layout: `response[10]` is the stored binding's
hypershift/layer flag, not the requested-layer echo, and the 7-byte function block always starts at
`response[11]`. For slots whose stored flag is `1` (slots 1, 2, 3, 9, 10 on this profile), the old
`extractUSBFunctionBlock` window logic shifted one byte left and decoded right-click, middle-click,
and scroll buttons as left click. Regression tests use the raw responses captured here.

Raw files:

- `00-controls.txt`, `10-native.txt`, `20-synapse-rear.txt`: `usb-input-values` event logs
- `original-blocks.txt`: slot 4 / 5 state before the run
- `state-log.txt`: write readbacks during the run
- `usb-info.txt`: device identity
