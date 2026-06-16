# Analysis Notes

Scenario: Basilisk V3 Pro connected over Bluetooth, Synapse closed, physical
profile button pressed while BTVS captured for 60 seconds. The user confirmed
the bottom LED advanced.

## Vendor ATT

`summary.md` lists three decoded vendor reads:

```text
01 86 00 00 -> 00 00 00
01 90 00 01 -> 00
05 81 00 01 -> 9c
```

Absolute timestamp filtering places those frames before `captureStart`, so they
are treated as buffered/stale BTVS traffic. No in-window BLE vendor
write/read/notify identified the active profile selected by the hardware cycle.

## Handle 0x001b Notifications

BTVS showed in-window ATT notifications on handle `0x001b`, but decoded them as
malformed/short and did not expose payload bytes. They clustered near the
profile-button activity:

| Cluster | Count | Start | End | Duration |
|---:|---:|---|---|---:|
| `1` | `21` | `21:55:57.009` | `21:55:57.196` | `0.187s` |
| `2` | `73` | `21:56:01.608` | `21:56:02.289` | `0.681s` |
| `3` | `122` | `21:56:08.164` | `21:56:09.969` | `1.805s` |

## HID Companion Sniff

See `hid-profile-cycle-sniff.md`. The HID sniff observed the useful signal:
each physical press produced `04 04 00 00 00 00 00 00 00`, then
`05 05 39 00 00 00 00 00 00` about 200 ms later. Treat those reports as
profile-cycle refresh hints, not decoded target IDs. They are enough to avoid
continuous current-profile polling: use the hint as the event and perform a
debounced one-shot live target `1` fingerprint refresh after it.
