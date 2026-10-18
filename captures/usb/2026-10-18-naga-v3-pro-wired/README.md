# Naga V3 Pro wired USB follow-up (2026-10-18)

Contributor hardware supplied by owner [jpagh](https://github.com/jpagh).
The cable connection enumerates as **`1532:00E7`**, distinct from receiver `00E8`.
It uses the same USB profile, transaction ID `0x1F`, three lighting zones, and
33-button inventory. This is contributor validation, not maintainer/local validation.

## Read-only evidence

See [reads.txt](reads.txt) and [metadata.txt](metadata.txt). No serial read was performed.

| Check | Wired observation |
| --- | --- |
| Firmware `00:81` | payload `01 01 00 00` |
| Poll rate `00:85` | `01` (1000 Hz) |
| DPI `04:85` | `1600x1600` |
| Stages `04:86` | active token `03`, IDs `1...5`, `400/800/1600/3200/50000` |
| Battery / charging | `58%`, charging yes |
| Sleep timeout `07:83` | 60 seconds |
| Inventory `02:84` | Same 33 slots as the receiver, including `106` and `128` |
| Body-button defaults | Slots `11`, `12`, `14`, `106`, `128` match receiver factory blocks on layers `00` and `01` |
| Lighting | LEDs `01`/`04`/`05`: brightness 85; static green |
| Scroll mode `02:94` | status `05` (unsupported) |
| Profile metadata `05:88`, slot 1 / offset 0 | status `03` (rejected) |

## Reversible writes

[write-readback-restore.txt](write-readback-restore.txt) records successful changed-value
writes, readback assertions, and byte-exact baseline restoration for:

- Poll rate: 1000 → 500 → 1000 Hz.
- Independent DPI: 1600x1600 → 800x1600 → 1600x1600.
- Sleep timeout: 60 → 120 → 60 seconds.
- Brightness: 85 → 86 → 85 independently on each of LEDs `01`, `04`, and `05`.
- DPI stages: same-value write/readback, preserving stage IDs, active token, and
  the owner's existing 50,000-DPI fifth stage. The stage table was not reset to
  the older receiver capture's 6400-DPI fifth stage.

The script snapshots each setting immediately before its changed write and
restores it in a `finally` block, then asserts exact readback. It stops on a
failed command/assertion; no command-level retry or transaction-ID sweep is used.
No button mappings were written by the script.

## Owner-confirmed app checks

With PID `00E7` added to the profile and a clean app rebuild, the owner confirmed:

- The wired device is recognized and All Zones Off → Static relights all three zones.
- A temporary rear scroll-button key remap works; Default restores no action.
- Cable unplug is detected as offline, and controls recover after replug.

A separate UI behavior was reported: selecting All Zones after individual-zone
editing displays a color but does not apply it until the color is edited. The
owner confirmed a follow-up build applies immediately, then requested that entering
All Zones seed its color from the first/top zone (scroll wheel), rather than the
last-edited zone. The owner confirmed that refinement works in the next clean
build. Regression coverage checks the outgoing color and all-zone scope, plus
read-only individual-zone navigation. This is distinct from the now-passing
Off → Static scope check.

Bluetooth identity and behavior are a separate validation step.
