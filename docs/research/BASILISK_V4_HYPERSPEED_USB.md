# Basilisk V4 HyperSpeed USB receiver

Local mapping on 2026-11-08: `1532:00EA`, product name
`Razer Basilisk V4 HyperSpeed`, 90-byte vendor feature reports, transaction `1F`.
[Evidence](../../captures/usb/2026-11-08-basilisk-v4-hyperspeed/README.md).
This is the HyperSpeed receiver; cable PID `00EB` remains unvalidated/unregistered.

## Sources

[DIRT8IKE's OpenRazer PR #2959](https://github.com/openrazer/openrazer/pull/2959),
open at inspection, head `a54e307c2682efc6ad774256ea4c1ddd8bed471c`, supplied the
receiver/cable IDs, polling pair, and separate lighting addresses. Credit DIRT8IKE
for the Windows captures and Linux hardware work described there. Its physical
lighting results are contributor evidence; our results below are local register
readback evidence. The [official Razer support page](https://mysupport.razer.com/app/answers/detail/a_id/21065)
documents the 33K sensor and product features. Neither source is a complete public
USB protocol specification.

## Verified commands

All numbers below are hexadecimal unless explicitly decimal. Responses have the
standard eight-byte header followed by arguments. Successful status is `02`.

| Feature | GET / SET | Arguments and local result |
|---|---|---|
| Poll rate | `00:8E` / `00:0E`, size 2 | `[01, rate]`: `01`=1000, `02`=500, `08`=125 Hz. All three verified. Legacy `00:85` rejects `05`. |
| DPI scalar | `04:85` / `04:05`, size 7 | `[target, X_BE16, Y_BE16, 00, 00]`; live target 0 changed/read back/restored. |
| DPI stages | `04:86` / `04:06`, size 38 decimal | `[target, activeID, count]` then five seven-byte rows. Five, one and three stages verified; 33K X / 32K Y read back exactly. |
| Brightness | `0F:84` / `0F:04`, size 3 | GET `[target, 0A, 00]`, SET `[target, 00, value]`. 85→86→85 decimal verified on targets 0/1. GET LED 00 rejects `03`. |
| Effects | `0F:82` / `0F:02` | Read size 12 decimal; writes use standard extended effect bodies and LED 00. GET echoes `[00,0A,...]` for targets 0/1, LEDs 00/0A. Off, static, spectrum, random/single/dual breathing verified. |
| Sleep | `07:83` / `07:03`, size 2 | Big-endian seconds; 300→301→300 verified. |
| Low battery threshold | `07:81` / `07:01`, size 1 | Raw byte; 77→78→77 verified. Full acceptable range not established. |
| Battery | `07:80`, size 2 | `[00,6C]` initially: 108/255, approximately 42%. |
| Charging | `07:84`, size 2 | `[00,00]` observed. No charge transition tested. |
| Buttons | `02:84` inventory, `02:8C` / `02:0C` | Conventional `[target,slot,layer] + seven-byte function block`. Both targets 0/1 read; ten changed/readback/restore checks. |

DPI row format is `[ID, X_BE16, Y_BE16, opaque0, opaque1]`. Preserve the opaque
bytes, stage IDs, and hidden rows. Baseline IDs are 1–5 with active ID 3, and
400/800/1600/3200/6400 DPI. Unlike BLE's shortened response, USB returns size 38
with zero-filled hidden rows when count is reduced. Those zeros are not an
observed hidden-stage baseline. The app retains previously read full rows only
for the current HID registry handle, merges visible rows, and verifies the visible
write against readback. A new session starting with fewer than five stages refuses
DPI table writes until a complete baseline can be read. It never invents hidden IDs
or writes zero DPI values. Scalar DPI changes do not update the stage table, so
active-stage-only app edits must write the table's active ID too.

## Buttons and lighting

Inventory: `01 02 03 04 05 34 35 0E 39 80 09 0A`, identical to Bluetooth.
Native blocks match the [Bluetooth report](BASILISK_V4_HYPERSPEED_BT.md).
Changed right-click writes and exact restores passed for slots
`03 04 05 34 35 0E 39 80 09 0A`, with stored writes projecting into target 0.
A subsequent primary-button pass changed left and right click to middle click,
verified targets 1/0, and restored each immediately. All 12 advertised button/wheel
actions are now editable. Slots `0E`, `39`, `80` expose Profile, Hypershift and
AI Prompt Master with their exact captured Default blocks `07010400000000`,
`0c013900000000` and `00010000000000` respectively.

Those special names are an **inference**, using native actions plus the
[official Razer device layout](https://mysupport.razer.com/app/answers/detail/a_id/21065)
and [product FAQ](https://www.razer.com/gaming-mice/razer-basilisk-v4-hyperspeed).
Physical button-to-slot correlation is still untested. The AI default is the captured
host-managed no-action block; OpenSnek does not implement Synapse's AI launcher.
The mechanical scroll-mode toggle is absent from the button inventory and remains
outside this remap surface.

USB LED 00 effect writes changed authoritative LED 0A state, unlike the tested
Bluetooth writes. All six exposed effects matched their meaningful body bytes on
both target reads. The returned storage/LED bytes differ from write addresses and
must not be treated as an echo failure. Runtime rendering and power-cycle
persistence remain untested locally. Reactive, wave and software frames are hidden.

## Unexposed features

Profile count/active read 1; inventory `05 01` advertises maximum ID 5 and assigned
ID 1. No create/delete/metadata write or profile switch was attempted. Five advertised
banks do not establish usable CRUD. Wheel GETs `02:94`, `02:96`, `02:97` return `05`
on targets 0/1; no tactile/free-spin/Smart-Reel controls are exposed.

No physical unplug/replug, sleep/wake, charging transition or power-cycle test was
performed. The cable, optional high-polling receiver and dock remain separate,
unvalidated transport identities. Future Synapse captures are most useful for
profile metadata/assignment and special-button behavior; none were required for
this receiver mapping.
