# Naga Pro side-panel physical press validation (2026-10-06)

Device: Razer Naga Pro, 2.4 GHz receiver `1532:0090`, firmware `0x00112100`, USB HID.
Panels pressed: 12-button and 6-button side plates on the same unit.
This session continues `captures/usb/2026-10-05-naga-pro-native-default-banks/`.

## Why this capture exists

PR #121 registered native default blocks for side-panel slots `64-75` and `80-82`, but validation
skipped physical presses on the 12- and 6-button panels because only the 2-button panel was
available. This session covers:

- physical output of every staged native default block on both panels,
- physical label order for both panels (the earlier work assumed 6-button labels `4-6` were
  reversed into slots `85`, `84`, `83`),
- whether slots `83-85` accept remaps physically (they shipped read-only on a class-`0x03` report
  from the original contributor's unit).

## Method

- `usb-button-set-raw` staged the native default blocks on both the persistent (`0x01`) and direct
  (`0x00`) profiles.
- Buttons were pressed in physical label order in a blank TextEdit document; the typed characters
  are the physical evidence.
- Slot `64` was then re-staged through the app `Default` path (`usb-button-set --kind default`) and
  pressed again.
- Every panel slot's block was read back after each step, and the pre-session mappings were
  restored at the end.

## Results

| Panel | Slots | Staged native block | Physical press result |
| --- | --- | --- | --- |
| 12-button | `64-75` | `02 01 00 1e` .. `02 01 00 2e` | labels `1-12` typed `1234567890-=` |
| 6-button | `80-85` | `02 01 00 1e` .. `02 01 00 23` | labels `1-6` typed `123456` |
| 12-button (app `Default` path) | `64` | `02 01 00 1e` | label `1` typed `1` |

## Conclusions

- Both panels map straight from label order to slot order: `64-75` = labels `1-12`, `80-85` =
  labels `1-6`. The prior 6-button reversal note is superseded by this press evidence.
- The 6-button panel's printed numbering wraps around its physical button layout, so mapping the
  buttons by physical position rather than by printed label can look like a reversed order. This
  likely explains the earlier 6-button reversal note; pressing the printed labels in numeric order
  `1-6` maps straight to slots `80-85`.
- Slots `83-85` are physically wired and writable; they were promoted to editable with keyboard
  `4` / `5` / `6` defaults instead of staying read-only.
- The class-`0x03` block seen on the original contributor's unit did not appear here, matching the
  2026-10-05 firmware bank capture.

## Observations

- Five of the twelve `usb-button-set-raw` calls to slots `64-75` reported
  `USB raw button write did not return success`, yet the readback showed every write applied on
  both profiles. This looks like a response-ack timeout in the probe rather than a write failure;
  it was not investigated further in this PR.
- `usb-input-listen --pid 0x0090` only delivered mouse-interface reports on this host:
  keyboard-interface callbacks were not delivered, consistent with macOS Input Monitoring gating.
  Physical evidence is therefore user-observed in TextEdit, the same methodology as section 4 of
  the 2026-10-05 capture.

## Files

- `00-blocks-before.txt` - live persistent + direct blocks for body and panel slots before the session
- `01-12-button-native-default-writes.txt` - staged 12-button defaults and readbacks
- `02-slot64-default-write-app-path.txt` - app `Default` write path on slot `64`
- `03-6-button-native-default-writes.txt` - staged 6-button defaults and readbacks
- `04-restore-originals.txt` - restore writes and final readback for slots `64-75` and `80-85`
