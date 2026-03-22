# Hypershift Hold Capture (2026-03-22)

Capture:
- `captures/ble/hypershift-hold-2026-03-22.pcapng`

Context:
- Windows + BTVS + Wireshark
- Basilisk V3 X HyperSpeed Bluetooth (`VID 0x068E`, `PID 0x00BA`)
- Synapse open
- User action: press and hold the Hypershift/DPI-clutch button three times

## Summary

The capture does not show any BLE vendor button-remap write for slot `0x06`.

Instead, each physical press produces a notify on ATT handle `0x0027`, and each of those press frames is followed almost immediately by a BLE DPI-stage write/readback transaction on the known vendor DPI keys:

- press event handle: `0x0027`
- press payload: `04 52 00 00 00 00 00 00`
- release payload: `04 00 00 00 00 00 00 00`
- DPI write key: `0B 04 01 00`
- DPI read key: `0B 84 01 00`

Inference:
- The Hypershift/DPI-clutch control is still outside the validated `08 04 01 <slot>` BLE button-bind family.
- On this Synapse setup, pressing the button appears to trigger a software-side DPI-stage operation driven by a separate HID/report path rather than by a slot-`0x06` vendor remap command.

## Event Timeline

Press / release pairs on handle `0x0027`:

1. `frame 826` at `7.087599s`: `04 52 00 00 00 00 00 00`
2. `frame 1021` at `8.493477s`: `04 00 00 00 00 00 00 00`
3. `frame 1191` at `9.708451s`: `04 52 00 00 00 00 00 00`
4. `frame 1417` at `11.058458s`: `04 00 00 00 00 00 00 00`
5. `frame 1561` at `11.980954s`: `04 52 00 00 00 00 00 00`
6. `frame 1752` at `13.084130s`: `04 00 00 00 00 00 00 00`

## Correlated DPI Transactions

First press:
- `frame 826`: `0x0027` press `04 52 00 00 00 00 00 00`
- `frame 834`: write header `0E 26 00 00 0B 04 01 00`
- `frame 838`: write payload chunk `02 05 00 90 01 90 01 00 00 01 BC 02 BC 02 00 00 02 40 06 40`
- `frame 842`: write payload chunk `06 00 00 03 80 0C 80 0C 00 00 04 A8 16 A8 16 00 00 00`
- `frame 852`: read header `0F 00 00 00 0B 84 01 00`
- `frames 859-860`: readback payload confirms the same 5-stage table with active token `0x02`

Second press:
- `frame 1191`: `0x0027` press
- `frame 1194`: write header `10 26 00 00 0B 04 01 00`
- `frames 1199, 1204`: write payload chunks
- `frame 1216`: read header `11 00 00 00 0B 84 01 00`
- `frames 1224-1225`: readback payload confirms the same table with active token `0x03`

Third press:
- `frame 1561`: `0x0027` press
- `frame 1564`: write header `12 26 00 00 0B 04 01 00`
- `frames 1568, 1572`: write payload chunks
- `frame 1585`: read header `13 00 00 00 0B 84 01 00`
- `frames 1593-1594`: readback payload confirms the same table with active token `0x04`

Observed staged DPI values in all three write/readback sequences:
- stage 1: `400`
- stage 2: `700`
- stage 3: `1600`
- stage 4: `3200`
- stage 5: `5800`

## Negative Findings

- No `08 04 01 06` ATT write appears anywhere in this focused hold capture.
- No BLE vendor write occurs on release; the paired release event is only the `0x0027` notify carrying `04 00 00 00 00 00 00 00`.
- The usual heartbeat/status handle `0x002B` remains constant throughout:
  - `05 10 00 00 00 00 00 00`

## Comparison With Older Full-HID Capture

Compared with `captures/ble/full-hid-hypershift-cap.pcapng`:
- the same special notify handle `0x0027` is present
- the older press byte was `0x59`
- the March 22 press byte is `0x52`

Inference:
- the second byte of the `0x0027` payload is likely action or mapping dependent
- it does not yet look safe to treat that byte as a fixed physical-button ID without the underlying HID report descriptor
