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

## Guided physical button identification

On 2026-11-08 (America/New_York), the maintainer pressed each requested physical
control three times while a receiver-only HID listener recorded input reports.
Exact device scope was `1532:00ea:01100000:usb`; the app/service were stopped for
all mutations. Both stored/live originals for slots 14, 57 and 128 were journaled
before changes, and every marker write was read back on both targets.

| Physical control | Slot | Temporary function | Three press times (seconds into capture) | Evidence |
|---|---|---|---|---|
| Frontmost of the three small thumb-side buttons | 128 (`80`) | Left click, `01010100000000` | 23.995, 24.604, 25.397 | [front-side-presses.txt](front-side-presses.txt) |
| Larger thumb paddle/trigger | 57 (`39`) | Middle click, `01010300000000` | 207.381, 207.931, 208.537 | [thumb-paddle-presses.txt](thumb-paddle-presses.txt) |
| Small underside profile button | 14 (`0E`) | Right click, `01010200000000` | 148.667, 149.145, 149.577 | [underside-presses.txt](underside-presses.txt) |

The corresponding input masks were `01`, `04`, and `02`, each followed by release
`00`. Later left clicks used to reply in the chat are retained in the filtered
transcripts but are not part of the three-press sequences. These transcripts keep
button-state changes and omit motion-only reports. The side-button instruction
explicitly excluded the larger paddle, and the underside instruction excluded the
power/connection slider. The maintainer confirmed completion of each sequence.

A first passive pass detected the reference wheel click but no front-side event.
An initial F18/F19/F20 marker pass had successful register readback but no observed
keyboard marker events; it did **not** establish a physical mapping or working
keyboard behavior. Its originals were restored before switching to mouse markers.
No conclusion about the cause of absent keyboard reports is made here.

Both marker passes saved originals before any write, restored stored before live,
and verified all six complete original payloads after restoring. Their final
journals are [keyboard-marker-journal.json](keyboard-marker-journal.json) and
[mouse-marker-journal.json](mouse-marker-journal.json), both `restored`. No command
retry was used. The helper also had a ten-minute automatic restore; this pass was
ended explicitly before that timeout.

The UI now uses Front Side Button, Thumb Paddle and Underside Button. Their
captured native Default blocks are unchanged. Receiver press correlation does not
claim Bluetooth press validation, native Hypershift/profile behavior, keyboard
remap behavior, persistence, or validation of every other physical control.
