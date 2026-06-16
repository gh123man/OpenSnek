# Synapse Startup Takeover Capture

Scenario: Basilisk V3 Pro connected over Bluetooth, Synapse/AppEngine not
running in the foreground. BTVS capture was started, then
`RazerAppEngine.exe` was launched about 8 seconds into the capture.

Important capture note: BTVS emitted some buffered traffic with packet
timestamps before the wrapper's wall-clock `captureStart`. This analysis uses
only packets between:

```text
captureStart = 2026-06-15T22:45:41.5547028-04:00
captureEnd   = 2026-06-15T22:46:42.8040663-04:00
```

## Synapse Logs

Synapse reported an active software profile during startup:

```text
activeProfile: 18f2a4cc-ecb8-4765-b532-9df401a686d6
name: OS_P5
```

It then logged OBM data and repeated setting/mapping application events,
including `set dpi result`, `setSingleButtonMapping`, `update OBM result`, and
`set OBM result`.

## Startup BLE Shape

The early in-window startup burst includes:

| Rel s | Key | Payload / response | Note |
|---:|---|---|---|
| `14.061` | `08 05 01 00` | write `00`, success | live target apply/control candidate |
| `14.094` | `08 07 01 00` | write `00`, response `50` | live target apply/control candidate |
| `14.122` | `08 06 01 00` | write `00`, success | live target apply/control candidate |
| `14.147` | `0B 04 01 00` | table `100,100,100,100,800` | live DPI projection |
| `14.175` | `00 81 00 00` | `02 32 03 00` | device/profile state read candidate |
| `14.213` | `01 8C 01 00` | `01` | target state check |
| `14.350` | `08 05 01 00` | write `00`, success | repeated live apply/control |
| `14.370` | `08 07 01 00` | write `00`, response `50` | repeated live apply/control |
| `14.394` | `08 06 01 00` | write `00`, success | repeated live apply/control |
| `14.470` | `0B 04 01 00` | table `100,100,100,100,800` | repeated live DPI projection |
| `14.589` | `03 80 00 00` | `01 02 03` | onboard target/profile list candidate |
| `14.670..14.972` | `03 84 02/03 00` | metadata chunks | stored target metadata reads |
| `15.001..15.145` | `0B 81/84 01/02/03 00` | DPI scalar/table reads | live/stored DPI inspection |
| `15.386..17.678` | `08 84 <target> <slot>` | button readbacks | button inventory reads |
| `17.783` | `08 04 01 01` | 10-byte button payload | live target button rewrite |
| `17.880` | `08 04 01 05` | 10-byte button payload | live target Button5 rewrite |
| `18.039` | `08 04 03 05` | 10-byte button payload | stored target `3` Button5 rewrite |

## Profile Button Slot 0x6A

Synapse read the profile-button binding for live/stored targets:

```text
08 84 01 6A -> 6A 00 12 12 01 01 01 01 00 00 00 00 00 00 00 00
08 84 02 6A -> 6A 00 12 12 01 01 01 01 00 00 00 00 00 00 00 00
08 84 03 6A -> 6A 00 12 12 01 01 01 01 00 00 00 00 00 00 00 00
```

No `08 04 <target> 6A` write was observed in the filtered startup window.

## Interpretation

This capture does not show a simple "remap the profile button" command. Synapse
appears to take ownership by:

1. applying/projecting the selected software profile onto live target `1`
2. reading onboard metadata, DPI, and button inventory
3. reading the profile-button binding (`0x6A`) rather than rewriting it
4. rewriting some ordinary button bindings as part of OBM/profile restoration

The startup takeover that makes the profile button behave as software-owned may
therefore be host-side HID event handling, or it may be a side effect of the
`08 05` / `08 07` / `08 06` live apply sequence. A focused capture of pressing
the profile button while Synapse is open is still needed to distinguish those.

For OpenSnek, the firmware-first rule stands: do not copy the Synapse startup
takeover/apply sequence for normal profile monitoring. Use hardware passive HID
hints and active DPI readback instead.
