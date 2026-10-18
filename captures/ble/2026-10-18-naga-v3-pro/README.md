# Naga V3 Pro Bluetooth validation (2026-10-18)

Contributor hardware supplied and visually checked by owner
[jpagh](https://github.com/jpagh). macOS HID enumerates **`068E:00E9`**, product
`Naga V3 Pro`, transport `Bluetooth Low Energy`. This remains contributor
validation, not maintainer/local validation.

## Read-only discovery

[reads.txt](reads.txt) and [stages-read.txt](stages-read.txt) record serialized
vendor reads using the existing `...1524` / `...1525` characteristics. Matching
responses use an eight-byte notify header followed by payload fragments. An
unrelated request-1 error header may precede the matching response; it is not
proof that the requested read failed. No serial read was performed.

| Key | Observation |
| --- | --- |
| `0B 84 01 00` | 36-byte DPI read, active token `03`, five stage IDs `1...5`, values `400/800/1600/3200/50000` |
| `05 81 00 01` | Battery raw `C7`; the Naga byte-scale interpretation yields 78%, not independently calibrated in this pass |
| `05 80 00 01` | Status `01` with cable unplugged: do not interpret as charging; use USB fallback or unknown |
| `05 84 00 00` | Sleep timeout `3C 00` (60 seconds, little-endian) |
| `10 80 00 01` | Zone inventory `04 01 05` |
| `10 85 01 <LED>` | Brightness `55` on wheel `01`, logo `04`, and side panel `05` |
| `10 83 00 <LED>` | Ten-byte static-state payload `01 00 00 01 00 FF 00 00 00 00` on each zone |
| `08 84 01 <slot>` | Slots `11/12/14/106/128` match USB factory blocks; 16-byte responses interleave two function-block lanes |
| `03 80 00 00` | Target inventory `01`; profile CRUD is not exposed or claimed |

The raw discovery command `03 82 01 00` also answered `01`, but it is not the
canonical active-target key (`03 82 00 00`) and is not used to claim active-profile
support.

## Changed-value write/readback/restore

[write-readback-restore.txt](write-readback-restore.txt) records successful
changed writes and exact baseline restoration for:

- Sleep timeout `60 → 120 → 60` seconds.
- Per-zone brightness `85 → 86 → 85` on all three LEDs.
- Per-zone static RGB `00FF00 → 112233 → 00FF00` on all three LEDs.
- Active DPI stage `1600x1600 → 1700x1800 → 1600x1600`, preserving every stage ID,
  active token, and the 50,000-DPI tail stage. Writes use the existing 38-byte
  request format; reads omit the final two marker/padding bytes.

[buttons-write-readback-restore.txt](buttons-write-readback-restore.txt) records
rear scroll-button (`128`) key remapping and exact restore independently on live
target `00` and persistent target `01`. The app owner later confirmed the key
physically worked and Default restored no action.

## Lighting effects

[effects-write-readback-restore.txt](effects-write-readback-restore.txt) records
all seven non-static effects on wheel LED `01`, with matching ACK and readback,
followed by exact static-state restoration. The BLE payload omits the USB storage
and LED prefix and is padded to ten bytes. For example:

| Effect | Payload |
| --- | --- |
| Off | `00 00 00 00 00 00 00 00 00 00` |
| Spectrum | `03 00 00 00 00 00 00 00 00 00` |
| Wave | `04 01 28 00 00 00 00 00 00 00` |
| Reactive green | `05 00 02 01 00 FF 00 00 00 00` |
| Pulse random | `02 00 00 00 00 00 00 00 00 00` |
| Pulse single blue | `02 01 00 01 00 00 FF 00 00 00` |
| Pulse dual red/blue | `02 02 00 02 FF 00 00 00 00 FF` |

After these capture-backed effects were exposed in a clean app build, the owner
confirmed that Off → Static, Spectrum, Wave, Reactive after a click, and all
pulse modes render correctly over Bluetooth. Off uses an effect write rather
than brightness zero so Static can relight without a brightness edit.

## Full app and hardware gate

- `OPEN_SNEK_HW=1 swift test --package-path OpenSnek --filter HardwareDpiReliabilityTests`
  passed the real Bluetooth multi/single-stage sequence (one test, zero failures).
  The existing test changes stages and does not restore them itself; the outer
  harness captured the original payload and restored/asserted it in `finally`.
  [hardware-dpi-restore.txt](hardware-dpi-restore.txt) contains the baseline and restore.
- Owner confirmed temporary rear scroll-button remap and Default through the UI.
- Owner confirmed off → offline, back to Bluetooth plus movement → controls recover.
- Owner confirmed approximately two minutes idle followed by movement wakes cleanly
  without repeated reconnect flapping. This is a finite test, not a long-duration claim.

## Isolation and limits

One earlier read-only baseline timed out after the mouse disconnected; no writes
were sent. The owner reconnected it before the successful changed-value sweep.
A later effect capture with the app polling concurrently contained a foreign app
notify header inside a probe payload. The baseline was restored; the final effect
and button captures were made with both app processes stopped, not by adding
command retries. Do not run two BLE configuration clients against this mouse at once.

The new profile reuses the USB 33-slot button table; only the named body-button
reads and rear-button changed writes were repeated over BLE, not an exhaustive
33-slot BLE sweep. Poll rate, onboard profile CRUD, scroll-wheel mode/responsiveness
readout/control, and software-lighting custom frames remain unexposed. Power-cycle
persistence of changed Bluetooth settings was not established; restore-on-connect
remains available when persistence is needed. Wired/receiver findings are separate
captures, not proof of Bluetooth feature support.
