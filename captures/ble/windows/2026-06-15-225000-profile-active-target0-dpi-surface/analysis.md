# Active Target 0 DPI Surface

Scenario: Basilisk V3 Pro connected over Bluetooth, Synapse closed, physical
profile button in firmware/onboard mode.

User slot terminology for this pass:

- slot `0`: live/current profile surface
- slots `1..4`: non-live onboard slots
- only slots `1` and `2` were intentionally mapped for the discriminating DPI
  test
- slot `1`: random DPI table
- slot `2`: mostly `100 DPI` table with one higher stage

## BLE Target Mapping

The DPI-family sweep found these read surfaces:

| OpenSnek term | BLE key family | Meaning |
|---|---|---|
| live/current slot `0` | `0B 81/82/83 00 00` | hardware-active DPI scalar/stages/stage token |
| stored slot `1` | `0B 81/82/83 02 00` | stored slot 1 DPI scalar/stages/stage token |
| stored slot `2` | `0B 81/82/83 03 00` | stored slot 2 DPI scalar/stages/stage token |
| stored slot `3` | `0B 81/82/83 04 00` | stored slot 3, not intentionally mapped in this setup |
| stored slot `4` | `0B 81/82/83 05 00` | stored slot 4, not intentionally mapped in this setup |

`0B 84 01 00` still reads the live/projection table with stage IDs, but it did
not track the hardware profile ring in these captures. Use `0B 82 00 00` for
hardware-active DPI-stage identity.

## Read Family

Read-only `0B` family sweep:

```text
0B 81 00 00 -> d827 d827 0000                         -> active scalar/current pair 10200
0B 82 00 00 -> 3200,10200,1600,7900,1100              -> active stages
0B 83 00 00 -> 02                                      -> active stage token
0B 84 00 00 -> success with empty payload              -> not useful for active stages

0B 81 02 00 / 0B 82 02 00 / 0B 83 02 00 -> stored slot 1 random table
0B 81 03 00 / 0B 82 03 00 / 0B 83 03 00 -> stored slot 2 mostly-100 table
```

## Profile Cycle Evidence

`profile-cycle-active-target0-short-2026-06-15.json`:

| Moment | `0B 82 00 00` active stages | Matched stored slot |
|---|---|---|
| before | `3200, 10200, 1600, 7900, 1100` | stored slot `1` / BLE target `2` |
| after one hardware profile-button cycle | `100, 100, 100, 100, 800` | stored slot `2` / BLE target `3` |

This proves `0B 82 00 00` can identify the hardware-selected profile by matching
its active DPI stage list against stored slot tables when the stored tables are
unique.

`profile-cycle-active-target0-slot2-to-slot3-2026-06-15.json`:

- before active target `0` matched stored slot `2`
- after the press window active target `0` still matched stored slot `2`
- the user clarified slots `3` and `4` were unmapped, so this pass is
  consistent with the firmware skipping/ignoring unmapped slots in this setup

## Implementation Model

For Basilisk V3 Pro Bluetooth:

1. Listen for passive HID profile-cycle hints (`04 04 ...` / `05 05 39 ...`).
2. After a debounced hint, read `0B 82 00 00`.
3. Compare that active stage list with stored slot tables from `0B 82 02 00`
   through `0B 82 05 00`.
4. If exactly one stored slot matches, update OpenSnek's selected onboard slot.
5. If zero or multiple slots match, mark the profile identity ambiguous and use
   another fingerprint axis before claiming an exact selected profile.
