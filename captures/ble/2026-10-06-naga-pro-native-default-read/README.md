# Naga Pro Bluetooth native-default read spot check (2026-10-06)

Device: Razer Naga Pro over Bluetooth (macOS-connected vendor/product `0x1532` / `0x0092`), with
the 2-button side panel installed during the check (these are protocol-level reads, so the panel in
use does not matter).
This spot check continues PR #121's receiver validation in
`captures/usb/2026-10-06-naga-pro-side-panel-validation/`.

## Why

PR #121 promoted 6-button slots `83-85` to writable and added the byte-3 native-block decode. This
check confirms, read-only, that the Bluetooth path serves the same native side-panel blocks from
the unassigned stored banks. No writes were issued.

## Results

| Target | Button slot | Decoded block | Meaning |
| --- | --- | --- | --- |
| `stored-slot=2` (`target=3`) | `64` | `02 01 00 1e` | keyboard `1` |
| `stored-slot=2` (`target=3`) | `75` | `02 01 00 2e` | keyboard `=` |
| `stored-slot=2` (`target=3`) | `83` | `02 01 00 21` | keyboard `4` |
| `stored-slot=2` (`target=3`) | `84` | `02 01 00 22` | keyboard `5` |
| `stored-slot=2` (`target=3`) | `85` | `02 01 00 23` | keyboard `6` |
| `stored-slot=3` (`target=4`) | `85` | `02 01 00 23` | keyboard `6` |
| `stored-slot=4` (`target=5`) | `85` | no payload (`status=0x03` frames) | bank not readable on this unit over BT |

## Observations

- The first vendor read after system pairing needs a longer timeout than the probe's `900` ms
  default: the 8 s and 10 s attempts completed, while the default timed out before service
  discovery finished.
- `bt-info` reports `none` in a fresh process because the transport creates its `CBCentralManager`
  lazily inside `run()`, so `connectedPeripheralSummaries` sees a nil central. Direct reads work.
- `target=5` answered with `status=0x03` and no decoded payload on two attempts, although the raw
  frames still carry `23 23` (keyboard `6`). The 2026-10-05 receiver capture recorded profiles
  `03`/`04`/`05` as byte-identical, so this may be a Bluetooth target-mapping or bank-visibility
  difference rather than missing data. Out of scope here; targets `3` and `4` cover the slots this
  PR changed.
- Read-only: no device state was modified.

## Files

- `probe-log.txt` - probe transcripts for the reads above
