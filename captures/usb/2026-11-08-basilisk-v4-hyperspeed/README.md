# Basilisk V4 HyperSpeed USB receiver mapping

Local maintainer session, 2026-11-08, `1532:00EA` receiver. The USB-C cable identity
`1532:00EB` was not connected or validated. Firmware response bytes: `01 00 10`.
The running app and service were stopped before probes. All exchanges used the
observed control interface at location `01100000`, transaction `1F`, and the
canonical Swift `USBHIDControlSession` with its per-device process lock. Commands
were serialized; failed commands were not retried with other transaction IDs.

| Evidence | Scope |
|---|---|
| `all-buttons-app-test.txt` | All 12 slots changed through app apply, native Default verified, original stored/live bindings restored |
| `primary-buttons-write-restore.txt` | Left/right click changed to middle click individually, both targets verified, immediate original restore |
| `read-only.txt` | Identity, battery, power, polling, DPI, profile inventory, initial lighting candidates |
| `buttons-lighting-wheel-reads.txt` | Exact-byte Swift reads of both targets, all 12 buttons, lighting and rejected wheel commands |
| `changed-write-restore.txt` | Changed polling, sleep, threshold, brightness, DPI count/X/Y, ten buttons, static lighting; each group restored and all originals checked again |
| `app-integration-test.txt` | Actual app bridge DPI transitions/active-only, polling, lighting, power and remap; journal phase `restored` |
| `effects-and-33k-restore.txt` | All six exposed effect bodies, 33,000/32,000 X/Y, scalar DPI; originals restored |

In the initial CLI transcript, `--args 10` means hex `10`, **not** decimal ten.
The labels ending `-10` in that file therefore describe an extra rejected LED `10`
candidate. The second transcript uses typed Swift bytes and confirms physical LED
`0A`. Command class/ID/size flags in the initial transcript were parsed as integers.

Originals were written before mutation into private `0600` journals
`/tmp/opensnek-bskv4-usb-original.json` and `/tmp/opensnek-bskv4-usb-effects.json`.
Both completed with phase `restored`, with byte-exact comparisons of all 35
captured registers. No serial numbers or profile metadata contents are published.
The temporary Swift helpers remain under `/tmp/bskv4-usb-*.swift`; transcripts
record each request and full response for reproducibility.

**Pass:** changed-write/readback/exact-restore for the scoped settings above.
**Skipped:** visual rendering, physical button presses, unplug/replug, sleep/wake,
power-cycle persistence, cable USB, custom frames and profile CRUD. ACKs alone are
not counted as successful setting validation.

See the [protocol report](../../../docs/research/BASILISK_V4_HYPERSPEED_USB.md)
for addresses, integration decisions and remaining gaps.

The app integration hardware gate also passed and restored all captured settings.
Its private journal is `/tmp/opensnek-bskv4-usb-app-journal.json`; recovery is available
through `HardwareBasiliskV4USBTests` using the normal hardware journal workflow.

## Button follow-up

The primary-button journal `/tmp/opensnek-bskv4-usb-primary-buttons.json` completed
in phase `restored`. Existing evidence already established the three special slots'
changed writes and captured default restores. The support profile now exposes all
12 actions and supplies explicit native Default blocks for slots 14, 57 and 128.
Their control names follow the device's captured actions and official Razer layout;
physical position correlation is still untested.

`HardwareUSBButtonRemapTests.testBasiliskV4AllButtonsAndNativeDefaults` passed on
the receiver. Each of 12 slots received a changed mapping, native Default, and
immediate original restore. Both layers were read after changed/default writes;
all originals were verified again by the journal helper. Private journal:
`/tmp/opensnek-bskv4-all-buttons-app-journal.json`, phase `restored`. Recovery uses
that same test filter and `OPEN_SNEK_HW_RECOVER_JOURNAL` with the exact USB device ID.
